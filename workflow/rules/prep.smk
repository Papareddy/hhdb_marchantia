# Stage 1: split primary proteome FASTA into per-protein files.
# Uses a checkpoint so downstream rules can discover IDs after the split.

checkpoint split_proteome:
    input:
        fa = config["proteome_fa"],
    output:
        directory("data/queries"),
    params:
        mode = MODE,
        n    = config.get("smoke_n", 20),
    log:
        "logs/prep/split_proteome.log",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {output}
        if [ "{params.mode}" = "smoke" ]; then
            seqkit head -n {params.n} {input.fa} \
              | seqkit split -s 1 -O {output} --by-id-prefix "" --quiet -
        else
            seqkit split -s 1 -O {output} --by-id-prefix "" --quiet {input.fa}
        fi
        # seqkit names files like "stdin.part_001_<id>.fasta" or similar; rename to {id}.fa
        ( cd {output} && for f in *.fasta *.fa 2>/dev/null; do
            id=$(head -n1 "$f" | sed 's/^>//' | awk '{{print $1}}')
            [ -n "$id" ] && [ "$f" != "${{id}}.fa" ] && mv "$f" "${{id}}.fa" || true
          done ) 2>{log} || true
        ls {output}/*.fa | wc -l >> {log}
        """

def all_ids(wildcards):
    co = checkpoints.split_proteome.get(**wildcards).output[0]
    return sorted(p.stem for p in Path(co).glob("*.fa"))
