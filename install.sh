#!/usr/bin/env bash
#
# install.sh — Installs all dependencies and prepares the CHAGent artifact
#              (ACSAC'26, paper 186) for execution.
#
# Usage:
#   ./install.sh                 # create ./.venv and install everything
#   NO_VENV=1 ./install.sh       # install into the current environment
#   TORCH_CUDA=cu118 ./install.sh# pin a specific CUDA wheel (Linux; e.g. older driver)
#   CPU_ONLY=1 ./install.sh      # install CPU-only torch (no GPU; eval will be slow/unsupported)
#
# By default torch is installed from PyPI, whose Linux wheels already bundle a
# CUDA runtime (and macOS gets the native build) — no --index-url needed.
#
# Requirements assumed to be present on the host:
#   * Python 3.10 (python3.10 or python3 >= 3.9)
#   * A CUDA-capable GPU + driver for training/inference (see infrastructure/)
#   * A HuggingFace account with access to meta-llama/Meta-Llama-3-8B-Instruct
#     (the generator base model is gated). Run `huggingface-cli login` or export
#     HF_TOKEN before executing the artifact — see README.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "=========================================================="
echo " CHAGent artifact installer"
echo " Working directory : $HERE"
echo " Python            : $($PYTHON_BIN --version 2>&1)"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Virtual environment
# ---------------------------------------------------------------------------
if [ "${NO_VENV:-0}" != "1" ]; then
    if [ ! -d ".venv" ]; then
        echo "[1/5] Creating virtual environment at ./.venv ..."
        "$PYTHON_BIN" -m venv .venv
    else
        echo "[1/5] Reusing existing ./.venv ..."
    fi
    # shellcheck disable=SC1091
    source .venv/bin/activate
    PYTHON_BIN="python"
else
    echo "[1/5] NO_VENV=1 set — installing into current environment."
fi

# ---------------------------------------------------------------------------
# 2. Base tooling
# ---------------------------------------------------------------------------
echo "[2/5] Upgrading pip / setuptools / wheel ..."
"$PYTHON_BIN" -m pip install --upgrade pip setuptools wheel

# ---------------------------------------------------------------------------
# 3. PyTorch (installed first so flash-attn can build against it)
#    Default: install from PyPI, whose wheels already bundle a CUDA runtime on
#    Linux (and give the native build on macOS) — no CUDA toolkit needed.
#    Overrides:
#      CPU_ONLY=1        -> force the CPU-only build
#      TORCH_CUDA=cu118  -> pin a specific CUDA wheel (e.g. to match an older
#                           NVIDIA driver); only works on Linux.
# ---------------------------------------------------------------------------
if [ "${CPU_ONLY:-0}" = "1" ]; then
    echo "[3/5] Installing CPU-only torch (GPU features will not work) ..."
    "$PYTHON_BIN" -m pip install "torch>=2.1" \
        --index-url "https://download.pytorch.org/whl/cpu"
elif [ -n "${TORCH_CUDA:-}" ]; then
    echo "[3/5] Installing torch (pinned CUDA build: ${TORCH_CUDA}) ..."
    "$PYTHON_BIN" -m pip install "torch>=2.1" \
        --index-url "https://download.pytorch.org/whl/${TORCH_CUDA}"
else
    echo "[3/5] Installing torch from PyPI (bundles CUDA on Linux) ..."
    "$PYTHON_BIN" -m pip install "torch>=2.1"
fi

# ---------------------------------------------------------------------------
# 4. Python dependencies
# ---------------------------------------------------------------------------
echo "[4/5] Installing project dependencies from requirements.txt ..."
"$PYTHON_BIN" -m pip install -r requirements.txt

# ---------------------------------------------------------------------------
# 5. flash-attention (optional; needed by train_generator.py & eval_chagent_sar.py)
#    Must be built with --no-build-isolation against the torch installed above.
#    Non-fatal: the main DSARCP evaluation (eval_chagent.py) does not require it.
# ---------------------------------------------------------------------------
if [ "${CPU_ONLY:-0}" = "1" ]; then
    echo "[5/5] Skipping flash-attn (CPU_ONLY set)."
else
    echo "[5/5] Installing flash-attn (optional; requires nvcc + CUDA toolkit) ..."
    if "$PYTHON_BIN" -m pip install "flash-attn==2.8.3" --no-build-isolation; then
        echo "      flash-attn installed."
    else
        echo "      WARNING: flash-attn failed to build. This is only required for"
        echo "               train_generator.py and eval_chagent_sar.py"
        echo "               (attn_implementation=\"flash_attention_2\")."
        echo "               The DSARCP evaluation (eval_chagent.py) runs without it."
    fi
fi

echo
echo "=========================================================="
echo " Installation complete."
if [ "${NO_VENV:-0}" != "1" ]; then
    echo " Activate the environment with:  source .venv/bin/activate"
fi
echo
echo " Next steps:"
echo "   1. Authenticate with HuggingFace (gated LLaMa-3 base model):"
echo "        huggingface-cli login       # or: export HF_TOKEN=<your token>"
echo "   2. See README for how to train modules / run the evaluation."
echo "=========================================================="
