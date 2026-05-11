# Custom HH-suite v3 database build for Marchantia polymorpha Tak-1 v7.1
# Wiki: https://github.com/soedinglab/hh-suite/wiki#building-customized-databases

from pathlib import Path

configfile: "config.yaml"

DB    = config["db_name"]
MODE  = config["mode"]
HHB   = config["hhblits_prod"] if MODE == "production" else config["hhblits_smoke"]
QDIR  = Path("data/queries")
A3M   = Path("data/a3m")
HHM   = Path("data/hhm")
CS219 = Path("data/cs219")
DBOUT = Path("data/db")

include: "workflow/rules/prep.smk"
include: "workflow/rules/msa.smk"
include: "workflow/rules/pack.smk"

# Top-level target: the six ffindex files (ordered) + integrity check stamp
rule all:
    input:
        DBOUT / f"{DB}_a3m.ffdata",
        DBOUT / f"{DB}_a3m.ffindex",
        DBOUT / f"{DB}_hhm.ffdata",
        DBOUT / f"{DB}_hhm.ffindex",
        DBOUT / f"{DB}_cs219.ffdata",
        DBOUT / f"{DB}_cs219.ffindex",
        f"results/validation/{DB}.integrity.ok",
        f"results/validation/{DB}.summary.tsv",
