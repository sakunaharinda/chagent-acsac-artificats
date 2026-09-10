#!/usr/bin/env bash
#
# Claim 4 — Ablation over retrieval / post-processing / refinement.
# Uses the SAME provided generator checkpoints as Claim 2.
# Mean/SD across seeds are computed EXTERNALLY.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# All six datasets by default. Each cell runs FOUR configs (A/B/C/D).
DATASETS="${DATASETS:-t2p acre ibm collected cyber overall}"
K=3                               # entities retrieved per component (fixed at 3 for gen eval)
RESULT_DIR="${RESULT_DIR:-results/ablation}"

# ---- Choose the scope of this run (sets SEEDS) -------------------------------
# Each cell runs 4 configs; config D is the full-refine run (same as Claim 2),
# which dominates the cost. Preset SEEDS/DATASETS in the environment to skip the
# prompt, e.g.:   DATASETS=cyber SEEDS=3 ./run.sh
if [ -n "${SEEDS:-}" ]; then
    echo "Using preset SEEDS='$SEEDS' (scope prompt skipped)."
elif [ -t 0 ]; then
    cat <<'EOF'
============================================================================
 Claim 4 (ablation) — choose reproduction scope
============================================================================
  [D] Default    : all datasets, seed 3, 4 configs each (~10 hours on an A100)
                   Reproduces the seed-3 ablation column; matches the seed-3
                   *_no_retrieve / *_no_update / *_no_refine logs in eval_logs/
                   (config D matches Claim 2's seed-3 logs).

  [E] Everything : all datasets, seeds 2, 3, 4, 4 configs each (~30 hours)
                   The full three-seed ablation reported in the paper.
                   (Ablation reference logs are included for seeds 3 and 4;
                   seed-2 runs are valid but have no pre-included log.)

 Time cost: each cell runs 4 configs (A no_retrieve, B no_update, C no_refine,
 D full). Config D is the full pipeline and dominates (~19 min ibm to ~118 min
 acre); A/B/C are faster. All four configs total roughly: ibm ~40 min,
 cyber/collected ~50 min, t2p ~1.9 h, overall ~2.1 h, acre ~3.6 h per seed
 (~10 h for all datasets at one seed).

 Tip: to run one dataset/seed, e.g.  DATASETS=cyber SEEDS=3 ./run.sh
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
echo "Done (datasets: $DATASETS | seeds: $SEEDS)."
echo "Compare each config's F1 to eval_logs/<dataset>_act_<seed>_<variant>.txt"
echo "(config D matches ../claim2_generation/eval_logs/<dataset>_act_<seed>.txt)"
echo "and check the A < B < C <= D trend against the paper."
if [ "$SEEDS" != "3" ]; then
    echo "For multi-seed results, aggregate the per-seed F1 into mean +/- SD EXTERNALLY."
fi
