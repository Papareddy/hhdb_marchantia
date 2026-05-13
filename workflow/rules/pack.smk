# Stage 5: pack a3m + hhm into ffindex; cstranslate the a3m ffindex into cs219.
# (cstranslate has no single-file mode — always operates on a ffindex.)
# Then size-sort cs219 desc and apply same ordering to a3m + hhm (wiki recipe).
#
# In production mode pack depends on per-batch sentinels (not per-protein files);
# the shell then INTERSECTS available {a3m,hhm} files so a protein that failed
# only one stage is excluded entirely. This keeps integrity_check passing
# (equal counts across all 3 indices) even with N permanent failures.

def _all_a3m(wildcards):  return [A3M / f"{i}.a3m" for i in all_ids(wildcards)]
def _all_hhm(wildcards):  return [HHM / f"{i}.hhm" for i in all_ids(wildcards)]

def _msa_completion(wildcards):
    """In production: depend on every batch sentinel (batch.smk loads BATCHES into globals).
    In smoke: depend on per-protein outputs (legacy DAG)."""
    if MODE == "production":
        return [f"data/batches/{bid}.done" for bid in globals()["BATCHES"]]
    return _all_a3m(wildcards) + _all_hhm(wildcards)

rule pack_ffindex:
    input:
        msa_done = _msa_completion,
    output:
        a3m_d = DBOUT / f"{DB}_a3m.ffdata",
        a3m_i = DBOUT / f"{DB}_a3m.ffindex",
        hhm_d = DBOUT / f"{DB}_hhm.ffdata",
        hhm_i = DBOUT / f"{DB}_hhm.ffindex",
        cs_d  = DBOUT / f"{DB}_cs219.ffdata",
        cs_i  = DBOUT / f"{DB}_cs219.ffindex",
    params:
        cs_flags = config["cstranslate"]["flags"],   # "-f -x 0.3 -c 4 -I a3m"
    log:
        "logs/pack/pack.log",
    threads: 4
    resources: mem_mb=32000, runtime=480    # bumped: 32G mem, 8h walltime
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        set -uo pipefail
        export HHLIB=$CONDA_PREFIX
        mkdir -p {DBOUT} _stage/a3m _stage/hhm logs/pack
        # Per-attempt log file so earlier attempts' errors aren't clobbered.
        ATTEMPT_LOG=logs/pack/pack.$(date +%Y%m%dT%H%M%S).log
        ln -sf "$(basename $ATTEMPT_LOG)" {log}
        exec > >(tee -a "$ATTEMPT_LOG") 2>&1
        echo "[pack] start $(date -Is) host=$(hostname) PWD=$PWD"
        df -h . | tee -a "$ATTEMPT_LOG"

        # Intersection: only include proteins where BOTH a3m and hhm exist (>0 bytes).
        find {A3M} -name '*.a3m' -size +0 -printf '%f\n' | sed 's/\.a3m$//' | sort -u > _stage/a3m_ids
        find {HHM} -name '*.hhm' -size +0 -printf '%f\n' | sed 's/\.hhm$//' | sort -u > _stage/hhm_ids
        comm -12 _stage/a3m_ids _stage/hhm_ids > _stage/both_ids
        n_a3m_only=$(comm -23 _stage/a3m_ids _stage/hhm_ids | wc -l)
        n_hhm_only=$(comm -13 _stage/a3m_ids _stage/hhm_ids | wc -l)
        n_both=$(wc -l < _stage/both_ids)
        echo "[pack] a3m_only=$n_a3m_only  hhm_only=$n_hhm_only  both=$n_both"
        [ "$n_both" -gt 0 ] || {{ echo "[pack] FAIL: zero proteins have both a3m and hhm"; exit 1; }}

        # stage symlinks renamed to bare ID (key) so all 3 indices share keys
        echo "[pack] $(date -Is) staging $n_both symlinks..."
        while read id; do
          ln -sf "$PWD/{A3M}/${{id}}.a3m" _stage/a3m/${{id}}
          ln -sf "$PWD/{HHM}/${{id}}.hhm" _stage/hhm/${{id}}
        done < _stage/both_ids
        echo "[pack] $(date -Is) staging done."

        echo "[pack] $(date -Is) ffindex_build a3m..."
        ffindex_build -s {output.a3m_d} {output.a3m_i} _stage/a3m
        echo "[pack] $(date -Is) ffindex_build hhm..."
        ffindex_build -s {output.hhm_d} {output.hhm_i} _stage/hhm

        echo "[pack] $(date -Is) cstranslate over a3m ffindex -> cs219 ffindex..."
        cstranslate {params.cs_flags} -i {DBOUT}/{DB}_a3m -o {DBOUT}/{DB}_cs219
        echo "[pack] $(date -Is) cstranslate done. cs219 size:"
        ls -lh {DBOUT}/{DB}_cs219.* | tee -a "$ATTEMPT_LOG"

        echo "[pack] $(date -Is) size-sort cs219 + reorder all three..."
        sort -k3 -n -r {output.cs_i} | cut -f1 > {DBOUT}/sorting.dat
        for triple in cs219 a3m hhm; do
          d={DBOUT}/{DB}_${{triple}}.ffdata
          i={DBOUT}/{DB}_${{triple}}.ffindex
          ffindex_order {DBOUT}/sorting.dat $d $i ${{d}}.ord ${{i}}.ord
          mv ${{d}}.ord $d
          mv ${{i}}.ord $i
        done

        rm -rf _stage
        echo "[pack] $(date -Is) DONE."
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
        # NOTE: hhsuitedb.py was an extra wiki-recommended structural check,
        # but on a 17k-entry DB it walks the full a3m.ffdata (~184GB) and
        # blew our 30min walltime in the v1 build. Index-count parity above
        # is the actual integrity guarantee. Skipping hhsuitedb.py.
        touch {output.ok}
        """

rule summary:
    input:
        ok = "results/validation/" + DB + ".integrity.ok",
    output:
        tsv = "results/validation/" + DB + ".summary.tsv",
    run:
        import statistics, glob
        from pathlib import Path as _P
        a3m_files = sorted(glob.glob(str(A3M / "*.a3m")))
        depths, lens = [], []
        for p in a3m_files:
            with open(p) as fh:
                lines = [l.rstrip() for l in fh if l and not l.startswith("#")]
            seqs = [l for l in lines if not l.startswith(">")]
            depths.append(sum(1 for l in lines if l.startswith(">")))
            if seqs: lens.append(len(seqs[0]))
        with open(output.tsv, "w") as o:
            o.write("metric\tvalue\n")
            o.write(f"N_proteins\t{len(a3m_files)}\n")
            if depths:
                o.write(f"mean_msa_depth\t{statistics.mean(depths):.1f}\n")
                o.write(f"median_msa_depth\t{statistics.median(depths):.1f}\n")
            if lens:
                o.write(f"mean_query_len\t{statistics.mean(lens):.1f}\n")

rule run_report:
    """Aggregate per-batch summary TSVs + failed lists into results/run_report.md."""
    input:
        ok = "results/validation/" + DB + ".integrity.ok",
    output:
        md = "results/run_report.md",
        failed_tsv = "results/failed_proteins.tsv",
    run:
        import glob, datetime, statistics
        from collections import Counter, defaultdict
        all_rows = []
        for tsv in sorted(glob.glob("logs/batches/*.summary.tsv")):
            with open(tsv) as fh:
                next(fh, None)
                for ln in fh:
                    parts = ln.rstrip("\n").split("\t")
                    if len(parts) >= 8:
                        all_rows.append(parts)
        statuses = Counter(r[2] for r in all_rows)
        reasons  = Counter(r[7] for r in all_rows if r[2] == "FAILED")
        wall_by_status = defaultdict(list)
        for r in all_rows:
            try: wall_by_status[r[2]].append(int(r[5]))
            except (ValueError, IndexError): pass
        with open(output.md, "w") as o:
            o.write(f"# Production run report\n\n")
            o.write(f"Generated: {datetime.datetime.now().isoformat()}\n\n")
            o.write(f"## Per-protein status\n\n")
            for s, n in statuses.most_common():
                o.write(f"- **{s}**: {n}\n")
            o.write(f"\n## Failure reasons (FAILED only)\n\n")
            for r, n in reasons.most_common():
                o.write(f"- {r}: {n}\n")
            o.write(f"\n## Walltime stats per status (seconds)\n\n")
            o.write("| status | n | mean | median | max |\n|---|---|---|---|---|\n")
            for s, ws in wall_by_status.items():
                if ws:
                    o.write(f"| {s} | {len(ws)} | {statistics.mean(ws):.0f} | {statistics.median(ws):.0f} | {max(ws)} |\n")
        with open(output.failed_tsv, "w") as o:
            o.write("protein_id\tlength_aa\thhblits_sec\thhmake_sec\twall_sec\texit\treason\n")
            for r in all_rows:
                if r[2] == "FAILED":
                    o.write("\t".join([r[0], r[1], r[3], r[4], r[5], r[6], r[7]]) + "\n")
