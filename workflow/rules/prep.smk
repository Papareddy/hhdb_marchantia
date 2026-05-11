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
    script:
        "../scripts/split_proteome.py"

def all_ids(wildcards):
    co = checkpoints.split_proteome.get(**wildcards).output[0]
    return sorted(p.stem for p in Path(co).glob("*.fa"))
