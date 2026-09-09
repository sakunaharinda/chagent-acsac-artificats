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

DATA (already included under artifact/data/)
--------------------------------------------
  document_folds/<fold>.csv       Identification test data (columns: input, acp, output)
  document_folds/<fold>_acp.csv   Generation eval data    (columns: input, output[, origin])
  vectorstores/<dataset>/...      FAISS entity indexes for retrieval
  verification/{utrain,uval,utest}.csv  Verifier data (labels 0-11)

  Folds/datasets: t2p, acre, ibm, collected, cyber, overall (+ misc store).
  Generator TRAINING data is pulled from the HuggingFace Hub by name
  (e.g. "Sakuna/llama3_cyber_reasoning_chat_with_act"), not from disk.

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
         --train_path="Sakuna/llama3_cyber_reasoning_chat_with_act" \
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

Checkpoints shipped with this artifact:
  - Generation: complete set — every dataset x every seed
      (artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint)
  - Identification: ONE seed per dataset
      (artifact/checkpoints/id/<mode>/checkpoint)
  - Validation/verifier: the seed-2 checkpoint
      (artifact/checkpoints/verification/checkpoint; also copy/symlink it to
       artifact/generation/checkpoints/verification/checkpoint for Claims 2 & 4)

Generation reproduction protocol (Claims 2 & 4):
  The generation runner is executed THREE TIMES per dataset, once per seed.
  Each run prints its own SARCP F1 and ACR-Generation F1. The MEAN and STANDARD
  DEVIATION across the three seeds are computed EXTERNALLY (not by the script);
  collect the three per-seed values and aggregate them, then compare to the
  paper. Set the seed values via the SEEDS variable at the top of run.sh so they
  match your checkpoint directory names (<mode>_act_<seed>).

Every run.sh prints results in the same format shown in the corresponding
claims/<claim>/expected/ file. See each claim.txt for what it demonstrates and
which paper table/figure it maps to.

NOTE ON SECRETS
---------------
Do NOT hardcode HuggingFace tokens in scripts. Pass them via the HF_TOKEN
environment variable or `huggingface-cli login`.
