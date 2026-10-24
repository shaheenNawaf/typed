# Voice-memo shaper model

A small model fine-tuned for one job: turn a voice-memo transcript into the
JSON the app's review sheet wants. It runs on the phone with llama.cpp
(`android/app/src/main/cpp`) as an optional download ("Smarter voice memos");
the rules shaper in `lib/voice/voice_shaper.dart` stays the instant default
and the fallback.

```
{"kind": "todo"|"note", "title": str,
 "tasks": [{"text": str, "when": str}], "note": str}
```

`when` is the date phrase exactly as spoken; `lib/voice/when_parser.dart`
turns it into a real date, so the model never does calendar maths.

## What counts as a task

`written/SPEC.md` is the labelling policy every example follows: tasks are
what the speaker will, needs to or should do; an action is inferred only
from a problem the speaker has no plan for; other people's promises are not
tasks; each item is its own task; tasks keep who, what and where. v1 was
trained on data that broke these (it learned to invent "Fix X" for any
problem and to skip "I should…" inside notes).

## Pipeline (v2)

1. **Template data**: `generate_data.py` builds memos from clean parts
   (known labels) and roughens them like speech-to-text output.
2. **Written data**: `written/*.jsonl`, hand-labelled memos by area (lists,
   work, problems, notes, messy speech, daily life in the Philippines).
   `check_written.py` rejects a row whose task words were not said, with
   filler, a duplicate task or a `when` not copied from the transcript.
   (`teacher_gen.py`, a local Qwen3-8B teacher, is kept for reference: its
   labels invented and dropped tasks too often to train on.)
3. **Assemble**: `build_data.py` mixes both, repeating the written memos and
   holding a slice back for validation.
4. **Train**: `train.py`, a full fine-tune with loss on the answer only.
5. **Evaluate**: `eval.py` on two sets, both kept out of training (near
   duplicates are removed from `written/`):
   - `eval_memos.jsonl`, 40 memos used while tuning;
   - `eval_holdout.jsonl`, 40 memos written before v2 tuning; its errors
     were looked at after v2, so it is no longer blind;
   - `eval_holdout2.jsonl`, 40 memos written before the v2.1 data round
     and never used for a decision: the honest number.
   Scores: kind, task precision/recall/F1, `when`, and `filler` (share of
   answers with "hey", "um", "like need"…). `rules_baseline_test.dart`
   exports the rules' answers and the app's (model answers through the
   checks in `llm_shaper.dart`), so all three are scored the same way.
6. **Export**: `export.sh` converts to GGUF and quantises, with the same
   llama.cpp version the app builds (`b11716`).

```
python generate_data.py --n 4000 --out data/template.jsonl --seed 2
python build_data.py --template data/template.jsonl --repeat 3     --train data/train_v2.jsonl --val data/val_v2.jsonl
python train.py --base Qwen/Qwen3-0.6B --train data/train_v2.jsonl     --val data/val_v2.jsonl --out out/qwen3-0.6b-v2
./export.sh out/qwen3-0.6b-v2 out/gguf/voice-shaper-v2
llama-server -m out/gguf/voice-shaper-v2-Q5_K_M.gguf --port 8091
python eval.py --server http://127.0.0.1:8091 --save data/model_preds.jsonl
```

## Results

App output (model plus the checks in `llm_shaper.dart`) on
`eval_holdout2.jsonl`:

| | kind | task F1 | when |
|---|---|---|---|
| rules only | 0.65 | 0.75 | 0.91 |
| v1 (raw model) | 0.83 | 0.71 | 0.88 |
| v2 (`voice-model-v2`, trained as "v2.1") | 0.95 | 0.91 | 0.89 |

On the 40 development memos v2 scores kind 0.98, task F1 0.88, when 0.90.
With ~50 tasks per set, one task is about two points.

The prompt (`common.py`) and the GBNF grammar (`lib/voice/llm_shaper.dart`)
must match what the model was trained on.
