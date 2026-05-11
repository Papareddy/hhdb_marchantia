# Querying the Marchantia HH-suite database

Once the build is complete, you have a 6-file ffindex DB at `data/db/`:
```
marchantia_v7.1_a3m.{ffdata,ffindex}
marchantia_v7.1_hhm.{ffdata,ffindex}
marchantia_v7.1_cs219.{ffdata,ffindex}
```

The packaged tarball (`marchantia_hhdb_v7.1.tar.gz`) is hosted on **Zenodo**:

> **DOI**: `10.5281/zenodo.XXXXXXX` *(filled in after upload — see "Zenodo upload" below)*
> Direct download URL: `https://zenodo.org/record/XXXXXXX/files/marchantia_hhdb_v7.1.tar.gz`

A self-contained companion repo `marchantia_hhdb_user` (post-build) wraps the
fetch + verify + query in a one-liner.

---

## Querying without the pipeline (fast path)

### One-shot search with hhsearch

```bash
# Conda env with hh-suite 3.3.0 (bioconda):
#   mamba create -n hhq -c bioconda hhsuite=3.3.0 && conda activate hhq
export HHLIB=$CONDA_PREFIX

hhsearch \
    -i your_factor.fa \
    -d /path/to/marchantia_v7.1 \
    -o your_factor.hhr \
    -cpu 4
```

`-d` takes the DB **prefix** without `_a3m.ffdata` etc. — if the files live
at `/scratch/db/marchantia_v7.1_a3m.ffindex`, pass `-d /scratch/db/marchantia_v7.1`.

### Iterative search with hhblits (more sensitive for remote homologs)

```bash
hhblits \
    -i your_factor.fa \
    -d /path/to/marchantia_v7.1 \
    -oa3m your_factor.a3m \
    -o your_factor.hhr \
    -n 3 -e 1e-3 -cpu 4
```

`-n 3` runs 3 iterations (slower, more sensitive). For finding factor
orthologs in this single-proteome DB, `-n 1` (i.e. `hhsearch`) is usually
enough.

### Reading the .hhr output

The first hit block is the most likely homolog. Key columns:
- **Prob** — probability of homology (0–100); >50 = strong, >90 = essentially certain
- **E-value** — expected hits by chance; <1e-3 is good
- **Cols** — number of aligned match columns
- **Query/Template HMM** — alignment span

```
 No Hit                             Prob E-value P-value  Score Cols Query HMM  Template HMM
  1 Mp1g00080.1                     99.9   3e-72   3e-77  423.7  385   1-410      4-410   (410)
```

### Batch search over many factors

```bash
for fa in factors/*.fa; do
  hhsearch -i $fa -d /path/to/marchantia_v7.1 -o results/$(basename $fa .fa).hhr -cpu 4
done
```
For >100 factors, wrap in a SLURM array job — each takes ~30 s on a 4-cpu
allocation against the 18 k-protein DB.

---

## Companion repo (post-build): `marchantia_hhdb_user`

Will contain:
```
marchantia_hhdb_user/
├── README.md            quick-start (3 commands)
├── Makefile             `make fetch` (download + md5) and `make verify`
├── query.sh             single-protein hhsearch wrapper
├── batch_query.sh       multi-protein wrapper (loops + parallel)
├── examples/            example .fa files (well-known Marchantia TFs)
└── docs/INTERPRETATION.md  how to read .hhr + which thresholds to trust
```

Won't ship the DB itself — `make fetch` pulls it from Zenodo.

---

## Zenodo upload (one-time, after production build completes)

Once `data/db/marchantia_v7.1_*.{ffdata,ffindex}` exist and pass
`integrity_check`:

1. Tar + md5 (the pipeline's stage 6 does this automatically into
   `results/marchantia_hhdb_v7.1.tar.gz` and `.md5`).
2. Create a new deposit at https://zenodo.org/deposit (sign in with ORCID).
3. Upload `marchantia_hhdb_v7.1.tar.gz` (Zenodo allows up to 50 GB per file
   — the tar will fit comfortably; estimated ~30–40 GB compressed).
4. Add metadata:
   - **Title**: `Marchantia polymorpha Tak-1 v7.1 — HH-suite v3 profile database`
   - **Authors**: Ranjith Papareddy (+ collaborators)
   - **Description**: short paragraph; reference this repo and the HH-suite + UniRef30 papers
   - **Keywords**: `Marchantia polymorpha`, `HH-suite`, `protein homology`, `HMM`, `bioinformatics`
   - **License**: CC-BY 4.0 (matches the bioinformatics-data convention; pipeline code is MIT separately)
   - **Related identifiers**: link to this GitHub repo (`is documented by` `https://github.com/Papareddy/hhdb_marchantia`) and the UniRef30 record
5. Reserve the DOI **before** publishing — paste it back into:
   - this file (replace `10.5281/zenodo.XXXXXXX`)
   - `CITATION.cff` (add as a `references` entry)
   - the future `marchantia_hhdb_user` repo's `Makefile` and README
6. Publish.

For new build versions later (e.g. when MpTak v8 drops), upload a new version
to the same Zenodo concept-DOI — that gives you a "latest" badge users can
follow without changing the URL.
