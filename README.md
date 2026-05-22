# AF3 Conformations Pipeline

A Nextflow pipeline for generating AlphaFold3 (AF3) structural predictions on an HPC cluster with SGE job scheduling. Given a protein FASTA file and an optional ligand SMILES string, the pipeline runs a ColabFold MSA, builds AF3 input JSON(s), and submits GPU inference jobs — producing both an apo (no-ligand) and a holo (with-ligand) structural prediction when a ligand is specified.

## Overview

```
FASTA + optional SMILES
        │
        ▼
GENERATE_MSA (CPU, SGE)
  colabfold_batch --msa-only
  prepare_af3_json.py
        │
        ├─── AF3nolig.json ──► RUN_AF3 → results/AF3nolig/
        └─── AF3withlig.json ─► RUN_AF3 → results/AF3withlig/   (if SMILES given)
```

## Repository Structure

```
.
├── inputs/                     # Input FASTA files
├── nextflow/
│   ├── main.nf                 # Nextflow DSL2 workflow
│   └── nextflow.config         # SGE executor and resource profiles
├── scripts/
│   └── af3/
│       ├── prepare_af3_json.py # Builds AF3 input JSON(s) from MSA output
│       └── run_af3_manual.sh   # Standalone SGE script for manual runs
├── results/                    # Pipeline outputs (gitignored)
├── work/                       # Nextflow intermediate files (gitignored)
└── run.sh                      # Convenience wrapper to launch the pipeline
```

## Requirements

- **HPC cluster with SGE** and access to the `iris-gpu` queue
- **Nextflow** (via the `nf-env` conda environment at `/projectnb/docking/imhaoyu/.conda/envs/nf-env`)
- **ColabFold** (`colabfold_batch`) loaded via `miniconda` + `gcc/13.2.0` modules
- **AlphaFold3** loaded via `alphafold3/3.0.0` module

## Usage

### Recommended: `run.sh` wrapper

`run.sh` activates the Nextflow environment and launches on the SGE profile.

```bash
# Protein only (no ligand)
./run.sh --fasta inputs/Q5SKN9.fa

# Protein + ligand
./run.sh --fasta inputs/Q5SKN9.fa --smiles "CC(=O)Oc1ccccc1C(=O)O"

# Resume after a failure
./run.sh --fasta inputs/Q5SKN9.fa -resume

# Dry run — validate pipeline logic without submitting jobs
./run.sh --fasta inputs/Q5SKN9.fa -preview
```

### Direct Nextflow invocation

```bash
nextflow run nextflow/main.nf -profile sge \
    --fasta inputs/Q5SKN9.fa \
    --smiles "CC(=O)Oc1ccccc1C(=O)O"
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `--fasta` | *(required)* | Path to input FASTA file |
| `--smiles` | `null` | SMILES string for ligand (omit for protein-only) |
| `--outdir` | `results` | Output directory |
| `--model_dir` | `af3_info/af3_weights` | Path to AF3 model weights |
| `--colabfold_env` | `/projectnb2/docking/imhaoyu/localcolabfold/colabfold-conda` | ColabFold conda env path |

## Outputs

Results are written to `results/<fasta_basename>/`:

```
results/
└── Q5SKN9/
    ├── msa/
    │   ├── AF3nolig.json       # AF3 input JSON (protein only)
    │   └── AF3withlig.json     # AF3 input JSON (protein + ligand, if SMILES given)
    ├── AF3nolig/               # AF3 prediction outputs (apo)
    └── AF3withlig/             # AF3 prediction outputs (holo, if SMILES given)
```

Pipeline monitoring files are written to `results/`:
- `pipeline_trace.txt` — per-task resource usage
- `pipeline_timeline.html` — visual execution timeline

## Manual SGE Submission

For single predictions outside Nextflow, edit the variables at the top of `scripts/af3/run_af3_manual.sh` and submit:

```bash
# Edit FASTA, WORK_DIR, SMILES, MODEL_DIR in the script, then:
qsub scripts/af3/run_af3_manual.sh
```

## Pipeline Processes

### `GENERATE_MSA` (CPU, 8 cores, 16 GB, 4 h walltime)

1. Runs `colabfold_batch --msa-only` to generate the paired MSA (`.a3m`)
2. Runs `scripts/af3/prepare_af3_json.py` to build `AF3nolig.json` (always) and `AF3withlig.json` (when `--smiles` is provided)

### `RUN_AF3` (GPU, 4 cores, 32 GB, 48 h walltime, `iris-gpu` queue)

Runs `run_alphafold.sh` with `--norun_data_pipeline` (MSA already computed), producing structure predictions for each input JSON.

## Development Notes

- Use `-resume` to skip already-completed steps after a failure — Nextflow caches results in `work/`
- The `-preview` flag validates pipeline syntax and graph without submitting any jobs
- Add new input FASTA files to `inputs/` and gitignore large outputs via `.gitignore`
- Commit messages follow `<type>: <description>` convention (`feat`, `fix`, `refactor`, `docs`, `config`)
