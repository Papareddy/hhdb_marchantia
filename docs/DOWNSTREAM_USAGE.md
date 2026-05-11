# Querying the Marchantia HH-suite database

Once the build is complete, you have a 6-file ffindex DB at `data/db/`:
```
marchantia_v7.1_a3m.{ffdata,ffindex}
marchantia_v7.1_hhm.{ffdata,ffindex}
marchantia_v7.1_cs219.{ffdata,ffindex}
```

Total compressed (`tar.gz`) size: ~XX GB (filled in after build).

## One-shot search with hhsearch

```bash
# In a conda env with hh-suite 3.3.0 (bioconda: `mamba install -c bioconda hhsuite=3.3.0`)
export HHLIB=$CONDA_PREFIX

hhsearch \
    -i your_factor.fa \
    -d /path/to/marchantia_v7.1 \
    -o your_factor.hhr \
    -cpu 4
```

`-d` takes the DB **prefix** without `_a3m.ffdata` etc. So if the files live at
`/scratch/db/marchantia_v7.1_a3m.ffindex`, pass `-d /scratch/db/marchantia_v7.1`.

## Iterative search with hhblits (deeper, finds remote homologs)

```bash
hhblits \
    -i your_factor.fa \
    -d /path/to/marchantia_v7.1 \
    -oa3m your_factor.a3m \
    -o your_factor.hhr \
    -n 3 \
    -e 1e-3 \
    -cpu 4
```

`-n 3` runs 3 iterations (slower, more sensitive). For factor-of-interest
homology hunts in a single proteome DB, `-n 1` (basically `hhsearch`) is
usually enough.

## Reading the .hhr output

The first hit block is the most likely homolog. Key columns:
- **Prob** — probability of homology (0–100); >50 = strong, >90 = essentially certain
- **E-value** — expected hits by chance; <1e-3 is good
- **Score** — raw HH alignment score
- **Cols** — number of aligned match columns
- **Query HMM / Template HMM** — alignment span

Example:
```
 No Hit                             Prob E-value P-value  Score Cols Query HMM  Template HMM
  1 Mp1g00080.1                     99.9   3e-72   3e-77  423.7  385   1-410      4-410   (410)
```

## Batch search over many factors

```bash
for fa in factors/*.fa; do
  out=results/$(basename $fa .fa).hhr
  hhsearch -i $fa -d /path/to/marchantia_v7.1 -o $out -cpu 4
done
```

For large factor lists (>100), wrap in a SLURM array job — each takes ~30 s on
a 4-cpu allocation against an 18 k-protein DB.

## Companion repository

A self-contained companion repo `marchantia_hhdb_user/` will be created after
this build completes. It bundles:
- A download link / DOI for the DB tarball
- A `Makefile` to fetch + extract + verify
- A tiny `query.sh` wrapper for the common hhsearch invocation
- Example queries (a few well-known Marchantia TFs)

Watch for the `marchantia_hhdb_user/` link in the README of this repo.
