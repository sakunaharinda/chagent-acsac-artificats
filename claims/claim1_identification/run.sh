#!/usr/bin/env bash
#
# Claim 1 — NLACP identification.
# Evaluates the provided per-dataset BERT checkpoint on each document fold.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Document folds to evaluate. "overall" is the combined set; edit as needed.
FOLDS="${FOLDS:-t2p acre ibm collected cyber overall}"
SEED="${SEED:-0}"          # published identification checkpoints use seed 0

cd "$REPO_ROOT/artifact/identification"

for fold in $FOLDS; do
    ckpt="checkpoints/${fold}_${SEED}/checkpoint"
    echo "############################################################"
    echo "# Identification — fold: ${fold}  seed: ${SEED}"
    echo "# checkpoint: artifact/identification/${ckpt}"
    echo "############################################################"
    if [ ! -d "$ckpt" ]; then
        echo "WARNING: checkpoint not found at artifact/identification/${ckpt} — skipping ${fold}."
        echo "         Run ../../download_checkpoints.sh to fetch the checkpoints."
        continue
    fi
    python evaluate_classification.py --mode="${fold}" --seed="${SEED}"
done

echo
echo "Done. Compare the printed {accuracy, precision, recall, f1} per fold"
echo "against the paper (see claim.txt for the table reference)."
