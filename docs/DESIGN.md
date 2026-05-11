# Design decisions

Notes on the non-obvious choices. Each decision lists the alternative we considered, why we picked this one, and where the wiki helped or hurt.

## 1. snakemake fan-out vs MPI-batched (option A vs B)

**Wiki canonical**: `mpirun -np N hhblits_mpi -i <db>_fas ...` over a single ffindex of FASTAs. Three SLURM submissions total.

**Our choice (A)**: snakemake fan-out → one SLURM job per **batch** of proteins (length-tiered).

**Why not the wiki way?** The bioconda `hhsuite=3.3.0` package ships **no `_mpi` variants** (we verified: `ls $CONDA_PREFIX/bin/*mpi` returns nothing). Using the wiki recipe would require building hh-suite from source against `compiler/gnu/13.3 + openmpi/4.1`, which adds a moving piece without large benefit at our scale. Snakemake fan-out also gives:
- per-protein fault isolation (a single bad protein doesn't kill the run)
- granular restart (re-run snakemake → only missing outputs redo)
- simpler logging (per-protein TSV row)

## 2. Length-tiered batching, not flat batch_size

The Marchantia proteome is heavy-tailed: median 325 AA, max 9,376 AA (~29× median). hhblits wallclock scales roughly linearly with query length, so a flat batch of 30 with one giant protein blows the walltime.

Instead we partition into 4 length tiers (small/medium/large/giant) with tier-specific `chunk_size` and `runtime_min`. Defined in `config.yaml`. See main README for the table.

## 3. `hhmake -M a3m`, not the wiki default `-M first`

**Wiki recipe**: `hhmake -i stdin -o stdout -v 0` — implicit `-M first` (match columns anchored to query positions).

**Our finding**: `-M first` (and `-M 50`, `-M 30`, with or without prior `hhfilter`/`reformat.pl`) reproducibly fails on hhblits 3.3.0 output for ~99% of our proteins:
```
ERROR: sequences in {a3m} do not all have the same number of columns,
e.g. first sequence and sequence UniRef100_X.
```
This is `hhalignment.cpp:1244 Compress`. We checked the A3Ms with a Python parser counting `(uppercase + '-')` per record — column counts were equal across all 4,762 sequences. So hhmake's `Compress` is computing columns differently than the A3M format spec implies.

**`-M a3m`** tells hhmake to **trust the A3M's own match-state encoding** (uppercase=match, lowercase=insert) without recomputing. It produces the .hhm cleanly. We picked it as the production default and noted this in `config.yaml`.

## 4. cstranslate at pack stage, not per protein

**Wiki recipe**: `cstranslate ... -I a3m -i <db>_a3m -o <db>_cs219` — operates on the full A3M ffindex.

**First attempt**: per-protein cstranslate rule (`cstranslate -i {id}.a3m -o {id}.cs219`).

**Failed**: cstranslate has **no single-file mode** — it always tries to open `<input>.ffdata`/`<input>.ffindex`. Even with no `-I` flag, it errors with `could not open file '{id}.a3m.ffdata'`.

**Fix**: drop the per-protein cstranslate rule entirely. Build the A3M ffindex first (in `pack_ffindex`), then run cstranslate over that ffindex in one shot. This matches the wiki recipe.

## 5. ffindex key normalization (the gotcha the wiki doesn't mention)

`ffindex_build -d <dir>` keys on the literal filename — including the extension. So:
- `ffindex_build -d data/a3m/` → keys are `Mp1g00070.1.a3m`
- `ffindex_build -d data/cs219/` → keys are `Mp1g00070.1.cs219`

**These don't match across indices** → hhsearch's lookup `cs219 hit → fetch a3m` fails silently. The wiki's MPI flow side-steps this by writing all 3 indices via `ffindex_apply_mpi` (which keys on the ffindex entry name, not file extension).

**Our fix** in `pack_ffindex`: stage symlinks renamed to bare ID (no extension) in `_stage/{a3m,hhm}/` before calling `ffindex_build`.

## 6. Intersection of available a3m + hhm at pack time

Some proteins permanently fail (giant proteins that hit timeout, edge-case A3Ms hhmake rejects). Without explicit handling, `pack_ffindex` would build mismatched indices → `integrity_check` fails.

**Fix**: `pack_ffindex` shell intersects `find data/a3m -size +0` ∩ `find data/hhm -size +0` and only stages proteins present in both. The DB cleanly excludes the failed long tail; `integrity_check` passes; failures are still visible in `results/failed_proteins.tsv`.

## 7. Two conda envs (orchestrator + runtime)

bioconda `hhsuite=3.3.0` is py3.7–3.9 only; `snakemake-executor-plugin-slurm>=0.11` needs py≥3.11. They cannot coexist. Solution: split into two envs, wire via snakemake's per-rule `conda:` directive + `--use-conda`. Adds a one-time per-rule env build to `.snakemake/conda/`, no per-job overhead after that.

## 8. Atomic per-protein writes (`.tmp → rename`)

A SIGKILL at SLURM walltime mid-`hhblits` would leave a truncated `.a3m`. On rerun, `[ -s .a3m ]` would say "exists, skip" → corrupt DB. The atomic pattern (`-oa3m {a3m}.tmp` then `mv` only after BOTH hhblits AND hhmake succeed) eliminates this class of bug.

## 9. SLURM `--signal=B:USR1@300` for graceful drain

Without it: SLURM SIGTERMs the bash script at walltime, killing the in-flight protein and forfeiting any unflushed log writes. With `--signal=B:USR1@300`, SLURM sends `SIGUSR1` to the **batch script** (not just the foreground process) 5 min before walltime. The bash trap sets `TIME_UP=1`; after the current protein finishes, the loop exits cleanly and snakemake records a recoverable batch failure. On rerun, the idempotent skip carries us forward.

## 10. `--jobs 40` (not higher), even though we have headroom

`MaxTRESPU=cpu=96000` and `LevelFS=7.83` (we're well under fair share) would let us go to `--jobs 200+`. We picked 40 because:
- `40 × 4 cpu = 160 CPUs` leaves room for other lab members
- avoids burning fair-share priority in a single weekend
- with `--max-jobs-per-second 1`, scheduler is never under burst

If you need to go faster and your `LevelFS > 5`, bump `jobs` in `profiles/slurm/config.yaml` to 80–100 — still safe.
