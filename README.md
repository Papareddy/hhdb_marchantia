# Marchantia polymorpha Tak-1 v7.1 — custom HH-suite v3 database

A reproducible Snakemake pipeline that builds a queryable HH-suite v3 profile
database from the *Marchantia polymorpha* Tak-1 v7.1 primary-isoform proteome
(`MpTak_v7.1.protein.primary.fa`, 18,007 proteins). MSAs are seeded against
[UniRef30](https://wwwuser.gwdg.de/~compbiol/uniclust/) (release 2023_02).

The build is the wiki-canonical procedure
([HH-suite wiki: Building customized databases](https://github.com/soedinglab/hh-suite/wiki#building-customized-databases))
adapted to a snakemake fan-out on a SLURM cluster (bwHPC Helix), with
length-tiered batching, atomic per-protein writes, structured TSV logs, and
per-rule conda envs.

- **Repo**: https://github.com/Papareddy/hhdb_marchantia
- **DB tarball**: hosted on Zenodo (DOI assigned after the build completes — see [docs/DOWNSTREAM_USAGE.md](docs/DOWNSTREAM_USAGE.md))

> **For users who just want to query the DB**: see the companion repo
> `marchantia_hhdb_user/` (created post-build) — it bundles the Zenodo DOI
> + a `Makefile` to fetch/verify + a one-line `hhsearch` wrapper. No need
> to clone this build pipeline.

---

## Quick start

### Prerequisites
- bwHPC Helix (or any SLURM cluster) with the `devel/miniforge/24.9.2` module
- An active SLURM account; ~250 GB free scratch
- ~100 core-hours per protein × 18 k proteins ≈ ~3 k–9 k core-hours total
  (depending on hhblits flags and protein lengths)

### 1. Set up the orchestrator env (one time)
```bash
module load devel/miniforge/24.9.2
mamba env create -f environment.yml
conda activate hhsuite_marchantia
```

The runtime env (`workflow/envs/hhsuite.yml`, contains `hhsuite=3.3.0`) is
built automatically by snakemake on first run via `--use-conda`.

### 2. Get the proteome
Download `MpTak_v7.1.protein.primary.fa` from
[marchantia.info](https://marchantia.info) → `data/proteome/`.

### 3. Get UniRef30 (~65 GB compressed → ~250 GB unpacked)
```bash
cd data/reference
wget -c https://wwwuser.gwdg.de/~compbiol/uniclust/current_release/UniRef30_2023_02_hhsuite.tar.gz
tar -xzf UniRef30_2023_02_hhsuite.tar.gz
md5sum -c UniRef30_2023_02.md5sums
```

### 4. Smoke test (recommended first)
```bash
# config.yaml: mode: "smoke", smoke_n: 10  (default)
snakemake --profile profiles/slurm -n      # dry-run
snakemake --profile profiles/slurm         # ~15 min on cpu-single
```
Validate `data/db/marchantia_v7.1_*.{ffdata,ffindex}` exist and
`results/validation/*.summary.tsv` reports sensible numbers.

### 5. Production
```bash
# Edit config.yaml: mode: "production"
# Or pass on CLI:
snakemake --profile profiles/slurm --config mode=production
```
Estimated wall: ~4–5 days on bwHPC Helix `cpu-single` with `--jobs 40`.

---

## Architecture

### The 6 ffindex files of an HH-suite DB
At query time, `hhsearch`/`hhblits` consume:
- `<db>_cs219.{ffdata,ffindex}` — column-state sequences (cheap **prefilter**)
- `<db>_a3m.{ffdata,ffindex}`   — A3M MSAs (loaded for surviving prefilter hits)
- `<db>_hhm.{ffdata,ffindex}`   — HMM profiles (used in Viterbi/realignment)

The cs219 index **must be size-sorted descending** so the prefilter's
load-balancer can split work evenly — this is the load-balancer requirement
the wiki calls out specifically.

### Build stages

```
proteome.fa → split → per-protein .fa
                         ↓
                    batch_msa  (production: tiered)
                         ↓
                    {a3m,hhm} per protein
                         ↓
                    pack_ffindex
                      ├─ build a3m + hhm ffindex
                      ├─ cstranslate over a3m ffindex → cs219 ffindex
                      └─ size-sort cs219, reorder all 3
                         ↓
                    integrity_check + summary + run_report
```

### Length-tiered batching (production only)

Naive 1-job-per-protein = 54,021 SLURM jobs (over the per-user `MaxSubmitPU=1500`
limit) AND wallclock kill risk on outliers (max protein = 9,376 AA).
Solution: **partition by length first, then chunk**.

| Tier | length range | # proteins | proteins/batch | wall | cpu | mem |
|---|---|---|---|---|---|---|
| small  | <800 AA      | 15,850 (88%) | 30 | 5 h | 4 | 16 G |
| medium | 800–1500     | 1,785 (10%)  | 10 | 6 h | 4 | 16 G |
| large  | 1500–3000    | 326 (2%)     |  4 | 6 h | 4 | 24 G |
| giant  | ≥3000        | 46 (0.3%)    |  1 | 4 h | 8 | 32 G |
|        | **total batches** | | | | | **836** |

Defined in `config.yaml` → `tiers:`. Computed by
`workflow/scripts/make_batches.py` at parse time.

### Per-batch script: `workflow/scripts/run_batch.sh`
For each protein in the batch, in order:
1. **Idempotent skip** if both `data/a3m/{id}.a3m` and `data/hhm/{id}.hhm` already exist with size > 0.
2. **`timeout 20m hhblits`** (configurable via `per_protein_timeout`). Stuck protein → killed, logged, loop continues.
3. **`hhmake -M a3m`** (see [Design decisions](docs/DESIGN.md) for why `-M a3m`).
4. **Atomic promote**: `.tmp → final` only if BOTH stages succeed (no half-files).
5. **`SIGUSR1` trap**: SLURM sends USR1 5 min before walltime (`--signal=B:USR1@300`); the loop drains gracefully after the current protein, so a walltime-killed batch leaves no partial state.
6. **Structured TSV log**: one row per protein in `logs/batches/{batch_id}.summary.tsv`:
   ```
   protein_id  length_aa  status  hhblits_sec  hhmake_sec  wall_sec  exit  reason
   ```

### Failure handling (three layers)
1. **Per-protein** (in the bash loop): timeout, atomic write, idempotent skip.
2. **Per-batch** (snakemake): `--restart-times 1`, `--keep-going`.
3. **End-of-run reconciliation**: re-run `snakemake` — auto-detects missing per-protein outputs and re-submits only the affected batches; idempotent skip means already-done proteins inside re-tried batches are instant no-ops.

The `pack_ffindex` rule then **intersects** `data/a3m/*.a3m` ∩ `data/hhm/*.hhm` so proteins that permanently failed at one stage are excluded entirely — `integrity_check` still passes (equal counts across all 3 indices).

### Fair-share friendliness (bwHPC)
- `--jobs 40` — caps concurrent submissions
- `--max-jobs-per-second 1` — polite scheduler rate
- Tier-aware walltime — no batch holds the queue waiting on one length outlier
- Per-batch `mem_mb` sized so we never stack too much RAM on a node

---

## Layout

```
hhdb_marchantia/
├── README.md                          this file
├── Snakefile                          top-level (5 includes)
├── config.yaml                        all knobs (modes, tiers, params)
├── environment.yml                    orchestrator env (snakemake 9.20)
├── docs/
│   ├── DESIGN.md                      design decisions: why this, not that
│   ├── DOWNSTREAM_USAGE.md            how end-users query the DB
│   ├── TROUBLESHOOTING.md             common errors + fixes
│   └── REFERENCES.md                  HH-suite + Marchantia citations
├── profiles/slurm/config.yaml         bwHPC Helix SLURM executor profile
├── workflow/
│   ├── envs/hhsuite.yml               runtime env (hhsuite 3.3.0, py3.9)
│   ├── rules/
│   │   ├── prep.smk                   split_proteome (checkpoint)
│   │   ├── msa.smk                    smoke per-protein hhblits / hhmake
│   │   ├── batch.smk                  PRODUCTION tiered batch_msa
│   │   └── pack.smk                   ffindex pack + cstranslate + sort + integrity + summary + run_report
│   └── scripts/
│       ├── split_proteome.py          fasta → per-protein {id}.fa
│       ├── make_batches.py            length-tier + chunk → batches.json
│       └── run_batch.sh               per-batch worker (atomic, idempotent, USR1-aware)
├── data/                              (gitignored — populated at runtime)
│   ├── proteome/                       MpTak_v7.1.protein.primary.fa
│   ├── reference/                      UniRef30_2023_02_*.{ffdata,ffindex}
│   ├── queries/                        per-protein {id}.fa
│   ├── a3m/                            per-protein {id}.a3m
│   ├── hhm/                            per-protein {id}.hhm
│   ├── batches/                        batches.json + per-batch sentinels + .failed lists
│   └── db/                             FINAL DB: marchantia_v7.1_{a3m,hhm,cs219}.{ffdata,ffindex}
├── logs/                              (gitignored)
│   ├── production_run.log              snakemake driver log
│   ├── batches/{batch_id}.summary.tsv  per-protein structured row (the forensic gold)
│   ├── hhblits/{id}.log                raw hhblits stderr per protein
│   └── hhmake/{id}.log                 raw hhmake stderr per protein
└── results/                           (gitignored)
    ├── validation/                     integrity sentinel + summary tsv
    ├── failed_proteins.tsv             aggregated failure list
    └── run_report.md                   final markdown report
```

---

## Two conda envs (rationale)

`hhsuite=3.3.0` (bioconda) ships only py3.7–3.9 builds; `snakemake-executor-plugin-slurm>=0.11`
needs py≥3.11. They cannot coexist in a single env. So:
- **orchestrator** (`environment.yml`): snakemake 9.20 + slurm executor + py3.11
- **runtime** (`workflow/envs/hhsuite.yml`): hhsuite 3.3.0 + py3.9

Wired via snakemake's per-rule `conda:` directive + `--use-conda`.

## Forensic logging

Every protein has a row in `logs/batches/{batch_id}.summary.tsv`. Search across the whole run:

```bash
grep "Mp1g00210.1" logs/batches/*.summary.tsv     # → which batch, status, timing
cat logs/hhblits/Mp1g00210.1.log                  # → raw hhblits stderr
cat logs/hhmake/Mp1g00210.1.log                   # → raw hhmake stderr
```

After production, `results/run_report.md` aggregates: counts by status, failure
reasons, walltime stats per status. `results/failed_proteins.tsv` is the
machine-readable failed list.

## Citations

If you use this database or pipeline, please cite:

- **HH-suite3**: Steinegger M *et al.* (2019) *BMC Bioinformatics* 20:473.
- **UniRef30 / Uniclust30**: Mirdita M *et al.* (2017) *Nucleic Acids Res.* 45:D170-D176.
- **Marchantia Tak-1 v7.1 genome**: Iwasaki M *et al.* (TODO: fill in once published).
- **Snakemake**: Mölder F *et al.* (2021) *F1000Research* 10:33.

---

## License

MIT — see `LICENSE`.

## Authors

Ranjith Papareddy (`ranjith.bbt@gmail.com`)
