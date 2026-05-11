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
    group: "msa"
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
    group: "msa"
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        export HHLIB=$CONDA_PREFIX
        hhmake -i {input.a3m} -o {output.hhm} -M {params.m} -v 1 > {log} 2>&1
        """

rule cstranslate:
    # NB: do not change the flag set; wiki warns silent badness if any are dropped.
    input:
        a3m = A3M / "{id}.a3m",
    output:
        cs = CS219 / "{id}.cs219",
    params:
        flags = config["cstranslate"]["flags"],
    log:
        "logs/cstranslate/{id}.log",
    group: "msa"
    conda: "../envs/hhsuite.yml"
    shell:
        r"""
        export HHLIB=$CONDA_PREFIX
        cstranslate {params.flags} -i {input.a3m} -o {output.cs} > {log} 2>&1
        """
