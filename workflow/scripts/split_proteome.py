"""Split a primary-isoform proteome FASTA into per-protein {id}.fa files.

Mode 'smoke' caps at config['smoke_n']. Mode 'production' takes everything.
ID = first whitespace-delimited token after '>'.
"""
from pathlib import Path
import sys

src   = snakemake.input.fa
out   = Path(snakemake.output[0])
mode  = snakemake.params.mode
n     = int(snakemake.params.n)
log_p = Path(snakemake.log[0])

out.mkdir(parents=True, exist_ok=True)
log_p.parent.mkdir(parents=True, exist_ok=True)

count   = 0
rec_id  = None
buf     = []

def flush():
    global count, rec_id, buf
    if rec_id is None:
        return
    (out / f"{rec_id}.fa").write_text("\n".join(buf) + "\n")
    count += 1
    rec_id = None
    buf = []

with open(src) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if line.startswith(">"):
            flush()
            if mode == "smoke" and count >= n:
                break
            rec_id = line[1:].split()[0]
            buf = [line]
        else:
            buf.append(line)
    flush()

log_p.write_text(f"mode={mode} smoke_n={n} wrote={count} into {out}\n")
print(f"split_proteome: wrote {count} files into {out}", file=sys.stderr)
