# Troubleshooting

The non-obvious failure modes encountered during development. Most of these
are baked into the pipeline now, listed here so the failure-recovery doesn't
look like magic.

## hhmake: `sequences ... do not all have the same number of columns`

```
ERROR: Error in hhalignment.cpp:1244: Compress:
       sequences in {a3m} do not all have the same number of columns,
       e.g. first sequence and sequence UniRef100_X.
```

**Affects**: ~99% of A3Ms with `-M first`, `-M 50`, `-M 30`. Persists after
`hhfilter`, `reformat.pl a3m a3m`.

**Fix**: use `hhmake -M a3m` (trust the A3M's own match-state encoding). This
is the default in our `config.yaml` (`hhmake.match_assign: "a3m"`).

## cstranslate: `could not open file '{id}.a3m.ffdata'`

cstranslate has **no single-file mode**. It always tries to open
`<input>.ffdata`/`<input>.ffindex`. The `-I a3m` flag in the wiki recipe
declares the **ffindex entry format**, not the input mode.

**Fix**: cstranslate runs at pack stage over the A3M *ffindex*, not per
protein. See `workflow/rules/pack.smk`.

## SLURM: `cpus_per_task=160 mem=312G FAILED 0:0 00:00:00`

snakemake's `group:` directive **sums resource requests** across grouped
rules. With `group: "msa"` on hhblits + hhmake + cstranslate and 50 proteins
per group, the submission ask becomes 160 cpu / 312 GB → instantly rejected by
`cpu-single`.

**Fix**: do not use `group:` for these rules. Each rule submits its own SLURM
job; aggregate via `batch_msa` wrapper instead (already done in `batch.smk`).

## snakemake: `NameError: The name 'id' is unknown`

```
RuleException in rule split_proteome:
NameError: The name 'id' is unknown in this context.
```

snakemake formats the entire `shell:` block (including comments!) as a Python
f-string. A literal `{id}.fa` in a comment will be parsed as a wildcard ref.

**Fix**: either escape (`{{id}}.fa`) or — much cleaner — use a `script:`
directive with a Python helper file (no shell-escaping pitfalls). The
splitter is now `workflow/scripts/split_proteome.py`.

## Conda: `hh-suite=3.3.0 not available`

bioconda package name is **`hhsuite`** (no hyphen). The version pin is
`hhsuite=3.3.0`.

## Conda: `python 3.9 conflicts with snakemake-executor-plugin-slurm`

`hhsuite=3.3.0` only ships py3.7–3.9 builds; `snakemake-executor-plugin-slurm`
needs py≥3.11. They can't coexist in one env.

**Fix**: orchestrator env (snakemake, py3.11) is separate from runtime env
(hhsuite, py3.9). Per-rule wiring via `conda:` directive +
`snakemake --use-conda`.

## helix login node: `slurm_load_node: Access/permission denied`

`sinfo` is access-denied on the login node. This is benign — `squeue`,
`sbatch`, `sacct`, and the slurm executor all work normally.

**Workaround for partition discovery**: read partition names off your existing
`squeue` output, or `sinfo -p cpu-single -h -o "%P"` (specifying a partition).

## A batch SLURM job hits walltime mid-protein

Without mitigation: in-flight protein gets SIGKILL'd, leaves a truncated
`.a3m`. Next snakemake run does `[ -s .a3m ]` → "exists, skip" → DB has
corrupt entry.

**Mitigation in place**:
1. `--signal=B:USR1@300` in slurm extra → SLURM sends SIGUSR1 to the bash script 5 min before walltime
2. bash trap sets `TIME_UP=1`; loop exits cleanly **after** current protein
3. atomic `.tmp → rename` only after BOTH hhblits and hhmake succeed
4. on rerun, idempotent skip checks BOTH outputs exist with size > 0

Net: a walltime kill costs at most one protein's wallclock.

## Some proteins permanently fail — does the DB break?

No. `pack_ffindex` intersects `data/a3m/*.a3m` ∩ `data/hhm/*.hhm` and only
includes proteins where both exist. `integrity_check` asserts equal counts
across the 3 indices; the failed long tail is excluded entirely.

The failures are recorded in:
- `data/batches/{batch_id}.failed` — per-batch list with reason
- `results/failed_proteins.tsv` — aggregated post-run

## I want to re-run only failed batches

Just rerun snakemake. It auto-detects missing batch sentinels and re-submits.
Inside re-tried batches, the per-protein idempotent skip means already-done
proteins are instant no-ops.

```bash
snakemake --profile profiles/slurm --config mode=production
```

## I changed the hhblits flags, now snakemake re-runs everything

snakemake's provenance tracking detects parameter changes. To opt out (only
rerun based on file mtimes):

```bash
snakemake --profile profiles/slurm --config mode=production --rerun-triggers mtime
```

Or wipe metadata for a specific output:
```bash
snakemake --cleanup-metadata data/batches/small_0001.done
```
