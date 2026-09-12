#!/usr/bin/env bash
#
# Claim 2 — End-to-end CHAGent policy generation (DSARCP).
# Runs eval_chagent.py with retrieval + iterative refinement, using the PROVIDED
# checkpoints. On start it asks whether to run the DEFAULT scope (all datasets,
# seed 3) or EVERYTHING (all datasets, seeds 2, 3, 4).
#
# Mean/SD across seeds are computed EXTERNALLY from the per-seed F1 values.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# All six datasets by default. Generator checkpoints are expected at:
#   artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint
DATASETS="${DATASETS:-t2p acre ibm collected cyber overall}"
K=3                               # entities retrieved per component (fixed at 3 for gen eval)
RESULT_DIR="${RESULT_DIR:-results/sarcp}"

# ---- Choose the scope of this run (sets SEEDS) -------------------------------
# Preset SEEDS (or DATASETS) via the environment to skip the prompt entirely,
# e.g.:   DATASETS=ibm SEEDS=3 ./run.sh
if [ -n "${SEEDS:-}" ]; then
    echo "Using preset SEEDS='$SEEDS' (scope prompt skipped)."
elif [ -t 0 ]; then
    cat <<'EOF'
============================================================================
 Claim 2 — choose run scope
============================================================================
  [D] Default    : all datasets, seed 3 only  (6 runs, ~5 hours on an A100)
                   Runs the full pipeline for seed 3; matches the seed-3
                   logs in eval_logs/.

  [E] Everything : all datasets, seeds 2, 3, 4 (18 runs, ~20 hours)
                   Needed only for the full three-seed mean/SD reported in the
                   paper (mean/SD are aggregated externally).

 Time cost of [E]: the full pipeline (retrieval + verification-guided
 refinement) averages ~49 min per (dataset, seed). Per-dataset it ranges from
 ~19 min (ibm) to ~118 min (acre); acre alone is ~6 h across three seeds.
 Running everything is therefore ~13-15 h of GPU time.

 Tip: to run a single cell instead, re-invoke with e.g.
        DATASETS=ibm SEEDS=3 ./run.sh
============================================================================
EOF
    printf "Choice [D/E] (default D): "
    read -r choice || choice=""
    case "$choice" in
        [Ee]*) SEEDS="2 3 4"; echo "-> Running EVERYTHING (all datasets, seeds 2 3 4)." ;;
        *)     SEEDS="3";     echo "-> Running DEFAULT (all datasets, seed 3)." ;;
    esac
else
    echo "Non-interactive shell detected: using DEFAULT scope (all datasets, seed 3)."
    SEEDS="3"
fi
echo "Datasets: $DATASETS"
echo "Seeds:    $SEEDS"
# -----------------------------------------------------------------------------

cd "$REPO_ROOT/artifact/generation/evaluation"

VER_CKPT="../checkpoints/verification/checkpoint"
if [ ! -d "$VER_CKPT" ]; then
    echo "ERROR: verifier checkpoint not found at artifact/generation/checkpoints/verification/checkpoint"
    echo "       Refinement (--refine) needs it. Run ../../download_checkpoints.sh"
    echo "       (it places the generation verifier there automatically)."
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
echo "Done (datasets: $DATASETS | seeds: $SEEDS)."
echo "Each run prints SARCP F1 and ACR-Generation F1; compare them to"
echo "eval_logs/<dataset>_act_<seed>.txt and to the paper (see claim.txt)."
if [ "$SEEDS" != "3" ]; then
    echo "For the multi-seed results, aggregate the per-seed F1 values into"
    echo "mean +/- SD EXTERNALLY."
fi
