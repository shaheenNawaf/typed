"""Teacher-generated training data, from a larger model running locally.

Templates teach structure; a teacher (Qwen3-8B in llama-server on this PC)
adds what templates cannot: open-ended topics, natural phrasing, implicit
tasks and real titles. Each request gets a random scenario and returns both
a messy transcript and its label, constrained to a JSON schema. Examples that
fail checks (a `when` not in the transcript, too many tasks, long titles…)
are dropped.

    llama-server -m Qwen3-8B-Q4_K_M.gguf -ngl 99 -np 4 -c 16384 --port 8091
    python teacher_gen.py --n 2500 --out data/teacher.jsonl --workers 4
"""

from __future__ import annotations

import argparse
import json
import random
import re
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PERSONAS = [
    "a nurse on rotating shifts", "a parent of two young kids", "a university student",
    "a freelance designer", "a small café owner", "a software engineer",
    "a retired teacher", "a project manager", "a real-estate agent",
    "someone renovating their flat", "a marathon trainee", "a new homeowner",
    "a sales rep who drives a lot", "a PhD student", "someone planning a wedding",
    "a dog owner", "someone moving cities", "a high-school teacher",
    "a startup founder", "someone caring for an elderly parent",
]

KINDS = [
    ("todo", "a to-do list of 2 to 5 things they must do"),
    ("todo", "a short errand list with a couple of items to buy"),
    ("todo", "work tasks for the coming days"),
    ("todo", "household chores and repairs"),
    ("todo", "a single thing they must not forget"),
    ("note", "an idea they just had"),
    ("note", "notes from a meeting or call they just finished"),
    ("note", "a reflection on how their week is going"),
    ("note", "a plan or decision they are thinking through"),
    ("note", "something they learned from a podcast, book or article"),
    ("note", "a journal-style memo about their day"),
    ("mixed", "mostly thoughts, but with one or two things they need to do"),
]

QUIRKS = [
    "include filler words like um, uh, like, you know",
    "include a correction such as 'scratch that' or 'no wait' that changes or removes something",
    "state at least one task implicitly, without saying 'I need to' (e.g. 'we're out of milk', 'the sink is leaking again')",
    "mention a date or time for some tasks (e.g. tomorrow, on Friday at 3, next week, by the 12th)",
    "add an item as an afterthought fragment, like 'oh and bread too'",
    "write it as one long run-on sentence with little punctuation",
    "write it all in lowercase with no punctuation, like raw speech-to-text",
    "start with a short lead-in like 'okay groceries' or 'for tomorrow'",
    "repeat a word or two the way people do when speaking",
]

SYSTEM = (
    "You create training data for a notes app. The user dictates a voice "
    "memo; the app turns the transcript into a note or a to-do list. You "
    "write ONE realistic transcript as a speech recogniser would output it, "
    "and the exact JSON the app should produce from it."
)

RULES = """Labelling rules for "output":
- kind: "todo" if the memo is mainly things to do; "note" if it is mainly thoughts, even if it contains a task or two.
- title: 2 to 5 words, a natural name for the note or list (e.g. "Weekend errands", "Notes from the Hannah call", "Groceries"). If the memo opens with a date-only lead-in like "for tomorrow" or "this weekend", use that phrase as the title verbatim with a capital letter (e.g. "For tomorrow").
- tasks: every concrete action, as a short imperative starting with a verb ("Buy milk", "Call the vet about Luna's booster"). Infer the action for implicit tasks ("we're out of rice" -> "Buy rice"; "the tap is leaking again" -> "Fix the leaking tap"). Merge afterthoughts into their task ("buy eggs... oh and bread" -> "Buy eggs and bread"). Apply corrections: drop what was cancelled, keep the replacement. Never include a date or time inside the task text.
- when: the date/time phrase for that task copied EXACTLY as it appears in the transcript (e.g. "tomorrow at 3", "on Friday", "by the 12th"), or "" if none. Only take a lead-in date ("for tomorrow") into tasks when the memo clearly means all of them.
- note: for a note, the memo's content as clean sentences (fillers removed, punctuation fixed, corrections applied), without the task sentences; for a to-do list, any non-task context sentence, else "".
"""

SCHEMA = {
    "type": "object",
    "properties": {
        "transcript": {"type": "string"},
        "output": {
            "type": "object",
            "properties": {
                "kind": {"type": "string", "enum": ["todo", "note"]},
                "title": {"type": "string"},
                "tasks": {"type": "array", "items": {
                    "type": "object",
                    "properties": {"text": {"type": "string"},
                                   "when": {"type": "string"}},
                    "required": ["text", "when"]}},
                "note": {"type": "string"},
            },
            "required": ["kind", "title", "tasks", "note"],
        },
    },
    "required": ["transcript", "output"],
}


def scenario() -> str:
    persona = random.choice(PERSONAS)
    kind, desc = random.choice(KINDS)
    quirks = random.sample(QUIRKS, k=random.choice([1, 2, 2, 3]))
    length = random.choice(["very short (one sentence)", "short (2-3 sentences)",
                            "medium (4-6 sentences)"])
    return (f"Speaker: {persona}.\nMemo: {desc}.\nLength: {length}.\n"
            f"Style: " + "; ".join(quirks) + ".\n"
            "Use specific, varied names, items and places. Do not reuse common "
            "examples like eggs, milk or the dentist unless natural.")


def ask(url: str) -> dict | None:
    body = {
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": scenario() + "\n\n" + RULES},
        ],
        "temperature": 0.9,
        "top_p": 0.95,
        "max_tokens": 900,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_schema",
                            "json_schema": {"name": "example", "schema": SCHEMA}},
    }
    req = urllib.request.Request(f"{url}/v1/chat/completions",
                                 json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        res = json.loads(urllib.request.urlopen(req, timeout=180).read())
        return json.loads(res["choices"][0]["message"]["content"])
    except Exception:
        return None


def valid(ex: dict) -> bool:
    t = ex.get("transcript", "").strip()
    o = ex.get("output", {})
    if len(t) < 15 or len(t) > 900:
        return False
    if len(o.get("title", "").split()) > 6 or not o.get("title"):
        return False
    tasks = o.get("tasks", [])
    if len(tasks) > 8:
        return False
    low = t.lower()
    for task in tasks:
        text, when = task.get("text", ""), task.get("when", "")
        if not text or len(text.split()) > 14:
            return False
        if when and when.lower() not in low:
            return False  # `when` must be copied from the transcript
        if re.search(r"\b(tomorrow|today|tonight|monday|tuesday|wednesday|"
                     r"thursday|friday|saturday|sunday)\b", text, re.I):
            return False  # dates belong in `when`, not the text
    if o.get("kind") == "todo" and not tasks:
        return False
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2500)
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default="http://127.0.0.1:8091")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    random.seed(a.seed)

    lock = threading.Lock()
    kept = rejected = 0
    f = open(a.out, "a", encoding="utf-8")

    def job(_):
        global kept, rejected
        ex = ask(a.url)
        if ex and isinstance(ex.get("output"), dict):
            o = ex["output"]
            # The teacher is loose about capitals; the app's style is
            # sentence case for titles and tasks.
            cap = lambda x: x[:1].upper() + x[1:] if x else x
            o["title"] = cap(o.get("title", "").strip())
            for t in o.get("tasks", []):
                if isinstance(t, dict):
                    t["text"] = cap(t.get("text", "").strip())
        with lock:
            if ex and valid(ex):
                f.write(json.dumps({"transcript": ex["transcript"].strip(),
                                    "output": json.dumps(ex["output"], ensure_ascii=False)},
                                   ensure_ascii=False) + "\n")
                f.flush()
                kept += 1
            else:
                rejected += 1
            if (kept + rejected) % 50 == 0:
                print(f"kept {kept} rejected {rejected}", flush=True)

    with ThreadPoolExecutor(a.workers) as pool:
        list(pool.map(job, range(a.n)))
    print(f"done: kept {kept} rejected {rejected}")
