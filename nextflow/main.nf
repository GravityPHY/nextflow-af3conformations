#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ── Parameters ────────────────────────────────────────────────────────────────
params.fasta     = null            // required: path to input FASTA
params.smiles    = null            // optional: SMILES string for ligand
params.outdir    = "results"
params.model_dir = "af3_info/af3_weights"
params.colabfold_env = "/projectnb2/docking/imhaoyu/localcolabfold/colabfold-conda"

// ── Process: generate MSA and prepare AF3 JSON(s) ────────────────────────────
process GENERATE_MSA {
    tag "${fasta.baseName}"
    publishDir "${params.outdir}/${fasta.baseName}/msa", mode: 'copy', pattern: "*.json"

    input:
    path fasta
    val  smiles

    output:
    path "AF3nolig.json",   emit: nolig_json
    path "AF3withlig.json", emit: withlig_json, optional: true

    script:
    def smiles_arg = (smiles && smiles != "null") ? "--smiles '${smiles}'" : ""
    """
    module load miniconda
    module load gcc/13.2.0
    source activate ${params.colabfold_env}

    set -euo pipefail

    colabfold_batch ${fasta} ./ --msa-only

    python3 ${launchDir}/scripts/af3/prepare_af3_json.py . \
        --name ${fasta.baseName} \
        ${smiles_arg}
    """
}

// ── Process: run AF3 prediction ───────────────────────────────────────────────
process RUN_AF3 {
    tag "${json.baseName}"
    publishDir "${params.outdir}/${json.baseName}", mode: 'copy'

    input:
    path json

    output:
    path "${json.baseName}", emit: af3_output

    script:
    """
    set -euo pipefail

    module load alphafold3/3.0.0

    # Copy the staged input (may be a symlink) into a real file, then pass
    # absolute paths to run_alphafold.sh so they resolve correctly inside the
    # Singularity container regardless of its working directory.
    cp -L ${json} input.json
    WORKDIR=\$PWD

    run_alphafold.sh \
        --json_path=\$WORKDIR/input.json \
        --model_dir=${params.model_dir} \
        --norun_data_pipeline \
        --output_dir=\$WORKDIR/${json.baseName}
    """
}

// ── Workflow ──────────────────────────────────────────────────────────────────
workflow {
    if (!params.fasta) {
        error "ERROR: --fasta is required. Usage: nextflow run main.nf --fasta <path> [--smiles <string>]"
    }

    fasta_ch  = Channel.fromPath(params.fasta, checkIfExists: true)
    smiles_ch = Channel.value(params.smiles ?: "null")

    GENERATE_MSA(fasta_ch, smiles_ch)

    // Run AF3 on nolig JSON always; withlig JSON only when SMILES was provided
    json_ch = GENERATE_MSA.out.nolig_json
        .mix(GENERATE_MSA.out.withlig_json)

    RUN_AF3(json_ch)
}
