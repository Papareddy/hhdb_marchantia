# Marchantia polymorpha Tak-1 v7.1 — custom HH-suite v3 database

Snakemake pipeline that builds a queryable HH-suite database from the
*M. polymorpha* primary proteome (`MpTak_v7.1.protein.primary.fa`, 18,007 proteins),
following the [HH-suite wiki "Building customized databases" recipe](https://github.com/soedinglab/hh-suite/wiki#building-customized-databases).

Stages: split → hhblits (vs UniRef30) → hhmake → cstranslate → ffindex pack → size-sort + reorder → integrity check.

## Run

```bash
module load devel/miniforge/24.9.2
mamba env create -f environment.yml          # one-time orchestrator env
conda activate hhsuite_marchantia

# first run will auto-build the per-rule hhsuite runtime env
# (workflow/envs/hhsuite.yml) under .snakemake/conda/

# smoke test (default: 20 proteins)
snakemake --profile profiles/slurm -n         # dry-run
snakemake --profile profiles/slurm

# production: edit config.yaml -> mode: "production", then re-run
```

## Why two conda envs

`hhsuite=3.3.0` only ships py3.7-3.9 builds; `snakemake-executor-plugin-slurm>=0.11`
needs py>=3.11. So the orchestrator (snakemake) and the runtime (hhsuite) live in
separate envs, wired via snakemake's per-rule `conda:` directive.

## Layout

See `Snakefile`, `config.yaml`, and `workflow/rules/{prep,msa,pack}.smk`.
