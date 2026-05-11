#!/usr/bin/env bash
# Minimal example: run hhsearch with one factor of interest against the
# Marchantia HH-suite database produced by this pipeline.
#
# Usage:  examples/query_one_factor.sh <query.fa> [output.hhr]
#
# Prereq: hh-suite 3.3.0 in PATH (e.g. `mamba install -c bioconda hhsuite=3.3.0`)
#         and HHLIB pointing at the conda env (`export HHLIB=$CONDA_PREFIX`).

set -euo pipefail

QUERY=${1:?usage: $0 <query.fa> [output.hhr]}
OUT=${2:-${QUERY%.*}.hhr}
DB=${MARCHANTIA_HHDB:-data/db/marchantia_v7.1}
THREADS=${THREADS:-4}

if [ -z "${HHLIB:-}" ] && [ -n "${CONDA_PREFIX:-}" ]; then
  export HHLIB=$CONDA_PREFIX
fi

[ -s "${DB}_a3m.ffdata" ] || {
  echo "ERROR: DB not found at $DB (looked for ${DB}_a3m.ffdata)" >&2
  echo "Set MARCHANTIA_HHDB=/path/to/marchantia_v7.1 (prefix, no extension)." >&2
  exit 1
}

echo "[$(date -Is)] hhsearch $QUERY against $DB ($THREADS cpu) -> $OUT"
hhsearch -i "$QUERY" -d "$DB" -o "$OUT" -cpu "$THREADS" -v 1
echo "[$(date -Is)] done. Top-10 hits:"
echo
sed -n '/^ No Hit/,/^No 1/p' "$OUT" | head -12
