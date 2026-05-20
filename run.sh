#!/bin/bash
set -e

# ---------------------------------------------------------------------
# run.sh — the only file you need to edit when adding a new model
# ---------------------------------------------------------------------
#
# WHAT THIS FILE DOES:
#   Called by the Wraptor worker for every job. Your model runs here.
#
# INPUT:
#   Your input file is always available at:
#     /tmp/input/data{INPUT_EXTENSION}
#   e.g. /tmp/input/data.fasta
#   The extension is set by the INPUT_EXTENSION env var in deploy.sh.
#
# OUTPUT:
#   Write all result files to /tmp/output/
#   The worker will upload everything in /tmp/output/ to S3 automatically.
#   You can write one file or many — all of them will be uploaded.
#
# EXAMPLE FOR A DIFFERENT MODEL:
#   python /app/my_model.py --input /tmp/input/data.pdb --output /tmp/output/
#
# ---------------------------------------------------------------------

python3 /app/predict.py
