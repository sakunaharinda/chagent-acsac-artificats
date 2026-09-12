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

The pipeline has three modules, each trained and evaluated independently:

  1. Identification (artifact/identification/)

  2. Generation (artifact/generation/)

  3. Validation / Verification (artifact/validation/)

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
  - Linux with an NVIDIA CUDA GPU (A100 with >= 40 GB VRAM recommended for LLaMa-3-8B).
  - Python 3.12 (tested with 3.12.13).
  - A HuggingFace account with access to the gated model meta-llama/Meta-Llama-3-8B-Instruct.

INSTALLATION
------------
  bash install.sh                 # creates ./.venv and installs everything
  source .venv/bin/activate

  # Authenticate for the gated LLaMa-3 base model (choose one):
  huggingface-cli login
  export HF_TOKEN=<your_token>

  # Optional but recommended: point the HF cache at a large disk
  export HF_HOME=/path/with/space/huggingface

TEST DATA (already included under artifact/data/ — no download needed)
-----------------------------------------------------------------
  document_folds/<fold>.csv       Identification test data (columns: input, acp, output)
  document_folds/<fold>_acp.csv   Generation eval data    (columns: input, output[, origin])
  vectorstores/<dataset>/...      FAISS entity indexes for retrieval
  verification/{utrain,uval,utest}.csv  Verifier data (labels 0-11)

  Folds/datasets: t2p, acre, ibm, collected, cyber, overall (+ misc store).

PRETRAINED CHECKPOINTS (download; ~20 GB total)
-----------------------------------------------
Checkpoints are hosted under https://huggingface.co/chagent-artifacts:
  chagent-artifacts/chagent-generation     generators (<dataset>_act/<seed>/checkpoint,
                                            seeds 2,3,4) + verification/checkpoint
  chagent-artifacts/chagent-verification    seed-2 BART verifier (2/checkpoint)
  chagent-artifacts/chagent-identification  identifiers (single seed)

Fetch and arrange them into the exact paths the scripts expect with:

    ./download_checkpoints.sh

RUNNING THE MODULES (run each script from its OWN directory)
------------------------------------------------------------
  # 1. Identification (train, then evaluate a fold)
  cd artifact/identification
  python train_classifier.py --dataset_path=../data/document_folds/collected.csv \
         --out_dir=checkpoints/collected --seed=0
  python evaluate_classification.py --mode=collected --seed=0

  # 2. Verifier (train + test)
  cd artifact/validation
  python train_test_verifier_single_split.py --dataset_path=../data/verification \
         --seed=2 --out_dir=checkpoints/verification

  # 3. Generator (LoRA fine-tune)
  cd artifact/generation
  python train_generator.py \
         --train_path=<train_dataset> \
         --seed=2 --out_dir=checkpoints/cyber_act_2

  # 4. End-to-end CHAGent evaluation (DSARCP, with refinement)
  cd artifact/generation/evaluation
  python eval_chagent.py --mode=cyber --result_dir="results/sarcp" --k=3 --seed=2 --refine

CHECKPOINT PATH CONVENTIONS (important)
---------------------------------------
Checkpoints live under each module's own checkpoints/ folder; the eval scripts
load them from these relative paths:
  - Identification eval:  checkpoints/<mode>_<seed>/checkpoint
        (i.e. artifact/identification/checkpoints/<mode>_<seed>/checkpoint)
  - Generation eval:      ../checkpoints/<mode>_act_<seed>/checkpoint   (LoRA adapter)
        (i.e. artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint)
  - Verifier used by generation:  ../checkpoints/verification/checkpoint
        (i.e. artifact/generation/checkpoints/verification/checkpoint)
  - Verifier eval (Claim 3):      checkpoints/verification/checkpoint
        (i.e. artifact/validation/checkpoints/verification/checkpoint)
download_checkpoints.sh places all of these automatically. Trainers save into
<out_dir> with an inner checkpoint-XXXX directory; after training, make sure the
produced checkpoint dir is reachable as ".../checkpoint" (rename the inner
checkpoint-XXXX if needed).

RUNNING THE EXPERIMENTS (claim -> artifact mapping)
---------------------------------------------------
Each of the paper's experiments has a self-contained runner under claims/ that
exercises the corresponding module on the PROVIDED checkpoints (no training
needed). Each claims/<n>/claim.txt states which paper section/table/figure the
experiment maps to, and each run prints results in the format shown in
claims/<n>/expected/.

  claims/claim1_identification/run.sh   NLACP identification, per fold
  claims/claim2_generation/run.sh       end-to-end DSARCP generation
  claims/claim3_verification/run.sh     policy verifier evaluation
  claims/claim4_ablation/run.sh         retrieval/post-process/refinement ablation

Checkpoints (run ./download_checkpoints.sh first — see above):
  - Generation: every dataset x seeds {2,3,4}
      (artifact/generation/checkpoints/<mode>_act_<seed>/checkpoint)
  - Validation/verifier: the seed-2 checkpoint, at
      artifact/validation/checkpoints/verification/checkpoint   (Claim 3) and
      artifact/generation/checkpoints/verification/checkpoint   (Claims 2 & 4)
  - Identification: seed 0 per dataset, from the chagent-identification repo, at
      artifact/identification/checkpoints/<mode>_0/checkpoint
      (train locally if the repo is unavailable)

Generation runs (Claims 2 & 4):
  The generation runner can be run per seed (seeds 2, 3, 4); each run prints its
  own SARCP F1 and ACR-Generation F1. The paper reports the mean/SD over the
  three seeds, aggregated externally — see claims/claim2_generation/claim.txt for
  the interactive scope prompt and the time cost of running all seeds.

Note on seed coverage (single-seed checkpoints for two modules):
  Generation ships all three seeds (2, 3, 4). For identification (Claim 1) and
  verification (Claim 3) a single representative-seed checkpoint is published
  (verifier: seed 2 — each verifier checkpoint is ~5 GB). These runs exercise
  the module and demonstrate the reported behaviour on that seed; obtaining the
  full multi-seed mean/SD is a lightweight extension (BERT/BART train quickly,
  and the training scripts + data are included — each run.sh prints the exact
  train command). For reference, the per-seed evaluation logs for the verifier's
  seeds 0/1/2 are included under claims/claim3_verification/eval_logs/.

NOTE ON SECRETS
---------------
Do NOT hardcode HuggingFace tokens in scripts. Pass them via the HF_TOKEN
environment variable or `huggingface-cli login`.
