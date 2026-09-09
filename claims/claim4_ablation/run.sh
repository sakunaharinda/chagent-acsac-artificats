#!/usr/bin/env bash
#
# Claim 4 — Ablation over retrieval / post-processing / refinement.
# Uses the SAME provided generator checkpoints as Claim 2.
# Mean/SD across seeds are computed EXTERNALLY.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Keep this small by default (ablation is expensive x4 configs). Expand as needed.
DATASETS="${DATASETS:-cyber}"
SEEDS="${SEEDS:-1 2 3}"
K=3                               # entities retrieved per component (fixed at 3 for gen eval)
RESULT_DIR="${RESULT_DIR:-results/ablation}"

cd "$REPO_ROOT/artifact/generation/evaluation"

run_cfg () {
    local label="$1"; shift
    local mode="$1"; shift
    local seed="$1"; shift
    echo "############################################################"
    echo "# Ablation [${label}] — dataset: ${mode}  seed: ${seed}"
    echo "# extra flags: $*"
    echo "############################################################"
    python eval_chagent.py --mode="${mode}" --seed="${seed}" --k="${K}" \
        --result_dir="${RESULT_DIR}/${label}" "$@"
}

for mode in $DATASETS; do
    for seed in $SEEDS; do
        gen_ckpt="../checkpoints/${mode}_act_${seed}/checkpoint"
        if [ ! -d "$gen_ckpt" ]; then
            echo "WARNING: generator checkpoint not found at $gen_ckpt — skipping ${mode}/${seed}."
            continue
        fi
        run_cfg "A_no_retrieve"        "$mode" "$seed" --no_retrieve
        run_cfg "B_retrieve_no_update" "$mode" "$seed" --no_update
        run_cfg "C_retrieve_update"    "$mode" "$seed"
        # D requires the verifier checkpoint (see Claim 2 prerequisites).
        if [ -d "../checkpoints/verification/checkpoint" ]; then
            run_cfg "D_full_refine"    "$mode" "$seed" --refine
        else
            echo "NOTE: skipping config D (--refine) — verifier checkpoint missing at ../checkpoints/verification/checkpoint"
        fi
    done
done

echo
echo "Done. For each dataset, aggregate the per-seed F1 of configs A/B/C/D"
echo "EXTERNALLY (mean +/- SD) and compare the trend against the paper."
