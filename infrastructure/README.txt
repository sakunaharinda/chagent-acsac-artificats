================================================================================
 Infrastructure Requirements & Access Notes
 CHAGent — ACSAC'26 Artifact (Paper #186)
================================================================================

HARDWARE
--------
  - GPU: 1x NVIDIA CUDA GPU.
      * LLaMa-3-8B LoRA fine-tuning + inference: >= 40 GB VRAM recommended
        (e.g., Nvidia A100). bf16 + flash-attention-2 +
        8-bit AdamW keep training within this budget.
      * BERT (identification) and BART-large (verification) fit comfortably in
        <= 16 GB VRAM.
  - CPU/RAM: >= 8 CPU cores and >= 32 GB system RAM recommended.
  - Disk: >= 60 GB free.
      * ~16-20 GB for the LLaMa-3-8B base model + HuggingFace cache.
      * Space for checkpoints under artifact/<module>/checkpoints/ and results/.

SOFTWARE
--------
  - OS: Linux (Ubuntu 20.04/22.04 tested class of environment).
  - Python: 3.12 (tested with 3.12.13). The interpreter must include the
    _ctypes stdlib module (pyenv builds without libffi omit it and will fail).
  - NVIDIA driver compatible with the installed torch wheel. By default
    install.sh installs torch (2.8.0) from PyPI, whose Linux wheels bundle a
    CUDA runtime (no system CUDA toolkit needed). On networks that throttle
    PyPI's CDN, set TORCH_CUDA=cu126 (or cu128) to pull torch from
    download.pytorch.org instead — pick a tag matching your driver.
  - nvcc / CUDA toolkit is required ONLY to build flash-attn (optional; used by
    train_generator.py and eval_chagent_sar.py). The main DSARCP evaluation
    runs without flash-attn.
  - All Python dependencies are installed by ../install.sh (see ../requirements.txt).

EXTERNAL ACCESS / ACCOUNTS REQUIRED
-----------------------------------
  - HuggingFace account with ACCEPTED access to the gated model:
        meta-llama/Meta-Llama-3-8B-Instruct
    Provide credentials via `huggingface-cli login` or the HF_TOKEN env var.
  - Network access to download models on first run:
        meta-llama/Meta-Llama-3-8B-Instruct   (generator base)
        facebook/bart-large                    (verifier base)
        bert-base-uncased                      (identifier base)
        mixedbread-ai/mxbai-embed-large-v1     (retrieval embeddings)
    After the first download these are cached under HF_HOME.
  - Generator training data is fetched from the HuggingFace Hub by dataset name.
  - Pretrained CHAGent checkpoints (~15 GB+) are downloaded from:
        https://huggingface.co/chagent-artifacts
        chagent-artifacts/chagent-generation     (~9.8 GB) generators + verifier
        chagent-artifacts/chagent-verification    (~4.9 GB) seed-2 BART verifier
        chagent-artifacts/chagent-identification  identifiers (single seed)
    Use ../download_checkpoints.sh to fetch and place them. The generation and
    verification repos are public; the identification repo may be private/gated
    (set HF_TOKEN / huggingface-cli login). The identification download is
    non-fatal and its checkpoints are linked automatically; if unavailable, train
    locally (see claims/claim1_identification).
  - Testing datasets are already included under artifact/data/ (no download).

PUBLIC RESEARCH INFRASTRUCTURE (optional)
-----------------------------------------
The artifact runs on a single-GPU machine and is compatible with common public
research testbeds that offer NVIDIA GPUs, e.g.:
  - Chameleon Cloud (GPU nodes)
  - CloudLab (GPU profiles)
  - SPHERE / FABRIC (where GPU resources are available)
  - Google Colab (A100/L4 high-RAM runtime; mind session limits for training)
On any of these, provision a Linux GPU instance, clone the repository, run
./install.sh, authenticate with HuggingFace, then follow claims/*/run.sh.

ESTIMATED RUNTIMES (single NVIDIA GPU, authors' setup; hardware-dependent)
--------------------------------------------------------------------------
Full DSARCP evaluation (eval_chagent.py --refine), measured mean wall-clock time
PER SEED, averaged over the available seeds (from claims/claim2_generation/eval_logs):

  dataset     mean time / seed     
  ---------   ----------------    
  ibm         ~19 min              
  cyber       ~25 min              
  collected   ~25 min              
  t2p         ~38 min              
  overall     ~64 min              
  acre        ~118 min             


REPRODUCIBILITY NOTES
---------------------
  - Seeds are exposed via --seed on every script; the paper's seeds are used in
    claims/*/run.sh.
  - Generation uses greedy decoding (do_sample=False). A metric variation
    across GPU/driver/library versions and seeds is expected.
