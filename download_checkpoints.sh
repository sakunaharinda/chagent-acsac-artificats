#!/usr/bin/env bash
#
# download_checkpoints.sh — Downloads the pretrained CHAGent checkpoints from the
# HuggingFace Hub into each module's own checkpoints/ folder, in the flat layout
# the evaluation scripts expect. No staging dirs, no symlinks.
#
# Source (https://huggingface.co/chagent-artifacts):
#   - chagent-generation     -> artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint
#                               (+ verification/checkpoint, used by generation refinement)
#   - chagent-identification -> artifact/identification/checkpoints/<mode>_<seed>/checkpoint
#   - chagent-verification   -> artifact/validation/checkpoints/verification/checkpoint
#
# The Hub stores generators/identifiers NESTED as <name>/<seed>/checkpoint; this
# script downloads then renames <name>/<seed> -> <name>_<seed> (a real move) so
# the final path is flat. A ".arranged" marker in each checkpoints/ dir makes
# re-runs skip the (large) re-download. Delete a module's checkpoints/ dir to
# force a fresh download.
#
# If identification is unavailable, it is skipped (train locally — see
# claims/claim1_identification/run.sh).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

GEN_REPO="chagent-artifacts/chagent-generation"
VER_REPO="chagent-artifacts/chagent-verification"
ID_REPO="chagent-artifacts/chagent-identification"

GEN_CK="$REPO_ROOT/artifact/generation/checkpoints"
ID_CK="$REPO_ROOT/artifact/identification/checkpoints"
VAL_CK="$REPO_ROOT/artifact/validation/checkpoints"

# ---------------------------------------------------------------------------
# Locate the HuggingFace download CLI
# ---------------------------------------------------------------------------
if command -v hf >/dev/null 2>&1; then
    HF_DL=(hf download)                       # newer huggingface_hub CLI
elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_DL=(huggingface-cli download)          # older CLI (still works)
else
    echo "ERROR: neither 'hf' nor 'huggingface-cli' found on PATH."
    echo "       Activate the venv (source .venv/bin/activate) or: pip install -U huggingface_hub"
    exit 1
fi

echo "=========================================================="
echo " Downloading CHAGent checkpoints (set HF_TOKEN if throttled)"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Generation: <mode>_act/<seed>/checkpoint  ->  <mode>_act_<seed>/checkpoint
# ---------------------------------------------------------------------------
if [ -f "$GEN_CK/.arranged" ]; then
    echo "[gen] already present at $GEN_CK — skipping (delete it to refresh)."
else
    echo "[gen] downloading $GEN_REPO ..."
    "${HF_DL[@]}" "$GEN_REPO" --repo-type model --local-dir "$GEN_CK"
    for actdir in "$GEN_CK"/*_act/; do
        [ -d "$actdir" ] || continue
        base="$(basename "$actdir")"                       # e.g. cyber_act
        for seeddir in "$actdir"*/; do
            [ -d "${seeddir}checkpoint" ] || continue
            seed="$(basename "$seeddir")"                  # e.g. 2
            dest="$GEN_CK/${base}_${seed}"                 # cyber_act_2
            [ -e "$dest" ] || mv "$seeddir" "$dest"
            echo "  [gen] ${base}_${seed}/checkpoint"
        done
        rmdir "$actdir" 2>/dev/null || true
    done
    touch "$GEN_CK/.arranged"
fi

# ---------------------------------------------------------------------------
# 2. Identification: <mode>/<seed>/checkpoint  ->  <mode>_<seed>/checkpoint
#    (non-fatal — skip if the repo can't be fetched)
# ---------------------------------------------------------------------------
if [ -f "$ID_CK/.arranged" ]; then
    echo "[id]  already present at $ID_CK — skipping (delete it to refresh)."
elif "${HF_DL[@]}" "$ID_REPO" --repo-type model --local-dir "$ID_CK"; then
    for modedir in "$ID_CK"/*/; do
        [ -d "$modedir" ] || continue
        base="$(basename "$modedir")"                      # e.g. cyber
        for seeddir in "$modedir"*/; do
            [ -d "${seeddir}checkpoint" ] || continue
            seed="$(basename "$seeddir")"                  # e.g. 0
            dest="$ID_CK/${base}_${seed}"                  # cyber_0
            [ -e "$dest" ] || mv "$seeddir" "$dest"
            echo "  [id]  ${base}_${seed}/checkpoint"
        done
        rmdir "$modedir" 2>/dev/null || true
    done
    touch "$ID_CK/.arranged"
else
    echo "[id]  WARNING: could not download $ID_REPO — skipped."
    echo "       Train locally via claims/claim1_identification/run.sh, or re-run"
    echo "       with HF_TOKEN set."
fi

# ---------------------------------------------------------------------------
# 3. Validation verifier: repo folder '2/checkpoint' -> 'verification/checkpoint'
# ---------------------------------------------------------------------------
if [ -f "$VAL_CK/.arranged" ]; then
    echo "[val] already present at $VAL_CK — skipping (delete it to refresh)."
else
    echo "[val] downloading $VER_REPO ..."
    "${HF_DL[@]}" "$VER_REPO" --repo-type model --local-dir "$VAL_CK"
    if [ -d "$VAL_CK/2/checkpoint" ] && [ ! -e "$VAL_CK/verification" ]; then
        mv "$VAL_CK/2" "$VAL_CK/verification"
    fi
    echo "  [val] verification/checkpoint"
    touch "$VAL_CK/.arranged"
fi

echo
echo "=========================================================="
echo " Checkpoints ready:"
echo "   Generators  : artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint"
echo "   Gen verifier: artifact/generation/checkpoints/verification/checkpoint"
echo "   Identifiers : artifact/identification/checkpoints/<mode>_<seed>/checkpoint"
echo "   Val verifier: artifact/validation/checkpoints/verification/checkpoint"
echo "=========================================================="
