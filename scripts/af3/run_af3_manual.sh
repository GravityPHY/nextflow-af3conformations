#!/bin/bash -l
#$ -P docking
#$ -l h_rt=48:00:00
#$ -N af3_prediction
#$ -l gpus=1
#$ -l gpu_c=6.0
#$ -q iris-gpu
#$ -j y
#$ -m ea
#
# Standalone SGE submission script for a single AF3 prediction.
# Used for manual runs outside of the Nextflow pipeline.
#
# Usage (edit the variables below, then: qsub run_af3_manual.sh):
#   FASTA      - path to input FASTA
#   WORK_DIR   - directory where MSA and JSON outputs will be written
#   SMILES     - SMILES string for ligand; leave empty to run protein-only
#   MODEL_DIR  - path to AF3 model weights

set -euo pipefail

FASTA=""           # e.g. /path/to/protein.fa
WORK_DIR=""        # e.g. /path/to/workdir
SMILES=""          # e.g. "CC(=O)Oc1ccccc1C(=O)O"  (leave empty for no ligand)
MODEL_DIR="/projectnb/docking/mlzs/af3_info/af3_weights"
COLABFOLD_ENV="/projectnb2/docking/imhaoyu/localcolabfold/colabfold-conda"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ── Validate inputs ────────────────────────────────────────────────────────────
if [[ -z "$FASTA" || -z "$WORK_DIR" ]]; then
    echo "ERROR: FASTA and WORK_DIR must be set in the script." >&2
    exit 1
fi

mkdir -p "$WORK_DIR"
cp "$FASTA" "$WORK_DIR/"

# ── Step 1: Generate MSA ───────────────────────────────────────────────────────
module load miniconda
module load gcc/13.2.0
source activate "$COLABFOLD_ENV"

cd "$WORK_DIR"
colabfold_batch "$(basename "$FASTA")" ./ --msa-only

# ── Step 2: Build AF3 input JSON(s) ───────────────────────────────────────────
SMILES_ARG=""
if [[ -n "$SMILES" ]]; then
    SMILES_ARG="--smiles '${SMILES}'"
fi

python3 "${SCRIPT_DIR}/prepare_af3_json.py" "$WORK_DIR" \
    --name "$(basename "${FASTA%.*}")" \
    ${SMILES_ARG}

# ── Step 3: Run AF3 ───────────────────────────────────────────────────────────
module load alphafold3/3.0.0

for json_file in AF3nolig.json AF3withlig.json; do
    if [[ -f "$WORK_DIR/$json_file" ]]; then
        out_name="${json_file%.json}"
        run_alphafold.sh \
            --json_path="${WORK_DIR}/${json_file}" \
            --model_dir="${MODEL_DIR}" \
            --norun_data_pipeline \
            --output_dir="${WORK_DIR}/${out_name}"
    fi
done
