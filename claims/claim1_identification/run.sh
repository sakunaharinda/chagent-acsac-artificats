#!/usr/bin/env bash
#
# Claim 1 — NLACP identification.
# Evaluates the provided per-dataset BERT checkpoint on each document fold.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Document folds to evaluate. "overall" is the combined set; edit as needed.
FOLDS="${FOLDS:-t2p acre ibm collected cyber overall}"

cd "$REPO_ROOT/artifact/identification"

for fold in $FOLDS; do
    ckpt="../checkpoints/id/${fold}/checkpoint"
    echo "############################################################"
    echo "# Identification — fold: ${fold}"
    echo "# checkpoint: ${ckpt}"
    echo "############################################################"
    if [ ! -d "$ckpt" ]; then
        echo "WARNING: checkpoint not found at $ckpt — skipping ${fold}."
        echo "         Place the trained checkpoint there, or train with:"
        echo "         python train_classifier.py --dataset_path=../data/document_folds/${fold}.csv --out_dir=../checkpoints/id/${fold} --seed=<seed>"
        continue
    fi
    python evaluate_classification.py --mode="${fold}"
done

echo
echo "Done. Compare the printed {accuracy, precision, recall, f1} per fold"
echo "against the paper (see claim.txt for the table reference)."
