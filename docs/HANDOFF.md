# Project handoff — Marchantia HH-suite database

**Use this if you're picking up this project from a fresh machine, or are a new collaborator (or Claude session) joining mid-flight.**

Last updated: 2026-05-12 ~19:50 helix time, during the v1 production pack-stage debugging.

---

## TL;DR — what state is the project in?

- ✅ **Smoke test** passed (10 proteins, full pipeline, hhsearch on AtATG5 verified). DB queryable.
- 🔄 **v1 production build** is mid-way through `pack_ffindex` (the cstranslate step). 17,567/18,007 proteins have a3m+hhm; 442 permanently failed at v1 settings (20 min timeout). Pack has failed 3× due to cstranslate being killed (cgroup OOM at 16 GB). Now running on attempt 5 with **32 GB / 8 cpus / 16 h walltime**.
- ⏳ **v1.1 retry** with longer timeouts (30/60/90/180 min) + more memory per tier is queued behind v1: a detached watcher on helix will fire it automatically once `results/marchantia_hhdb_v7.1_build-1.tar.gz.md5` appears.
- ⏳ **Zenodo upload** is a manual user step after both tarballs exist.

---

## Two repos

| Repo | Role | URL |
|---|---|---|
| `hhdb_marchantia` (this one) | Snakemake build pipeline | https://github.com/Papareddy/hhdb_marchantia |
| `marchantia_hhdb_user` | End-user companion (clone + `make fetch` from Zenodo) | https://github.com/Papareddy/marchantia_hhdb_user |

Active branches in `hhdb_marchantia`:
- `main` — what's currently deployed to helix for the v1 build
- `feature/tier-aware-timeout` — patched per-tier timeouts + memory bumps for v1.1 retry (NOT merged; pulled file-by-file via the retry workflow)

---

## Helix workspace

```
ssh helix
cd /gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia
```

Account: `bw25c013`, partition: `cpu-single`, conda module: `devel/miniforge/24.9.2`.
QOS `normal`: `MaxSubmitPU=1500`, `MaxTRESPU=cpu=96000`. Cluster: `MaxJobCount=30000`, `MaxArraySize=1001`.
Workspace expires 2026-06-10 (extend with `ws_extend HH_Suite_Marchantia 30` if needed).

---

## Currently-running processes on helix (as of last handoff write)

Names/PIDs change; always re-check with `ps -p $(cat logs/production_run.pid)` and `pgrep -af "v1\.1 chain\|v1 stage6 watcher"`.

```
DRIVER:       snakemake driver         PID 3302626  (the production orchestrator)
SLURM job:    pack_ffindex (attempt 5) 12982471 PD  (32 G, 8 cpu, 16 h walltime)
WATCHER #1:   v1 Stage 6               PID 2629270  detached on helix
              → waits for results/validation/marchantia_v7.1.integrity.ok
              → then tars data/db/* into results/marchantia_hhdb_v7.1_build-1.tar.gz + .md5
WATCHER #2:   v1.1 chain               PID 2345993  detached on helix
              → waits for results/marchantia_hhdb_v7.1_build-1.tar.gz.md5
              → then: git fetch origin feature/tier-aware-timeout, checkout config.yaml +
                workflow/rules/batch.smk + workflow/scripts/retry_failed_batches.sh
              → bash workflow/scripts/retry_failed_batches.sh
              → wait for retry driver to finish
              → tar v1.1 into results/marchantia_hhdb_v7.1_build-1.1.tar.gz + .md5
WATCHER #3:   AtATG5 query (local ssh) bl22clgp9 (local bg task) + helix-side bash
              → waits for all 6 ffindex files non-empty + integrity.ok
              → runs hhsearch examples/AtATG5.fa
              → writes examples/AtATG5.hhr
```

Local watchers (on the Mac): `b7jcg2nbh` already fired (prematurely, before integrity gate added) — its bogus zero-byte `.md5` was deleted; cleaned up. `bjx1ccqpz` (old v1.1 chain) was superseded by the detached helix-side PID 2345993 — the duplicate at helix PID 2319067 was killed.

---

## Quick status commands

```bash
# Snapshot of where we are
cd /gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia
ls -lh data/db/                                            # 6 ffindex files? Sizes?
ls -lh results/                                            # tarballs?
cat results/validation/marchantia_v7.1.integrity.ok 2>/dev/null
squeue -u $USER -o "%.10i %.20j %.2t %.10m %.5C %.10L"     # SLURM state
ps -p $(cat logs/production_run.pid 2>/dev/null) -o pid,etime,stat  # driver alive?
cat logs/v1_stage6.log logs/v11_chain.log 2>/dev/null      # watchers' breadcrumbs
tail -20 logs/production_run.log                           # driver progress
ls -lt logs/pack/pack.20*.log 2>/dev/null | head           # per-attempt pack logs (timestamped)
```

To count protein progress inside the running cstranslate:
```bash
LATEST=$(ls -t logs/pack/pack.20*.log | head -1)
grep -c "^Processing entry:" "$LATEST"     # vs 17,567 total
wc -l data/db/marchantia_v7.1_cs219.ffindex
```

---

## What's expected to happen next (without any intervention)

```
T0  now            pack 12982471 = PD, waits for SLURM scheduling
T1  +0-15 min      pack starts running on a cpu-single node (32G/8cpu)
T2  +5 min running ffindex_build a3m (writes 184 GB a3m.ffdata)
T3  +6 min         ffindex_build hhm  (writes 970 MB hhm.ffdata)
T4  +6 min - +6 h  cstranslate over a3m ffindex → cs219 (8 cpu, ~60 entries/min target)
T5  +6 h           sort cs219 desc + reorder all 3 ffindexes
T6  +6 h 10 min    pack done; integrity_check submitted (separate SLURM job, ~1 min)
T7  +6 h 11 min    integrity.ok written; v1 Stage 6 watcher fires
T8  +6 h 30 min    v1 tarball + .md5 written; v1.1 chain detects
T9  +6 h 31 min    v1.1 chain pulls feature branch, runs retry_failed_batches.sh
T10 +6-12 h        retry runs (smaller batches, longer per-protein timeouts)
T11 +12-18 h       retry pack + integrity + tar
T12                v1.1 tarball + .md5 written; you upload both to Zenodo
```

---

## Failure modes + recovery (cheatsheet)

| Symptom | Most likely cause | Fix |
|---|---|---|
| `cstranslate ... Killed` in `logs/pack/pack.20*.log` | cgroup OOM despite low MaxRSS (mmap-heavy program) | Bump `pack_ffindex` mem in `profiles/slurm/config.yaml`. We're at 32 G; next step is 64 G. |
| Pack walltime hit | cstranslate slower than estimated | Bump `runtime` in profile; or bump `cpus_per_task` + matching `-c N` in `config.yaml`'s `cstranslate.flags`. |
| `hhmake ... Compress error` | hhblits A3M edge case | Use `-M a3m` (already default in `config.yaml`). |
| Driver dies with `Error in rule batch_msa` after 836/836 done | Race: one batch's `.done` got removed when snakemake marked it failed even though run_batch.sh completed | Manually touch the missing sentinel + restart (see "medium_0100 recovery" below). |
| `data/db/*` got deleted by snakemake on rule failure | Snakemake removes outputs on rule failure | Per-protein `data/a3m/*.a3m` and `data/hhm/*.hhm` are preserved (different rule); pack just rebuilds the 6 ffindex files. |

### medium_0100-style recovery (a batch's .done missing despite the batch script completing)

```bash
# pick the batch_id from the snakemake error
BID=medium_0100
# reconstruct minimal summary + failed list + sentinel
cat > logs/batches/${BID}.summary.tsv <<EOF
protein_id	length_aa	status	hhblits_sec	hhmake_sec	wall_sec	exit_code	reason
EOF
# add rows for the 2 known fails:
echo -e "Mp4g18280.1\t1132\tFAILED\t1200\t0\t1200\t137\thhblits_oom_killed" >> logs/batches/${BID}.summary.tsv
echo -e "Mp4g18390.1\t1057\tFAILED\t1200\t0\t1200\t137\thhblits_oom_killed" >> logs/batches/${BID}.summary.tsv
printf "Mp4g18280.1\thhblits_oom_killed\nMp4g18390.1\thhblits_oom_killed\n" > data/batches/${BID}.failed
touch data/batches/${BID}.done
# then re-unlock + restart the driver
snakemake --unlock
nohup snakemake --profile profiles/slurm --config mode=production \
    > logs/production_run.log 2>&1 &
echo $! > logs/production_run.pid
```

### Swap-and-restart (pack failed mysteriously again)

A helper exists:
```bash
bash scripts/swap_pack_patch_and_restart.sh
```
It kills any live driver, scancels pending pack jobs, wipes `data/db/*` (NOT `data/a3m/*` or `data/hhm/*`), pulls `pack.smk` + `profiles/slurm/config.yaml` from `origin/main`, unlocks, and restarts.

---

## Picking up on a different machine

1. **Clone both repos**:
   ```bash
   git clone https://github.com/Papareddy/hhdb_marchantia.git
   git clone https://github.com/Papareddy/marchantia_hhdb_user.git
   cd hhdb_marchantia
   ```
2. **Tell Claude (or whoever) to read this file first**:
   ```
   Read docs/HANDOFF.md and then ssh helix to check current state.
   ```
3. **Verify ssh access to helix works** (you'll need your bwHPC keys):
   ```bash
   ssh helix 'cd /gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia && ls -lh data/db/ results/'
   ```
4. **Pick the appropriate next action** based on what `ls -lh results/` shows:
   - Empty → pack is still running or failed; check `squeue -u $USER` and `logs/production_run.log`
   - `marchantia_hhdb_v7.1_build-1.tar.gz` only → v1 done, v1.1 retry in flight; check `logs/v11_chain.log`
   - Both tarballs → upload to Zenodo (see `docs/DOWNSTREAM_USAGE.md` § "Zenodo upload")

---

## Permanent rules (never violate)

- **Never delete `data/reference/`**. UniRef30 took 19 min to download + 22 min to extract; the user (Ranjith) explicitly said it is sacrosanct. If disk pressure arises, surface to the user — never `rm` UniRef30 programmatically.
- Production submissions are **gated on user "go"** in this project. Cron jobs / detached watchers running auto-pipelines are OK — destructive or compute-heavy actions still need explicit greenlight.

---

## Open questions for the user (post-v1.1)

1. Pick a Zenodo metadata bundle: title, co-authors, exact CC-BY-4.0 vs CC0, etc. (Defaults in `docs/DOWNSTREAM_USAGE.md`.)
2. Decide whether to publish v1 + v1.1 as two separate Zenodo records or v1.1 as a "new version" under the same concept-DOI (recommendation: latter).
3. After Zenodo DOI is assigned, run a small script to backfill the DOI into: this repo's `README.md`, `CITATION.cff`, the companion repo's `README.md` and `Makefile`.
