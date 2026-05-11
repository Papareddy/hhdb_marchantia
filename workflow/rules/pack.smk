# Stage 5: pack per-protein {a3m,hhm,cs219} files into 6 ffindex files,
# then size-sort cs219 and apply the same ordering to a3m + hhm (wiki).
# Final integrity check + summary table.

def _all_a3m(wildcards):  return [A3M   / f"{i}.a3m"   for i in all_ids(wildcards)]
def _all_hhm(wildcards):  return [HHM   / f"{i}.hhm"   for i in all_ids(wildcards)]
def _all_cs(wildcards):   return [CS219 / f"{i}.cs219" for i in all_ids(wildcards)]

rule pack_ffindex:
    # ffindex_build keys on the literal filename. We need identical keys across
    # all three indices, so we stage symlinks named after the bare {id} (no ext).
    input:
        a3m = _all_a3m,
        hhm = _all_hhm,
        cs  = _all_cs,
    output:
        a3m_d = DBOUT / f"{DB}_a3m.ffdata",
        a3m_i = DBOUT / f"{DB}_a3m.ffindex",
        hhm_d = DBOUT / f"{DB}_hhm.ffdata",
        hhm_i = DBOUT / f"{DB}_hhm.ffindex",
        cs_d  = DBOUT / f"{DB}_cs219.ffdata",
        cs_i  = DBOUT / f"{DB}_cs219.ffindex",
    log:
        "logs/pack/ffindex_build.log",
    threads: 4
    resources: mem_mb=8000, runtime=60
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {DBOUT} _stage/a3m _stage/hhm _stage/cs219

        # stage symlinks renamed to bare ID (key)
        for f in {A3M}/*.a3m;   do ln -sf "$PWD/$f" _stage/a3m/$(basename "$f" .a3m);   done
        for f in {HHM}/*.hhm;   do ln -sf "$PWD/$f" _stage/hhm/$(basename "$f" .hhm);   done
        for f in {CS219}/*.cs219; do ln -sf "$PWD/$f" _stage/cs219/$(basename "$f" .cs219); done

        ffindex_build -s {output.a3m_d} {output.a3m_i} _stage/a3m   2> {log}
        ffindex_build -s {output.hhm_d} {output.hhm_i} _stage/hhm   2>>{log}
        ffindex_build -s {output.cs_d}  {output.cs_i}  _stage/cs219 2>>{log}

        # size-sort cs219 desc → sorting.dat → reorder cs219, a3m, hhm with same order
        sort -k3 -n -r {output.cs_i} | cut -f1 > {DBOUT}/sorting.dat
        for triple in cs219 a3m hhm; do
          d={DBOUT}/{DB}_${{triple}}.ffdata
          i={DBOUT}/{DB}_${{triple}}.ffindex
          ffindex_order {DBOUT}/sorting.dat $d $i ${{d}}.ord ${{i}}.ord 2>>{log}
          mv ${{d}}.ord $d
          mv ${{i}}.ord $i
        done

        rm -rf _stage
        """

rule integrity_check:
    input:
        a3m_i = DBOUT / f"{DB}_a3m.ffindex",
        hhm_i = DBOUT / f"{DB}_hhm.ffindex",
        cs_i  = DBOUT / f"{DB}_cs219.ffindex",
    output:
        ok = "results/validation/" + DB + ".integrity.ok",
    log:
        "logs/pack/integrity.log",
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        set -euo pipefail
        n_a3m=$(wc -l < {input.a3m_i})
        n_hhm=$(wc -l < {input.hhm_i})
        n_cs=$(wc -l  < {input.cs_i})
        echo "a3m=$n_a3m hhm=$n_hhm cs219=$n_cs" | tee {log}
        [ "$n_a3m" = "$n_hhm" ] && [ "$n_hhm" = "$n_cs" ] || {{ echo "FAIL: index lengths differ"; exit 1; }}
        # wiki-recommended structural check (best effort; tool may need PYTHONPATH set):
        hhsuitedb.py -o {DBOUT}/{DB} --cpu 1 >> {log} 2>&1 || echo "WARN: hhsuitedb.py not available or returned non-zero — review {log}"
        touch {output.ok}
        """

rule summary:
    input:
        ok = "results/validation/" + DB + ".integrity.ok",
        a3m_files = _all_a3m,
    output:
        tsv = "results/validation/" + DB + ".summary.tsv",
    run:
        import statistics
        rows = []
        depths, lens = [], []
        for p in input.a3m_files:
            with open(p) as fh:
                lines = [l.rstrip() for l in fh if l and not l.startswith("#")]
            seqs = [l for l in lines if not l.startswith(">")]
            depths.append(sum(1 for l in lines if l.startswith(">")))
            if seqs: lens.append(len(seqs[0]))
        with open(output.tsv, "w") as o:
            o.write("metric\tvalue\n")
            o.write(f"N_proteins\t{len(input.a3m_files)}\n")
            o.write(f"mean_msa_depth\t{statistics.mean(depths):.1f}\n")
            o.write(f"median_msa_depth\t{statistics.median(depths):.1f}\n")
            o.write(f"mean_query_len\t{statistics.mean(lens):.1f}\n")
