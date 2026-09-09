#!/usr/bin/env bash
#
# Claim 3 — Policy verifier evaluation.
# Evaluates the provided seed-2 BART verifier checkpoint on the verification
# test set. eval_test.py takes no arguments (paths are fixed in the script).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPO_ROOT/artifact/validation"

CKPT="../checkpoints/verification/checkpoint"
if [ ! -d "$CKPT" ]; then
    echo "ERROR: verifier checkpoint not found at artifact/checkpoints/verification/checkpoint"
    echo "       Place the seed-2 BART verifier checkpoint there. To (re)train:"
    echo "         python train_test_verifier_single_split.py --dataset_path=../data/verification --seed=2 --out_dir=../checkpoints/verification"
    echo "       then ensure the produced checkpoint-XXXX dir is reachable as 'checkpoint'."
    exit 1
fi

echo "############################################################"
echo "# Verifier evaluation — checkpoint: ${CKPT}"
echo "# test set: ../data/verification/utest.csv"
echo "############################################################"
python eval_test.py

echo
echo "Done. Compare the binary report, MCC, and 12-class report against the"
echo "paper (see claim.txt for the table reference)."
