#!/usr/bin/env bash
# No-tar chain: cp v1 to SDS, run v1.1 retry, cp v1.1 to SDS.
set -uo pipefail
WORKDIR=/gpfs/bwfor/work/ws/hd_wi353-HH_Suite_Marchantia/hhdb_marchantia
SDS=/mnt/sds-hd/sd25l008/resources/marchantia_hhdb_v7.1
LOG=$WORKDIR/logs/sds_only_chain.log
cd "$WORKDIR"
mkdir -p "$SDS/db_v1" "$SDS/db_v1.1"
echo "[$(date -Is)] SDS-only chain start" >> "$LOG"

# 1) wait for v1 integrity.ok
until [ -s results/validation/marchantia_v7.1.integrity.ok ]; do sleep 30; done
echo "[$(date -Is)] v1 integrity.ok seen" >> "$LOG"

# 2) cp v1 ffindex files to SDS/db_v1/
echo "[$(date -Is)] copying v1 DB to $SDS/db_v1/" >> "$LOG"
cp -v data/db/marchantia_v7.1_a3m.ffdata     "$SDS/db_v1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_a3m.ffindex    "$SDS/db_v1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_hhm.ffdata     "$SDS/db_v1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_hhm.ffindex    "$SDS/db_v1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_cs219.ffdata   "$SDS/db_v1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_cs219.ffindex  "$SDS/db_v1/" >> "$LOG" 2>&1
du -sh "$SDS/db_v1/" >> "$LOG"
echo "[$(date -Is)] v1 -> $SDS/db_v1/marchantia_v7.1   (queryable)" >> "$LOG"

# 3) apply feature/tier-aware-timeout to working tree
git remote add origin https://github.com/Papareddy/hhdb_marchantia.git 2>/dev/null || true
git fetch origin feature/tier-aware-timeout >> "$LOG" 2>&1
git checkout origin/feature/tier-aware-timeout -- \
    config.yaml workflow/rules/batch.smk workflow/scripts/retry_failed_batches.sh
chmod +x workflow/scripts/retry_failed_batches.sh
# === cstranslate -c 8 PRESERVED (feature branch has -c 4, we want -c 8 for pack speed) ===
sed -i "s|-f -x 0.3 -c 4 -I a3m|-f -x 0.3 -c 8 -I a3m|" config.yaml
echo "[$(date -Is)] patched cstranslate flags back to -c 8" >> "$LOG"
echo "[$(date -Is)] feature/tier-aware-timeout applied" >> "$LOG"

# 4) fire v1.1 retry
module load devel/miniforge/24.9.2
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate hhsuite_marchantia
bash workflow/scripts/retry_failed_batches.sh >> "$LOG" 2>&1
RETRY_PID=$(cat logs/retry_run.pid)
echo "[$(date -Is)] retry driver PID=$RETRY_PID" >> "$LOG"

# 5) wait for retry driver to exit
until ! ps -p "$RETRY_PID" > /dev/null 2>&1; do sleep 120; done
echo "[$(date -Is)] retry driver exited" >> "$LOG"

# 6) wait for new integrity.ok (the retry rebuilds data/db + writes a fresh integrity.ok)
# Note: integrity.ok may already exist from v1; wait until it's been modified after retry.
START_TS=$(date +%s)
until [ "$(stat -c %Y results/validation/marchantia_v7.1.integrity.ok 2>/dev/null || echo 0)" -gt "$START_TS" ]; do sleep 30; done
echo "[$(date -Is)] v1.1 integrity.ok seen" >> "$LOG"

# 7) cp v1.1 ffindex files to SDS/db_v1.1/
echo "[$(date -Is)] copying v1.1 DB to $SDS/db_v1.1/" >> "$LOG"
cp -v data/db/marchantia_v7.1_a3m.ffdata     "$SDS/db_v1.1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_a3m.ffindex    "$SDS/db_v1.1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_hhm.ffdata     "$SDS/db_v1.1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_hhm.ffindex    "$SDS/db_v1.1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_cs219.ffdata   "$SDS/db_v1.1/" >> "$LOG" 2>&1
cp -v data/db/marchantia_v7.1_cs219.ffindex  "$SDS/db_v1.1/" >> "$LOG" 2>&1
du -sh "$SDS/db_v1.1/" >> "$LOG"
echo "[$(date -Is)] FULL CHAIN COMPLETE  -> $SDS/db_v1.1/marchantia_v7.1" >> "$LOG"
