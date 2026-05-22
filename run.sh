#!/bin/bash
# Wrapper to run the AF3 conformations Nextflow pipeline.
# Activates the nf-env conda environment and sets JAVA_HOME before launching.
#
# Usage:
#   ./run.sh --fasta inputs/Q5SKN9.fa
#   ./run.sh --fasta inputs/Q5SKN9.fa --smiles "O=P(O)(O)NP=..."
#   ./run.sh --fasta inputs/Q5SKN9.fa -resume
#   ./run.sh --fasta inputs/Q5SKN9.fa -preview      # dry run / syntax check

NF_ENV="/projectnb/docking/imhaoyu/.conda/envs/nf-env"

export JAVA_HOME="${NF_ENV}/lib/jvm"
export PATH="${NF_ENV}/bin:${PATH}"

nextflow run "$(dirname "$0")/nextflow/main.nf" -profile sge "$@"
