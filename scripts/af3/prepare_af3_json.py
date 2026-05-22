#!/usr/bin/env python3
"""
Prepare AF3 input JSON(s) from a colabfold MSA output directory.

Always writes AF3nolig.json. If --smiles is provided, also writes AF3withlig.json.
"""

import copy
import glob
import json
import logging
import os
import argparse
from typing import Optional

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

_AF3_TEMPLATE: dict = {"dialect": "alphafold3", "version": 1, "name": "", "modelSeeds": [1], "sequences": []}


def _read_a3m(path: str) -> str:
    with open(path) as fh:
        return fh.read().strip("\x00")


def _read_fasta_seq(path: str) -> str:
    with open(path) as fh:
        lines = fh.readlines()
    for i, line in enumerate(lines):
        if line.startswith(">") and i + 1 < len(lines):
            return lines[i + 1].strip()
    raise ValueError(f"No sequence found in {path}")


def _find_one(pattern: str, label: str) -> str:
    matches = glob.glob(pattern)
    if not matches:
        raise FileNotFoundError(f"No {label} found matching: {pattern}")
    if len(matches) > 1:
        log.warning("Multiple %s found, using first: %s", label, matches[0])
    return matches[0]


def build_sequences(
    work_dir: str, smiles: Optional[str] = None
) -> tuple[list, list]:
    fasta = _find_one(os.path.join(work_dir, "*.fa*"), "FASTA file")
    # colabfold_batch --msa-only writes the merged MSA as <name>.a3m at the root
    a3m = _find_one(os.path.join(work_dir, "*.a3m"), "merged .a3m file")

    protein: dict = {
        "protein": {
            "id": ["A"],
            "sequence": _read_fasta_seq(fasta),
            "modifications": [],
            "unpairedMsa": _read_a3m(a3m),
            "pairedMsa": "",
            "templates": [],
        }
    }

    nolig = [protein]
    withlig = [protein, {"ligand": {"id": ["B"], "smiles": smiles}}] if smiles else []
    return nolig, withlig


def write_json(sequences: list, name: str, out_path: str) -> None:
    content = copy.deepcopy(_AF3_TEMPLATE)
    content["name"] = name
    content["sequences"] = sequences
    with open(out_path, "w") as fh:
        json.dump(content, fh, indent=2)
    log.info("Wrote %s", out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", help="Directory with FASTA and colabfold MSA output")
    parser.add_argument("--name", help="Job name for AF3 (default: FASTA basename)")
    parser.add_argument("--smiles", default=None, help="SMILES string for ligand (optional)")
    args = parser.parse_args()

    work_dir = os.path.abspath(args.work_dir)

    if args.name:
        name = args.name
    else:
        fasta = _find_one(os.path.join(work_dir, "*.fa*"), "FASTA file")
        name = os.path.splitext(os.path.basename(fasta))[0]

    nolig_seqs, withlig_seqs = build_sequences(work_dir, args.smiles)

    write_json(nolig_seqs, name, os.path.join(work_dir, "AF3nolig.json"))
    if args.smiles:
        write_json(withlig_seqs, f"{name}_withlig", os.path.join(work_dir, "AF3withlig.json"))
        log.info("Created AF3nolig.json and AF3withlig.json")
    else:
        log.info("No SMILES provided — created AF3nolig.json only")


if __name__ == "__main__":
    main()
