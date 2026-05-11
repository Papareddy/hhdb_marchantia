# References

## Tools

| Tool | Citation |
|---|---|
| HH-suite3 (hhblits, hhmake, hhsearch, cstranslate) | Steinegger M, Meier M, Mirdita M, Vöhringer H, Haunsberger SJ, Söding J. (2019) "HH-suite3 for fast remote homology detection and deep protein annotation." *BMC Bioinformatics* **20**(1):473. doi:10.1186/s12859-019-3019-7 |
| UniRef30 / Uniclust30 | Mirdita M, von den Driesch L, Galiez C, Martin MJ, Söding J, Steinegger M. (2017) "Uniclust databases of clustered and deeply annotated protein sequences and alignments." *Nucleic Acids Research* **45**(D1):D170-D176. doi:10.1093/nar/gkw1081 |
| Snakemake | Mölder F, Jablonski KP, Letcher B, *et al.* (2021) "Sustainable data analysis with Snakemake." *F1000Research* **10**:33. doi:10.12688/f1000research.29032.2 |
| Conda / mamba | Anaconda Inc. (2024) https://docs.conda.io ; Mamba: https://mamba.readthedocs.io |

## Proteome / genome

- *Marchantia polymorpha* Tak-1 v7.1 — primary isoform proteome from
  https://marchantia.info — TODO: fill in genome paper citation once published.

## Pipeline-specific

- HH-suite wiki, "Building customized databases":
  https://github.com/soedinglab/hh-suite/wiki#building-customized-databases
  (the canonical recipe this pipeline adapts to a snakemake fan-out)
- HH-suite repo: https://github.com/soedinglab/hh-suite
- HH-suite user guide PDF: https://github.com/soedinglab/hh-suite/blob/master/data/hhsuite-userguide.pdf

## How to cite this pipeline

If you use the *Marchantia polymorpha* HH-suite database produced by this
pipeline in your research, please cite:

- This repository: `github.com/<user>/hhdb_marchantia` (TODO: fill once pushed to GitHub)
- The HH-suite3 paper (Steinegger 2019, above) — for the homology-search method
- The UniRef30 paper (Mirdita 2017, above) — for the seed MSAs
- The Marchantia Tak-1 v7.1 genome paper — for the proteome
