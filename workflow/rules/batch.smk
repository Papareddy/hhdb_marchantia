# Production stage: per-batch wrapper that runs hhblits+hhmake serially over
# a chunk of proteins, with structured per-protein logging.
# Batches are length-tiered (see workflow/scripts/make_batches.py + config.yaml).

import json
from pathlib import Path

# ---- load batches manifest (built once via `make_batches.py`) ----
_BATCHES_PATH = Path("data/batches/batches.json")

def _ensure_batches_json():
    """Generate the batches manifest from the FASTA + tier config if missing."""
    if _BATCHES_PATH.exists():
        return
    _BATCHES_PATH.parent.mkdir(parents=True, exist_ok=True)
    import subprocess, sys
    subprocess.check_call([
        sys.executable, "workflow/scripts/make_batches.py",
        config["proteome_fa"],
        json.dumps(config["tiers"]),
        str(_BATCHES_PATH),
    ])

_ensure_batches_json()
_MANIFEST = json.loads(_BATCHES_PATH.read_text())
LENGTHS = _MANIFEST["lengths"]   # {protein_id: aa_length}
BATCHES = _MANIFEST["batches"]   # {batch_id: [protein_id, ...]}

def _tier_name(batch_id: str) -> str:
    return batch_id.split("_")[0]

def _tier_cfg(batch_id: str) -> dict:
    name = _tier_name(batch_id)
    for t in config["tiers"]:
        if t["name"] == name:
            return t
    raise KeyError(f"no tier config for {name!r} (batch_id={batch_id})")

def _batch_fastas(wildcards):
    return [str(QDIR / f"{i}.fa") for i in BATCHES[wildcards.batch_id]]

rule batch_msa:
    input:
        fastas = _batch_fastas,
        queries_dir = QDIR,                       # ensures split_proteome ran
    output:
        done = "data/batches/{batch_id}.done",
        tsv  = "logs/batches/{batch_id}.summary.tsv",
    log:
        "logs/batches/{batch_id}.batch.log",
    threads: lambda wc: int(_tier_cfg(wc.batch_id)["cpus"])
    resources:
        mem_mb           = lambda wc: int(_tier_cfg(wc.batch_id)["mem_mb"]),
        runtime          = lambda wc: int(_tier_cfg(wc.batch_id)["runtime_min"]),
        slurm_partition  = lambda wc: config["slurm"]["partition_short"],
        slurm_extra      = "--signal=B:USR1@300",
    params:
        uniref      = config["uniref30_prefix"],
        iters       = config["hhblits_prod"]["iters"],
        evalue      = config["hhblits_prod"]["evalue"],
        hhb_extra   = config["hhblits_prod"]["extra"],
        per_timeout = config["per_protein_timeout"],
        hhmake_m    = config["hhmake"]["match_assign"],
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        export HHLIB=$CONDA_PREFIX
        export UNIREF30_PREFIX={params.uniref:q}
        export HHBLITS_ITERS={params.iters}
        export HHBLITS_EVALUE={params.evalue}
        export HHBLITS_EXTRA={params.hhb_extra:q}
        export PER_PROTEIN_TIMEOUT={params.per_timeout}
        export HHMAKE_M={params.hhmake_m}
        bash workflow/scripts/run_batch.sh \
            {output.done} {output.tsv} {input.fastas} > {log} 2>&1
        """
