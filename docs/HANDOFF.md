# Project handoff — Marchantia HH-suite database

**Use this if you're picking up this project from a fresh machine, or are a new collaborator (or Claude session) joining post-build.**

Last updated: 2026-05-15 (post-v1.1 build, DB live on SDS).

---

## TL;DR — what state is the project in?

**Production-complete.** The DB is built, validated, and queryable.

- ✅ **v1.1 build complete**: 18,007 / 18,007 proteins (100 % proteome coverage)
- ✅ **DB live on SDS**: `/mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1/db_v1/`
- ✅ **Validated**: 6 conserved RQC/ribosome-rescue factors hit Marchantia at Prob=100 (PELO/HBS1L/NEMF/LTN1/ABCE1/ZNF598). Reference output bundled in companion repo.
- ✅ **Companion repo** (`marchantia_hhdb_user`) production-ready: clone-and-run, auto-creates conda env, bundled examples.
- ⏳ **Pending (user-driven, not autonomous)**:
  - Send announcement email to Dagdas lab (draft in session history)
  - Upload `archives/marchantia_hhdb_v7.1_build-1.1.tar.gz` to Zenodo (manual)
  - Backfill Zenodo DOI into README.md, CITATION.cff (both repos), `marchantia_hhdb_user/Makefile`
  - UniRef30 cleanup decision (informational; **never delete autonomously**)

---

## Two repos

| Repo | Role | URL |
|---|---|---|
| `hhdb_marchantia` (this one) | Snakemake build pipeline | https://github.com/Papareddy/hhdb_marchantia |
| `marchantia_hhdb_user` | End-user query wrapper (clone + run) | https://github.com/Papareddy/marchantia_hhdb_user |

Active branches in `hhdb_marchantia`:
- `main` — the final v1.1 production config
- `feature/tier-aware-timeout` — earlier intermediate branch (merged in spirit; can be deleted)

---

## Where the DB lives

```
/mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1/
├── archives/          ← tarball backups of both v1 (97.55 %) and v1.1 (100 %) builds
└── db_v1/             ← canonical query target (was named db_v1.1, renamed after v1 was deleted)
    └── marchantia_v7.1_{a3m,hhm,cs219}.{ffdata,ffindex}
        a3m     213 GB / 18,007 entries
        hhm     1.1 GB / 18,007 entries
        cs219   7.4 MB / 18,007 entries
```

### Canonical env var (what users export)

```
export MARCHANTIA_HHDB=/mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1/db_v1/marchantia_v7.1
```

Note: the directory is named `db_v1/` (not `db_v1.1/`). When the new build superseded the original v1, the dir was renamed for cleanliness. The build provenance lives in the `archives/` tarballs.

---

## Helix workspace

The pipeline source + scratch outputs still live on helix for re-runs:

```
ssh helix
cd /gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia
```

Account: `bw25c013`, partition: `cpu-single`, conda module: `devel/miniforge/24.9.2`.
Workspace expires ~2026-06-10 — extend with `ws_extend HH_Suite_Marchantia 30` if needed.

---

## How to query (the 60-second user path)

From any bwHPC node with SDS mounted, including the helix login node:

```bash
git clone https://github.com/Papareddy/marchantia_hhdb_user.git
cd marchantia_hhdb_user
export MARCHANTIA_HHDB=/mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1/db_v1/marchantia_v7.1
./batch_query.sh examples/my_rqc_factors.fasta
```

First run takes ~3 min to auto-create the conda env (`mamba env create -f environment.yml` happens automatically inside `scripts/setup_env.sh`). Subsequent runs go straight to query.

---

## Permanent rules — never violate

- **Never delete `data/reference/`**. UniRef30 (~250 GB unpacked) took >40 min to download + extract; the user explicitly marked it sacrosanct. If disk pressure arises, surface to the user — never `rm` autonomously. Memory: `feedback_no_destructive_reference_data.md`.
- **Never retry ssh after auth failure**. bwHPC's fail2ban / rate-limit treats burst retries as a brute-force attack; the user was previously administratively suspended for this pattern. On first `ssh helix` failure ("Permission denied", "Too many authentication failures", "Connection refused"), **stop and tell the user**. Do NOT retry with different flags, alternate IPs, or `ssh-add` resets. Memory: `feedback_no_ssh_retry_spam.md`.
- **Production submissions require explicit "go"** from the user. Autonomous resume of a previously-approved chain (after a cluster outage, etc.) is OK as long as it's clearly continuing the same approved work.

---

## Non-obvious knowledge that bit us (and how to avoid)

Most of this is also in `docs/METHODOLOGY.md` and the `marchantia_hhdb_user` README — duplicated here as a quick reference for future-you.

- **hhmake -M first/50/30 all fail** on hhblits 3.3.0 output with `"Compress"` column-count errors. Only `-M a3m` works (trusts the A3M's own match-state encoding). Hardcoded in `config.yaml`.
- **cstranslate has NO single-file mode** — always operates on a ffindex. The pack stage runs it once over the full a3m ffindex; per-protein cstranslate is the wrong design.
- **ffindex_build keys on the literal filename including extension** — staged symlinks renamed to bare ID (no `.a3m`/`.hhm`) before `ffindex_build` so all 3 indices share keys.
- **snakemake's `group:` directive sums resources** — `group: msa` with 50 proteins/batch made snakemake ask 160 cpu / 312 G, instantly rejected by `cpu-single`. Removed groups; switched to a manual `batch_msa` wrapper rule.
- **profile's `set-resources` overrides the rule's `resources:` block** — always check the profile when bumping resources for a rule.
- **snakemake's `script:` directive treats `{...}` in COMMENTS as wildcards** — a comment like `# rename to {id}.fa` causes NameError. Use a python script via the `script:` directive (not a shell heredoc).
- **cstranslate `-c N` is OpenMP threads, and MORE threads = MORE memory, not less.** Empirical: peak ≈ 15 GB + 4 GB × N. For an 18 k-entry DB, safe combo is `-c 4` + ≥64 GB pack mem. `-c 8` + 48 GB OOMs at ~47 GB peak. The v1.1 pack succeeded with `-c 4` + 96 GB (used 98 GB peak — bump to 128 GB next time for safety margin).
- **Every fresh `mamba env create` or feature-branch checkout tends to silently re-introduce `cstranslate -c 4`** and reset pack mem to 32 GB. Grep `cstranslate config.yaml` and `mem_mb` in `profiles/slurm/config.yaml` after any config touch.
- **Login-node outages kill the snakemake driver AND any detached watchers** (`nohup setsid` doesn't survive login-node restart). Running SLURM jobs continue, but no new ones get submitted from the local queue. Recovery: `snakemake --unlock` → restart driver detached → re-arm watchers.
- **Forced kill of the snakemake driver invalidates rule metadata** (`.snakemake/incomplete/`). On resume, snakemake re-submits previously-completed rules. Because `run_batch.sh` is idempotent (skips proteins with existing `.a3m`/`.hhm`), the re-submission is wasted SLURM-submission time, not wasted CPU. Use `snakemake --touch` to skip the re-validation pass if needed.

---

## Failure modes + recovery cheatsheet

Mostly historical now — kept here in case a future re-run hits the same walls.

| Symptom | Likely cause | Fix |
|---|---|---|
| `cstranslate ... Killed` in `logs/pack/pack.*.log` | cgroup OOM despite low MaxRSS (mmap-heavy) | Bump `pack_ffindex` mem in `profiles/slurm/config.yaml`; we ended at 96 GB. Next safe step: 128 GB. **Decrease `-c N`, don't increase** (more threads = more RAM). |
| Pack walltime hit | cstranslate slower than estimated | Bump `runtime` in profile; current setting is 16 h (used 11.5 h in v1.1). |
| `hhmake ... Compress error` | hhblits A3M edge case | Use `-M a3m` (already default). |
| Driver dies with "Directory cannot be locked" | Stale `.snakemake/.lock` from a killed driver | `snakemake --unlock` then restart |
| `Error in rule batch_msa` after 836/836 done | Race: one batch's `.done` got removed by snakemake even though run_batch.sh completed | Manually touch the missing sentinel + restart (see "medium_0100 recovery" in earlier docs) |

### Swap-and-restart helper

```bash
bash scripts/swap_pack_patch_and_restart.sh
```

Kills any live driver, scancels pending pack jobs, wipes `data/db/*` (NOT `data/a3m/*` or `data/hhm/*`), pulls `pack.smk` + `profiles/slurm/config.yaml` from `origin/main`, unlocks, and restarts.

---

## Picking up on a different machine

1. Clone both repos:
   ```bash
   git clone https://github.com/Papareddy/hhdb_marchantia.git
   git clone https://github.com/Papareddy/marchantia_hhdb_user.git
   cd hhdb_marchantia
   ```
2. Read `docs/HANDOFF.md` (this file) and `docs/METHODOLOGY.md` first.
3. Verify SDS access (requires bwHPC keys):
   ```bash
   ssh helix 'ls -lh /mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1/db_v1/'
   ```
   Expected: 6 files (a3m/hhm/cs219 × ffdata/ffindex), totaling ~214 GB.
4. To re-run the build (if needed):
   ```bash
   ssh helix
   cd /gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia
   git pull
   conda activate hhsuite_marchantia
   snakemake --profile profiles/slurm --config mode=production
   ```

---

## Open questions for the user (post-v1.1)

1. **Send the Dagdas-lab announcement email** (draft is in the session that produced this handoff).
2. **Pick a Zenodo metadata bundle**: title, co-authors, exact CC-BY-4.0 vs CC0. Defaults in `docs/DOWNSTREAM_USAGE.md`.
3. **Zenodo upload**: publish v1.1 tarball (`archives/marchantia_hhdb_v7.1_build-1.1.tar.gz`); decide whether v1 also gets a record (recommendation: skip, v1.1 strictly supersedes it).
4. **After Zenodo DOI is assigned**: backfill the DOI into this repo's `README.md`, `CITATION.cff`, the companion repo's `README.md` and `Makefile`.
5. **UniRef30 cleanup**: roughly 250 GB on bwHPC scratch (`data/reference/`). User-only decision; surface, never act.
