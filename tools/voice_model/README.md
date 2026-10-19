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

## Pipeline

1. **Template data**: `generate_data.py` builds memos from clean parts
   (known labels) and roughens them like speech-to-text output.
2. **Teacher data**: `teacher_gen.py` asks a larger model running locally
   (Qwen3-8B in llama-server) for varied memos *and* their labels, schema-
   constrained and filtered. Templates teach structure; the teacher adds
   open-ended topics and real titles.
3. **Train**: `train.py`, a full fine-tune with loss on the answer only.
4. **Evaluate**: `eval.py` against `eval_memos.jsonl`, 30 hand-written memos
   never used for training. `rules_baseline_test.dart` exports the rules
   shaper's answers so both are scored the same way.
5. **Export**: `export.sh` converts to GGUF and quantises, with the same
   llama.cpp version the app builds (`b11716`).

The prompt (`common.py`) and the GBNF grammar (`lib/voice/llm_shaper.dart`)
must match what the model was trained on.
