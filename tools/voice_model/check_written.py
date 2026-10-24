"""Checks written training memos (written/*.jsonl, see written/SPEC.md).

    python check_written.py written/lists.jsonl

Prints each failing line with the reason; exit code 1 if any fail.
"""

from __future__ import annotations

import json
import sys

from teacher_gen import valid

ok = bad = 0
seen: set[str] = set()
for path in sys.argv[1:]:
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            label = row["label"]
            ex = {"transcript": row["transcript"], "output": label}
        except Exception as e:  # noqa: BLE001
            print(f"{path}:{n}: not a valid row ({e})")
            bad += 1
            continue
        why = None
        if label.get("kind") not in ("todo", "note"):
            why = "kind must be todo or note"
        elif not isinstance(label.get("note"), str):
            why = "note must be a string"
        elif row["transcript"].strip().lower() in seen:
            why = "duplicate transcript"
        elif not valid(ex):
            why = ("failed checks: title 1-6 words, todo needs tasks, task "
                   "<= 14 words with no day names, 'when' copied exactly from "
                   "the transcript, every task's words said in the transcript "
                   "(one inferred word allowed), no filler, no task twice")
        seen.add(row["transcript"].strip().lower())
        if why:
            print(f"{path}:{n}: {why}\n    {line.strip()[:240]}")
            bad += 1
        else:
            ok += 1
print(f"{ok} ok, {bad} failing")
sys.exit(1 if bad else 0)
