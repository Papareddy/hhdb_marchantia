#!/usr/bin/env bash
# Run hhblits + hhmake on every protein in a batch, with:
#   - per-protein timeout (PER_PROTEIN_TIMEOUT)
#   - atomic .tmp -> rename writes
#   - idempotent skip-if-output-exists
#   - graceful drain on SIGUSR1 (sent by SLURM 5 min before walltime)
#   - structured per-protein TSV log (the "forensic gold")
#
# Usage:  run_batch.sh <done_sentinel> <summary_tsv> <fasta1> <fasta2> ...
# Required env: UNIREF30_PREFIX, HHBLITS_ITERS, HHBLITS_EVALUE, HHBLITS_EXTRA,
#               PER_PROTEIN_TIMEOUT, HHMAKE_M, HHLIB
# Optional:     SLURM_CPUS_PER_TASK (auto-set by SLURM)

set -uo pipefail

DONE_FILE=$1
SUMMARY_TSV=$2
shift 2
FASTAS=("$@")

BATCH_ID=$(basename "$DONE_FILE" .done)
FAILED_FILE=data/batches/${BATCH_ID}.failed

mkdir -p data/a3m data/hhm data/batches \
         logs/batches logs/hhblits logs/hhmake \
         "$(dirname "$DONE_FILE")" "$(dirname "$SUMMARY_TSV")"

# (re)create per-batch log tsv with header
printf "protein_id\tlength_aa\tstatus\thhblits_sec\thhmake_sec\twall_sec\texit_code\treason\n" > "$SUMMARY_TSV"
: > "$FAILED_FILE"

# graceful drain on USR1 (SLURM sends this 5 min before walltime via --signal=B:USR1@300)
TIME_UP=
trap 'TIME_UP=1; echo "[$(date -Is)] SIGUSR1 received — finishing current protein then bailing" >&2' USR1

UNIREF="${UNIREF30_PREFIX:-data/reference/UniRef30_2023_02}"
N_ITERS="${HHBLITS_ITERS:-2}"
EVALUE="${HHBLITS_EVALUE:-1e-3}"
HHB_EXTRA="${HHBLITS_EXTRA:--cov 0 -qid 0 -maxfilt 100000 -diff inf -id 100}"
PER_PROTEIN_TIMEOUT="${PER_PROTEIN_TIMEOUT:-20m}"
HHMAKE_M="${HHMAKE_M:-a3m}"
THREADS="${SLURM_CPUS_PER_TASK:-4}"

echo "[$(date -Is)] batch=$BATCH_ID  n_proteins=${#FASTAS[@]}  uniref=$UNIREF  iters=$N_ITERS  cpu=$THREADS  timeout=$PER_PROTEIN_TIMEOUT" >&2

for fa in "${FASTAS[@]}"; do
  id=$(basename "$fa" .fa)
  a3m=data/a3m/${id}.a3m
  hhm=data/hhm/${id}.hhm
  hhb_log=logs/hhblits/${id}.log
  hhm_log=logs/hhmake/${id}.log

  start=$(date +%s)
  qlen=$(awk '!/^>/' "$fa" 2>/dev/null | tr -d '\n' | wc -c)

  # idempotent skip
  if [ -s "$a3m" ] && [ -s "$hhm" ]; then
    end=$(date +%s)
    printf "%s\t%d\tSKIPPED\t0\t0\t%d\t0\toutput_already_exists\n" \
      "$id" "$qlen" $((end - start)) >> "$SUMMARY_TSV"
    continue
  fi

  # ---- hhblits ----
  hhb_start=$(date +%s)
  timeout "$PER_PROTEIN_TIMEOUT" hhblits \
      -i "$fa" -d "$UNIREF" -oa3m "${a3m}.tmp" \
      -n "$N_ITERS" -e "$EVALUE" -cpu "$THREADS" \
      $HHB_EXTRA -v 1 > "$hhb_log" 2>&1
  hhb_exit=$?
  hhb_sec=$(($(date +%s) - hhb_start))

  if [ "$hhb_exit" -ne 0 ] || [ ! -s "${a3m}.tmp" ]; then
    end=$(date +%s)
    if [ "$hhb_exit" -eq 124 ]; then reason="hhblits_timeout_${PER_PROTEIN_TIMEOUT}"; else reason="hhblits_failed_exit_${hhb_exit}"; fi
    printf "%s\t%d\tFAILED\t%d\t0\t%d\t%d\t%s\n" \
      "$id" "$qlen" "$hhb_sec" $((end - start)) "$hhb_exit" "$reason" >> "$SUMMARY_TSV"
    printf "%s\t%s\n" "$id" "$reason" >> "$FAILED_FILE"
    rm -f "${a3m}.tmp"
    [ -n "$TIME_UP" ] && { echo "[$(date -Is)] walltime imminent — bailing after failed $id" >&2; exit 1; }
    continue
  fi

  # ---- hhmake ----
  hhm_start=$(date +%s)
  hhmake -i "${a3m}.tmp" -o "${hhm}.tmp" -M "$HHMAKE_M" -v 1 > "$hhm_log" 2>&1
  hhm_exit=$?
  hhm_sec=$(($(date +%s) - hhm_start))

  if [ "$hhm_exit" -ne 0 ] || [ ! -s "${hhm}.tmp" ]; then
    end=$(date +%s)
    reason="hhmake_failed_exit_${hhm_exit}"
    grep -q "Compress" "$hhm_log" 2>/dev/null && reason="hhmake_compress_error"
    printf "%s\t%d\tFAILED\t%d\t%d\t%d\t%d\t%s\n" \
      "$id" "$qlen" "$hhb_sec" "$hhm_sec" $((end - start)) "$hhm_exit" "$reason" >> "$SUMMARY_TSV"
    printf "%s\t%s\n" "$id" "$reason" >> "$FAILED_FILE"
    rm -f "${a3m}.tmp" "${hhm}.tmp"
    [ -n "$TIME_UP" ] && { echo "[$(date -Is)] walltime imminent — bailing after hhmake fail $id" >&2; exit 1; }
    continue
  fi

  # promote both atomically (only after BOTH succeed, so a half-batch leaves no zombies)
  mv "${a3m}.tmp" "$a3m"
  mv "${hhm}.tmp" "$hhm"
  end=$(date +%s)
  printf "%s\t%d\tOK\t%d\t%d\t%d\t0\tok\n" \
    "$id" "$qlen" "$hhb_sec" "$hhm_sec" $((end - start)) >> "$SUMMARY_TSV"

  [ -n "$TIME_UP" ] && { echo "[$(date -Is)] walltime imminent — bailing after $id (clean state)" >&2; exit 1; }
done

# All proteins in batch handled (ok / failed / skipped). Touch sentinel.
touch "$DONE_FILE"
n_ok=$(awk -F'\t' '$3=="OK"' "$SUMMARY_TSV" | wc -l)
n_fail=$(awk -F'\t' '$3=="FAILED"' "$SUMMARY_TSV" | wc -l)
n_skip=$(awk -F'\t' '$3=="SKIPPED"' "$SUMMARY_TSV" | wc -l)
echo "[$(date -Is)] batch=$BATCH_ID DONE  ok=$n_ok fail=$n_fail skip=$n_skip" >&2
