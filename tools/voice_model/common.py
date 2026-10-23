"""Shared prompt format and scoring for the voice-memo shaper model.

The app builds exactly the same prompt (lib/voice/llm_shaper.dart), so the
instruction text here must stay in sync with it.
"""

from __future__ import annotations

import json
import re

INSTRUCTION = (
    "Turn this voice memo transcript into JSON with keys kind (todo or note), "
    "title, tasks (list of {text, when}) and note. Tasks are short imperative "
    "actions; when is the date or time phrase exactly as spoken, or empty. "
    "Apply corrections like 'scratch that'. Drop filler words."
)


def prompt(transcript: str) -> str:
    """ChatML, shared by Qwen and SmolLM; no system turn, no thinking."""
    return (
        f"<|im_start|>user\n{INSTRUCTION}\n\nTranscript: {transcript}"
        f"<|im_end|>\n<|im_start|>assistant\n"
    )


END = "<|im_end|>"

# The GBNF grammar is read from the app (LlmShaper.grammar) so the evaluator
# and the phone constrain output identically.
def _app_grammar() -> str:
    import pathlib
    dart = pathlib.Path(__file__).resolve().parents[2] / "lib/voice/llm_shaper.dart"
    src = dart.read_text(encoding="utf-8")
    start = src.index("grammar = r'''") + len("grammar = r'''")
    return src[start:src.index("''';", start)]


GRAMMAR = _app_grammar()

# ── scoring ─────────────────────────────────────────────────────────────────

_STOP = {"the", "a", "an", "my", "some", "to", "for", "about", "of", "and",
         "her", "his", "their", "our", "your", "with", "at", "on", "in"}


def _toks(s: str) -> set[str]:
    words = re.findall(r"[a-z0-9']+", s.lower())
    return {w for w in words if w not in _STOP}


def _sim(a: str, b: str) -> float:
    ta, tb = _toks(a), _toks(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def parse(text: str) -> dict | None:
    text = text.strip()
    if text.endswith(END):
        text = text[: -len(END)]
    try:
        obj = json.loads(text)
    except Exception:
        return None
    if not isinstance(obj, dict) or obj.get("kind") not in ("todo", "note"):
        return None
    if not isinstance(obj.get("tasks"), list):
        return None
    for t in obj["tasks"]:
        if not isinstance(t, dict) or not isinstance(t.get("text"), str):
            return None
    return obj


def score(pred: dict | None, expect: dict) -> dict:
    """Valid JSON, kind accuracy, task precision/recall (fuzzy, >= 0.4
    token overlap), and when-phrase agreement on matched tasks."""
    if pred is None:
        return {"valid": 0, "kind": 0, "tp": 0, "np": 0,
                "ne": len(expect["tasks"]), "when_ok": 0, "when_n": 0}
    exp = expect["tasks"]
    got = [t for t in pred["tasks"] if t.get("text", "").strip()]
    used = set()
    tp = when_ok = when_n = 0
    for e in exp:
        best, bi = 0.0, -1
        for i, g in enumerate(got):
            if i in used:
                continue
            s = _sim(e["text"], g["text"])
            if s > best:
                best, bi = s, i
        if best >= 0.4:
            used.add(bi)
            tp += 1
            if e["when"]:
                when_n += 1
                gw = (got[bi].get("when") or "").lower()
                # "*" = the rules baseline found *a* date (it stores the
                # resolved label, not the phrase).
                if gw == "*":
                    when_ok += 1
                elif _toks(e["when"]) and _toks(e["when"]) <= _toks(gw) | _toks(got[bi]["text"]):
                    when_ok += 1
    return {"valid": 1, "kind": int(pred["kind"] == expect["kind"]), "tp": tp,
            "np": len(got), "ne": len(exp), "when_ok": when_ok,
            "when_n": when_n}


def summarize(rows: list[dict]) -> dict:
    n = len(rows)
    tp = sum(r["tp"] for r in rows)
    np_ = sum(r["np"] for r in rows)
    ne = sum(r["ne"] for r in rows)
    p = tp / np_ if np_ else 0.0
    r = tp / ne if ne else 0.0
    return {
        "valid": sum(r_["valid"] for r_ in rows) / n,
        "kind": sum(r_["kind"] for r_ in rows) / n,
        "task_p": round(p, 3), "task_r": round(r, 3),
        "task_f1": round(2 * p * r / (p + r), 3) if p + r else 0.0,
        "when": round(sum(r_["when_ok"] for r_ in rows)
                      / max(1, sum(r_["when_n"] for r_ in rows)), 3),
    }
