================================================================================
 CHAGent — Artifact for ACSAC'26 (Paper #186)
 Extracting Access Control Policies from Natural Language Access Requirements
================================================================================

OVERVIEW
--------
CHAGent is a pipeline that turns Natural Language Access Control Requirements
(NLACPs) into structured Access Control Policies (ACPs). An ACP is a list of
Access Control Rules (ACRs); each ACR is a dictionary with six fields:

    decision  (allow | deny)
    subject   action   resource   purpose   condition

Missing fields take the literal value 'none'. The full schema and worked
examples live in artifact/generation/evaluation/prompts.py (ACP_DEFN).

The pipeline has three modules, each trained and evaluated independently:

  1. Identification (artifact/identification/)
       Fine-tuned bert-base-uncased binary classifier that decides whether a
       sentence is an NLACP.

  2. Generation (artifact/generation/)
       LoRA fine-tuned meta-llama/Meta-Llama-3-8B-Instruct that generates the
       ACP from an NLACP. Evaluation (artifact/generation/evaluation/) adds:
         - Retrieval (RAG): per-component FAISS entity stores snap generated
           values to known entities (artifact/data/vectorstores/).
         - Verification-guided iterative refinement: the BART verifier flags an
           error category and the generator re-generates, up to 3 times.

  3. Validation / Verification (artifact/validation/)
       facebook/bart-large classifier that labels a (NLACP, policy) pair as
       'correct' or one of 11 error categories.

DIRECTORY LAYOUT
----------------
  artifact/          Code, data, and (after training) model checkpoints
  claims/            One folder per paper claim: claim.txt, run.sh, expected/
  infrastructure/    Hardware/software requirements and access notes
  install.sh         Installs all dependencies into ./.venv
  requirements.txt   Python dependencies
  README.txt         This file
  license.txt        License
  use.txt            Intended use and limitations
  paper/             The paper PDF

REQUIREMENTS
------------
See infrastructure/README.txt for full details. In short:
  - Linux with an NVIDIA CUDA GPU (>= 24 GB VRAM recommended for LLaMa-3-8B).
  - Python 3.10.
  - A HuggingFace account with access to the gated model
    meta-llama/Meta-Llama-3-8B-Instruct.

INSTALLATION
------------
  ./install.sh                 # creates ./.venv and installs everything
  source .venv/bin/activate

  # Authenticate for the gated LLaMa-3 base model (choose one):
  huggingface-cli login
  export HF_TOKEN=<your_token>

  # Optional but recommended: point the HF cache at a large disk
  export HF_HOME=/path/with/space/huggingface

DATA (already included under artifact/data/ — no download needed)
-----------------------------------------------------------------
  document_folds/<fold>.csv       Identification test data (columns: input, acp, output)
  document_folds/<fold>_acp.csv   Generation eval data    (columns: input, output[, origin])
  vectorstores/<dataset>/...      FAISS entity indexes for retrieval
  verification/{utrain,uval,utest}.csv  Verifier data (labels 0-11)

  Folds/datasets: t2p, acre, ibm, collected, cyber, overall (+ misc store).

PRETRAINED CHECKPOINTS (download; ~15 GB total)
-----------------------------------------------
Checkpoints are hosted under https://huggingface.co/chagent-artifacts:
  chagent-artifacts/chagent-generation     generators (<dataset>_act/<seed>/checkpoint,
                                            seeds 2,3,4) + verification/checkpoint
  chagent-artifacts/chagent-verification    seed-2 BART verifier (2/checkpoint)
  chagent-artifacts/chagent-identification  identifiers (single seed; may be
                                            private/gated — set HF_TOKEN)

Fetch and arrange them into the exact paths the scripts expect with:

    ./download_checkpoints.sh

It symlinks the Hub's nested <dataset>_act/<seed>/checkpoint layout into the
flat <dataset>_act_<seed>/checkpoint layout eval_chagent.py uses, places the
verifier for both the generation and validation claims, and links the
identification checkpoints to artifact/checkpoints/id/<dataset>/checkpoint. The
identification download is non-fatal; if it is unavailable, train those quickly
(see claims/claim1_identification).

RUNNING THE MODULES (run each script from its OWN directory)
------------------------------------------------------------
  # 1. Identification (train, then evaluate a fold)
  cd artifact/identification
  python train_classifier.py --dataset_path=../data/document_folds/collected.csv \
         --out_dir=../checkpoints/id/collected --seed=0
  python evaluate_classification.py --mode=collected --seed=0

  # 2. Verifier (train + test)
  cd artifact/validation
  python train_test_verifier_single_split.py --dataset_path=../data/verification \
         --seed=2 --out_dir=../checkpoints/verification

  # 3. Generator (LoRA fine-tune)
  cd artifact/generation
  python train_generator.py \
         --train_path=<train_dataset> \
         --seed=2 --out_dir=../checkpoints/cyber_act_2

  # 4. End-to-end CHAGent evaluation (DSARCP, with refinement)
  cd artifact/generation/evaluation
  python eval_chagent.py --mode=cyber --result_dir="results/sarcp" --k=3 --seed=2 --refine

CHECKPOINT PATH CONVENTIONS (important)
---------------------------------------
The evaluation scripts load checkpoints from fixed relative paths:
  - Identification eval expects:  ../checkpoints/id/<mode>/checkpoint
  - Generation eval expects:      ../checkpoints/<mode>_act_<seed>/checkpoint   (LoRA adapter)
  - Verifier used by generation:  ../checkpoints/verification/checkpoint
        (i.e. artifact/generation/checkpoints/verification/checkpoint)
  - Verifier eval (Claim 3) expects: checkpoints/verification/checkpoint
        (i.e. artifact/validation/checkpoints/verification/checkpoint)
Trainers save into <out_dir> with an inner checkpoint-XXXX directory (and the
identification trainer appends _<seed> to out_dir). After training, make sure
the produced checkpoint directory is reachable at the exact path the evaluator
expects (rename/symlink the inner checkpoint-XXXX to "checkpoint" if needed).

REPRODUCING PAPER CLAIMS
------------------------
Each claim has a self-contained runner that EVALUATES PROVIDED CHECKPOINTS
(no training required for reproduction):
  claims/claim1_identification/run.sh   evaluates one checkpoint per dataset
  claims/claim2_generation/run.sh       runs 3 seeds x dataset (see below)
  claims/claim3_verification/run.sh     evaluates the seed-2 verifier checkpoint
  claims/claim4_ablation/run.sh         retrieval/post-process/refinement ablation

Checkpoints (run ./download_checkpoints.sh first — see above):
  - Generation: complete set — every dataset x seeds {2,3,4}
      (artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint)
  - Validation/verifier: the seed-2 checkpoint, placed at
      artifact/validation/checkpoints/verification/checkpoint   (Claim 3) and
      artifact/generation/checkpoints/verification/checkpoint   (Claims 2 & 4)
  - Identification: single seed per dataset, from the chagent-identification
      repo, linked to artifact/checkpoints/id/<mode>/checkpoint
      (train locally if the repo is unavailable)

Generation reproduction protocol (Claims 2 & 4):
  The generation runner is executed THREE TIMES per dataset, once per seed
  (seeds 2, 3, 4). Each run prints its own SARCP F1 and ACR-Generation F1. The
  MEAN and STANDARD DEVIATION across the three seeds are computed EXTERNALLY
  (not by the script); collect the three per-seed values and aggregate them,
  then compare to the paper. The seed values are set via the SEEDS variable at
  the top of run.sh and match the checkpoint directory names (<mode>_act_<seed>).

Every run.sh prints results in the same format shown in the corresponding
claims/<claim>/expected/ file. See each claim.txt for what it demonstrates and
which paper table/figure it maps to.

Note on seed coverage:
  The generation checkpoints cover all three seeds (2, 3, 4), so Claims 2 and 4
  reproduce the reported per-seed results directly (mean/SD aggregated externally).

  For identification (Claim 1) and verification (Claim 3) we publish a single
  representative-seed CHECKPOINT (for verification, seed 2 — each verifier
  checkpoint is ~5 GB, hence one seed), which reproduces that seed's reported
  results exactly.
    - Claim 3: the paper's verifier result is a mean over seeds 0, 1, 2. The
      per-seed evaluation logs for all three are included as reference
      (claims/claim3_verification/eval_logs/ver_{0,1,2}.txt); run.sh reproduces
      seed 2, the only published checkpoint.
    - Claim 1: one checkpoint per dataset (single seed) reproduces that seed's
      identification results.
  Reproducing additional seeds is a simple extension — both modules are
  lightweight (BERT/BART) and the training scripts + data are included, so you
  can retrain the remaining seeds and evaluate them the same way. Each run.sh
  prints the exact train command; mean/SD across seeds is aggregated externally.

NOTE ON SECRETS
---------------
Do NOT hardcode HuggingFace tokens in scripts. Pass them via the HF_TOKEN
environment variable or `huggingface-cli login`.
