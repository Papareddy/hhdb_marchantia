#!/usr/bin/env bash
# Run this on HELIX if pack attempt 2 also fails.
# Pulls the patched pack.smk + bumped resources from origin/main and
# restarts the driver without redoing any per-protein work.
#
# Usage:  bash scripts/swap_pack_patch_and_restart.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# 1) make sure no driver is alive (idempotent kill)
if [ -s logs/production_run.pid ]; then
  pid=$(cat logs/production_run.pid)
  if ps -p "$pid" > /dev/null 2>&1; then
    echo "[swap] killing existing driver PID=$pid"
    kill "$pid" 2>/dev/null || true
    sleep 5
    kill -9 "$pid" 2>/dev/null || true
  fi
fi

# 2) cancel any still-pending/running pack SLURM jobs
for jid in $(squeue -u "$USER" -h -o "%i %j" | awk '/pack_ffindex/ {print $1}'); do
  echo "[swap] scancel $jid"
  scancel "$jid" || true
done

# 3) clear pack outputs so snakemake re-runs pack (NOT the a3m/hhm — those are valuable)
echo "[swap] removing data/db/* + results/validation/* (pack only)"
rm -rf data/db/*
rm -f results/validation/marchantia_v7.1.integrity.ok
rm -f results/validation/marchantia_v7.1.summary.tsv

# 4) fetch patched pack.smk + profile from origin/main
echo "[swap] fetching patched pack.smk + profile from origin/main"
git remote add origin https://github.com/Papareddy/hhdb_marchantia.git 2>/dev/null || true
git fetch origin main
git checkout origin/main -- workflow/rules/pack.smk profiles/slurm/config.yaml

# 5) restart driver
module load devel/miniforge/24.9.2
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate hhsuite_marchantia
echo "[swap] snakemake --unlock"
snakemake --unlock || true
echo "[swap] restarting driver in background"
nohup snakemake --profile profiles/slurm --config mode=production \
    > logs/production_run.log 2>&1 &
echo $! > logs/production_run.pid
sleep 8
echo "[swap] NEW driver PID=$(cat logs/production_run.pid)"
tail -15 logs/production_run.log
