"""Build length-tiered batches for the production HH-suite DB build.

Reads the primary-isoform FASTA, computes per-protein length, partitions into
length tiers, then chunks within each tier. Writes a single JSON file:

  {"lengths": {protein_id: length_aa, ...},
   "batches": {batch_id: [protein_id, ...], ...}}

Used by the Snakefile at parse time to enumerate `batch_msa` wildcards.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path


def parse_fasta_lengths(fa: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    cur_id: str | None = None
    cur_len = 0
    with fa.open() as f:
        for ln in f:
            ln = ln.rstrip()
            if ln.startswith(">"):
                if cur_id is not None:
                    out[cur_id] = cur_len
                cur_id = ln[1:].split()[0]
                cur_len = 0
            else:
                cur_len += len(ln)
        if cur_id is not None:
            out[cur_id] = cur_len
    return out


def build_batches(lens: dict[str, int], tiers: list[dict]) -> dict[str, list[str]]:
    """tiers entries: {name, max_len, chunk_size}.

    Each tier captures proteins with length < max_len (and >= prior tier's max_len).
    The LAST tier's max_len should be effectively infinite (e.g. 10**9) to catch
    the long tail.
    """
    batches: dict[str, list[str]] = {}
    assigned: set[str] = set()
    prev_max = 0
    for tier in tiers:
        name = tier["name"]
        mx = int(tier["max_len"])
        K = int(tier["chunk_size"])
        ids = sorted(i for i, L in lens.items()
                     if i not in assigned and prev_max <= L < mx)
        assigned.update(ids)
        for i in range(0, len(ids), K):
            batches[f"{name}_{(i // K) + 1:04d}"] = ids[i:i + K]
        prev_max = mx
    leftover = sorted(i for i in lens if i not in assigned)
    if leftover:
        # Should be empty if the last tier has a huge max_len; handle just in case.
        K = int(tiers[-1]["chunk_size"])
        for i in range(0, len(leftover), K):
            batches[f"{tiers[-1]['name']}_overflow_{(i // K) + 1:04d}"] = leftover[i:i + K]
    return batches


def main() -> None:
    fa = Path(sys.argv[1])
    tiers = json.loads(sys.argv[2])
    out_path = Path(sys.argv[3])
    lens = parse_fasta_lengths(fa)
    batches = build_batches(lens, tiers)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"lengths": lens, "batches": batches}, indent=2))
    n_by_tier: dict[str, int] = {}
    for bid, ids in batches.items():
        tier = bid.split("_")[0]
        n_by_tier[tier] = n_by_tier.get(tier, 0) + len(ids)
    print(f"wrote {len(batches)} batches over {len(lens)} proteins to {out_path}",
          file=sys.stderr)
    for t, n in n_by_tier.items():
        print(f"  tier {t}: {n} proteins", file=sys.stderr)


if __name__ == "__main__":
    main()
