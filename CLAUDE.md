# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Research artifact for the ACSAC'26 paper (paper 186) on **CHAGent** — a pipeline that extracts structured **Access Control Policies (ACPs)** from **Natural Language Access Control Requirements (NLACPs)**. The paper PDF is in `paper/`.

An ACP is a Python list of **Access Control Rules (ACRs)**, each a dict with six keys: `decision` (`allow`/`deny`), `subject`, `action`, `resource`, `purpose`, `condition`. Missing values are the literal string `'none'`. This schema is defined verbatim in the model prompt at `artifact/generation/evaluation/prompts.py` (`ACP_DEFN`) and is the contract every module agrees on — change it there and downstream parsing/metrics must change too.

## Pipeline architecture

Three sequential modules under `artifact/`, each independently trained and evaluated:

1. **`identification/`** — Binary `bert-base-uncased` classifier deciding whether a sentence is an NLACP (label column `acp`). Input column is `input`.
2. **`generation/`** — LoRA-fine-tuned `meta-llama/Meta-Llama-3-8B-Instruct` that generates the ACP list from an NLACP. This is the core contribution; evaluation lives in `generation/evaluation/` and wires in retrieval + refinement.
3. **`validation/`** — `facebook/bart-large` sequence classifier acting as a **policy verifier**. Given `(NLACP, policy-rendered-as-sentence)` it predicts one of 12 classes (`ID2AUGS`): `correct` (id 11) or one of 11 error types (wrong decision, missing/incorrect subject/action/resource/condition/purpose, missing rules).

### The generate → verify → refine loop (most important flow)

`generation/evaluation/eval_chagent.py::generate_refine` is the end-to-end DSARCP evaluation. Per NLACP:
1. **Generate** a policy with the fine-tuned LLaMa (`generation_utils.py::generate_llm`, or `generate_step` when `--use_pipe`). Retrieval is on by default.
2. **Retrieve + post-process** (`utils.py::update`): for each rule component, do a FAISS `similarity_search(k=1)` against the per-dataset vectorstore to snap the generated value to a known entity, then `postprocess` it. Skipped under `--no_update`; retrieval itself skipped under `--no_retrieve`.
3. **Verify** with BART (`refinement_utils.py::verify`) → error class. If not `correct` (11), build a targeted correction prompt (`prompts.py::get_error_instrution`) and re-generate. Loop up to `MAX_TRIES = 3`. Only runs under `--refine`.
4. **Score** with `AccessEvaluator`.

Retrieval uses the policy component's value as the query; `origin` selects which dataset's vectorstore to search, and any `*_train` origin is remapped to the `misc` store.

### Two evaluation settings

- **DSARCP** — full six-key schema. `eval_chagent.py`.
- **SAR** — subject/action/resource only, used for comparison against prior work (`senna`, `xia`). `eval_chagent_sar.py`, `srl_results_sar.py`, `generate_comparison.py`. `setting='sar'` in the generation utils strips extra keys.

### Two metric families (in `evaluator.py`)

- **ACR generation** (`strict` and `ent_type` schemas): exact vs. fuzzy rule matching. `ent_type` allows fuzzy component matches via `do_overlap` (longest-common-substring ratio; thresholds are looser for `purpose`/`condition` at 0.2). The headline "ACR Generation" F1 uses `ent_type`.
- **SRL** (`srl_results_sarcp.py` / `srl_results_sar.py`): action-centric — groups subjects/resources/purposes/conditions under each `action`. This is the primary reported metric (`results['srl']`).

## Datasets & data layout (`artifact/data/`)

- **`document_folds/`** — test sets per source corpus. Fold names: `t2p`, `acre`, `ibm`, `collected`, `cyber`, `overall`. Two variants per fold:
  - `<fold>.csv` — columns `input,acp,output`; used by **identification** (needs the `acp` binary label).
  - `<fold>_acp.csv` — used by **generation** eval (`input`, `output`, optional `origin`; `origin` defaults to the fold name).
- **`vectorstores/<dataset>/{subjects,actions,resources,purposes,conditions}_index/`** — FAISS indexes (one per component) for RAG. Loaded by `utils.py::load_vectorstores` using `mixedbread-ai/mxbai-embed-large-v1` embeddings on CUDA. `allow_dangerous_deserialization=True` — these are trusted local pickles. There is also a `misc` store (fallback for training origins).
- **`verification/{utrain,uval,utest}.csv`** — verifier data; columns `inputs,policies,policies_sent,labels` where `labels` is the 0–11 `ID2AUGS` id.
- Training datasets for the generator are loaded from the **HuggingFace Hub** by name (e.g. `Sakuna/llama3_cyber_reasoning_chat_with_act`), not from local files.

## Running

There is no build system, test suite, or dependency manifest checked in. Everything is invoked as standalone Python `click` CLIs, wrapped in SLURM `job_*.sh` scripts. **A CUDA GPU is required** (models load to `cuda:0`; the generator uses `flash_attention_2` + bf16). Each command needs `HF_TOKEN` (LLaMa is gated) and typically `HF_HOME`.

Run each script from **its own directory** — the hardcoded relative paths (`../data/...`, `../checkpoints/...`, `../../data/...`) assume that.

```bash
# 1. Train NLACP identification (from artifact/identification/)
python train_classifier.py --dataset_path=../data/document_folds/cyber.csv --out_dir=checkpoints/id/cyber --seed=0
# Evaluate it (loads ../checkpoints/id/<mode>/checkpoint)
python evaluate_classification.py --mode=cyber --seed=0

# 2. Train the generator (from artifact/generation/) — --train_path is a HF Hub dataset name
python train_generator.py --train_path="Sakuna/llama3_cyber_reasoning_chat_with_act" --seed=115 --out_dir=checkpoints/cyber_act_115

# 3. Train the BART verifier (from artifact/validation/)
python train_test_verifier_single_split.py --seed=2 --out_dir=checkpoints/2

# 4. End-to-end CHAGent eval (from artifact/generation/evaluation/)
python eval_chagent.py --mode=cyber --result_dir="results/sarcp/neww" --k=3 --seed=2 --refine
```

Key `eval_chagent.py` flags (they define the ablations): `--refine` (enable verify+refine loop), `--no_retrieve` (skip RAG), `--no_update` (skip similarity-search post-processing), `--use_pipe` (use `transformers.pipeline` instead of raw `model.generate`), `--k` (entities retrieved per component).

### Checkpoint path conventions (must match across scripts)

`eval_chagent.py` expects `../checkpoints/{mode}_act_{seed}/checkpoint/` (generator LoRA adapter, loaded via `PeftModel`) and `../checkpoints/verification/checkpoint/` (verifier). Training scripts append `_{seed}` to `--out_dir` in some cases (identification does; generator does not). When adding a run, keep the produced path and the consumer path in sync.

## Gotchas

- **`generation/evaluation/utils.py` defines `update` and `convert_to_sent`/`process_label` twice** — the second definition wins (SARCP-aware versions). Don't be misled by the earlier ones.
- Generation stops on hardcoded token ids in `generation_utils.py` (`60`=`]`, `933`=`]\n`, etc.) tuned for the LLaMa-3 tokenizer and the `[...]` list output format. The output is parsed with a regex `\[.*?\]` + `ast.literal_eval`; parse failures return `[]` (counted as `fails`).
- The verifier's binary collapse in `evaluate_classification.py`/`eval_test.py` treats id `11` as negative and everything else as positive.
- `report_to='none'` everywhere — no W&B/tensorboard logging is expected.
- SLURM `job_*.sh` scripts hardcode a personal venv path (`/data/sjay950/research/.venv`) and are environment-specific templates, not portable. `job_train.sh`/`job_eval.sh` are gitignored.

## Security note

The committed `job_*.sh` scripts contain a **hardcoded HuggingFace access token** (`HF_TOKEN=hf_...`) in commands/comments. Treat it as compromised: rotate it and pass tokens via the environment instead of committing them.
