# Stage 2-4: per-protein MSA + HMM + cs219.
# Per-protein rules; group them so the SLURM executor batches them per job.

rule hhblits:
    input:
        fa = QDIR / "{id}.fa",
    output:
        a3m = A3M / "{id}.a3m",
    params:
        db     = config["uniref30_prefix"],
        iters  = HHB["iters"],
        evalue = HHB["evalue"],
        cpu    = HHB["cpu"],
        extra  = HHB["extra"],
    log:
        "logs/hhblits/{id}.log",
    threads: lambda wc: HHB["cpu"]
    resources:
        mem_mb  = lambda wc: config["slurm"]["hhblits_mem_mb"],
        runtime = lambda wc: config["slurm"]["hhblits_runtime_min"],
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        export HHLIB=$CONDA_PREFIX
        hhblits -i {input.fa} -d {params.db} -oa3m {output.a3m} \
                -n {params.iters} -e {params.evalue} -cpu {params.cpu} \
                {params.extra} -v 1 > {log} 2>&1
        """

rule hhmake:
    input:
        a3m = A3M / "{id}.a3m",
    output:
        hhm = HHM / "{id}.hhm",
    params:
        m = config["hhmake"]["match_assign"],
    log:
        "logs/hhmake/{id}.log",
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        export HHLIB=$CONDA_PREFIX
        hhmake -i {input.a3m} -o {output.hhm} -M {params.m} -v 1 > {log} 2>&1
        """

# NOTE: per-protein cstranslate rule REMOVED — cstranslate has no single-file
# mode; it always opens <prefix>.ffdata/.ffindex. We now run cstranslate ONCE
# at pack time over the full a3m ffindex (matches wiki recipe).
