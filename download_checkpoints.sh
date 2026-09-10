#!/usr/bin/env bash
#
# download_checkpoints.sh — Downloads the pretrained CHAGent checkpoints from the
# HuggingFace Hub and arranges them into the exact paths the evaluation scripts
# expect.
#
# Source (https://huggingface.co/chagent-artifacts):
#     - chagent-artifacts/chagent-generation     (generators),  ~9.8 GB
#         layout: <dataset>_act/<seed>/checkpoint/  and  verification/checkpoint/
#     - chagent-artifacts/chagent-verification    (seed-2 BART verifier),  ~4.9 GB
#         layout: 2/checkpoint/
#     - chagent-artifacts/chagent-identification  (identifiers, single seed)
#         layout: not confirmed here; step 4 probes plausible layouts. May be
#         private/gated (download is non-fatal).
#
# Datasets: t2p acre ibm collected cyber overall     Seeds: 2 3 4
#
# NOTE on the path mismatch: eval_chagent.py loads generators from the FLAT path
#   ../checkpoints/<dataset>_act_<seed>/checkpoint
# while the Hub stores them NESTED as <dataset>_act/<seed>/checkpoint. This script
# creates symlinks so the flat path resolves to the downloaded nested directory.
#
# NOTE on identification: identification checkpoints live in their own repo
# (chagent-identification), typically a single seed. This script downloads it
# (non-fatal) and auto-links to
#   artifact/checkpoints/id/<dataset>/checkpoint   (the path eval expects; no seed)
# If the repo is private/gated/unpublished, train locally (fast — bert-base-uncased)
# via claims/claim1_identification/run.sh.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

GEN_REPO="chagent-artifacts/chagent-generation"
VER_REPO="chagent-artifacts/chagent-verification"
ID_REPO="chagent-artifacts/chagent-identification"

DATASETS="${DATASETS:-t2p acre ibm collected cyber overall}"
SEEDS="${SEEDS:-2 3 4}"

GEN_DL="$REPO_ROOT/artifact/generation/checkpoints_hf"
VER_DL="$REPO_ROOT/artifact/checkpoints_hf"
ID_DL="$REPO_ROOT/artifact/identification/checkpoints_hf"

# ---------------------------------------------------------------------------
# Locate the HuggingFace download CLI
# ---------------------------------------------------------------------------
if command -v hf >/dev/null 2>&1; then
    HF_DL=(hf download)
elif command -v hf >/dev/null 2>&1; then
    HF_DL=(hf download)
else
    echo "ERROR: neither 'huggingface-cli' nor 'hf' found on PATH."
    echo "       Activate the venv (source .venv/bin/activate) or: pip install -U huggingface_hub"
    exit 1
fi

echo "=========================================================="
echo " Downloading CHAGent checkpoints"
echo "   generation     -> $GEN_DL"
echo "   verifier       -> $VER_DL"
echo "   identification -> $ID_DL  (non-fatal if unavailable)"
echo " (set HF_TOKEN if a repo is gated or you hit rate limits)"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Download
# ---------------------------------------------------------------------------
"${HF_DL[@]}" "$GEN_REPO" --repo-type model --local-dir "$GEN_DL"
"${HF_DL[@]}" "$VER_REPO" --repo-type model --local-dir "$VER_DL"

# Identification repo may be private/gated or not published yet — make it
# non-fatal so the rest of the arrangement still runs. Set HF_TOKEN if it is
# gated (huggingface-cli login, or export HF_TOKEN).
ID_OK=0
if "${HF_DL[@]}" "$ID_REPO" --repo-type model --local-dir "$ID_DL"; then
    ID_OK=1
else
    echo "NOTE: could not download $ID_REPO (private/gated/not-published?)."
    echo "      Identification checkpoints will be skipped; train locally via"
    echo "      claims/claim1_identification/run.sh, or re-run with HF_TOKEN set."
fi

# ---------------------------------------------------------------------------
# 2. Arrange generator checkpoints into the flat layout eval_chagent.py expects:
#    artifact/generation/checkpoints/<dataset>_act_<seed>  ->  <GEN_DL>/<dataset>_act/<seed>
#    (so that <...>/<dataset>_act_<seed>/checkpoint resolves)
# ---------------------------------------------------------------------------
GEN_CKPT_DIR="$REPO_ROOT/artifact/generation/checkpoints"
mkdir -p "$GEN_CKPT_DIR"
for d in $DATASETS; do
    for s in $SEEDS; do
        src="$GEN_DL/${d}_act/${s}"
        if [ -d "$src/checkpoint" ]; then
            ln -sfn "$src" "$GEN_CKPT_DIR/${d}_act_${s}"
            echo "  linked ${d}_act_${s} -> ${src}"
        else
            echo "  WARNING: missing $src/checkpoint (skipped)"
        fi
    done
done

# Verifier used by generation refinement:
#   artifact/generation/checkpoints/verification/checkpoint
if [ -d "$GEN_DL/verification/checkpoint" ]; then
    ln -sfn "$GEN_DL/verification" "$GEN_CKPT_DIR/verification"
    echo "  linked generation verifier -> $GEN_DL/verification"
fi

# ---------------------------------------------------------------------------
# 3. Verifier for the validation claim (eval_test.py expects, relative to
#    artifact/validation/):  ../checkpoints/verification/checkpoint
#    i.e. artifact/checkpoints/verification/checkpoint  ->  <VER_DL>/2/checkpoint
# ---------------------------------------------------------------------------
mkdir -p "$REPO_ROOT/artifact/checkpoints"
if [ -d "$VER_DL/2/checkpoint" ]; then
    ln -sfn "$VER_DL/2" "$REPO_ROOT/artifact/checkpoints/verification"
    echo "  linked validation verifier -> $VER_DL/2"
fi

# ---------------------------------------------------------------------------
# 4. Identification checkpoints (separate repo: chagent-identification;
#    typically a single seed). evaluate_classification.py expects, relative to
#    artifact/identification/:  ../checkpoints/id/<dataset>/checkpoint
#    i.e. artifact/checkpoints/id/<dataset>/checkpoint  (NO seed level).
#    The exact inner naming/seed is not confirmed here (repo was not publicly
#    readable at authoring time), so we search a few plausible layouts under
#    $ID_DL and link the first <...>/checkpoint found for each dataset.
# ---------------------------------------------------------------------------
ID_SRC_ROOT="$ID_DL"
ID_DEST="$REPO_ROOT/artifact/checkpoints/id"
if [ "$ID_OK" = "1" ] && [ -d "$ID_SRC_ROOT" ]; then
    mkdir -p "$ID_DEST"
    for d in $DATASETS; do
        found=""
        # try: <d>_act/<seed>/checkpoint, <d>_act/checkpoint, <d>/<seed>/checkpoint, <d>/checkpoint
        for cand in "$ID_SRC_ROOT/${d}_act"/*/checkpoint "$ID_SRC_ROOT/${d}_act/checkpoint" \
                    "$ID_SRC_ROOT/${d}"/*/checkpoint     "$ID_SRC_ROOT/${d}/checkpoint"; do
            if [ -d "$cand" ]; then found="$cand"; break; fi
        done
        if [ -n "$found" ]; then
            ln -sfn "$(dirname "$found")" "$ID_DEST/${d}"
            echo "  linked id/${d} -> $(dirname "$found")"
        else
            echo "  NOTE: no identification checkpoint found for ${d} under $ID_SRC_ROOT (skipped)"
        fi
    done
else
    echo "NOTE: identification checkpoints not available (download skipped/failed)."
    echo "      Re-run with access to $ID_REPO, or train locally (see claim 1)."
fi

echo
echo "=========================================================="
echo " Checkpoints ready:"
echo "   Generators  : artifact/generation/checkpoints/<dataset>_act_<seed>/checkpoint"
echo "   Gen verifier: artifact/generation/checkpoints/verification/checkpoint"
echo "   Val verifier: artifact/checkpoints/verification/checkpoint"
echo "   Identifier  : artifact/checkpoints/id/<dataset>/checkpoint (if published)"
echo
echo " If identification checkpoints were not linked above, the chagent-identification"
echo " repo was unreadable (private/gated — set HF_TOKEN) or its inner folder naming"
echo " differs from the layouts probed in step 4 — adjust the 'cand' patterns there,"
echo " or train locally via claims/claim1_identification/run.sh."
echo "=========================================================="
