#!/usr/bin/env bash
#
# Claim 2 — End-to-end CHAGent policy generation (DSARCP).
# Runs eval_chagent.py with retrieval + iterative refinement for each dataset
# and each of the three seeds, using the PROVIDED checkpoints.
#
# Mean/SD across the three seeds are computed EXTERNALLY from the per-seed
# F1 values printed below.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---- EDIT THESE so they match your checkpoint directory names ----
# Generator checkpoints must exist at:
#   artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint
DATASETS="${DATASETS:-t2p acre ibm collected cyber}"
SEEDS="${SEEDS:-2 3 4}"          # the three seeds used in the paper (match checkpoint dirs)
K=3                               # entities retrieved per component (fixed at 3 for gen eval)
RESULT_DIR="${RESULT_DIR:-results/sarcp}"
# ------------------------------------------------------------------

cd "$REPO_ROOT/artifact/generation/evaluation"

VER_CKPT="../checkpoints/verification/checkpoint"
if [ ! -d "$VER_CKPT" ]; then
    echo "ERROR: verifier checkpoint not found at artifact/generation/checkpoints/verification/checkpoint"
    echo "       Refinement (--refine) needs it. Copy/symlink the seed-2 BART"
    echo "       verifier checkpoint there, e.g.:"
    echo "         ln -s \"\$(pwd)/../../validation/checkpoints/2/checkpoint\" \"\$(pwd)/../checkpoints/verification/checkpoint\""
    exit 1
fi

for mode in $DATASETS; do
    for seed in $SEEDS; do
        gen_ckpt="../checkpoints/${mode}_act_${seed}/checkpoint"
        echo "############################################################"
        echo "# CHAGent DSARCP — dataset: ${mode}  seed: ${seed}  k: ${K}"
        echo "# generator checkpoint: ${gen_ckpt}"
        echo "############################################################"
        if [ ! -d "$gen_ckpt" ]; then
            echo "WARNING: generator checkpoint not found at $gen_ckpt — skipping."
            continue
        fi
        python eval_chagent.py \
            --mode="${mode}" \
            --seed="${seed}" \
            --k="${K}" \
            --result_dir="${RESULT_DIR}" \
            --refine
    done
done

echo
echo "Done. For each dataset, collect the three per-seed F1 values printed above"
echo "(SARCP F1 and ACR-Generation F1) and compute mean +/- SD EXTERNALLY, then"
echo "compare against the paper (see claim.txt for the table reference)."
