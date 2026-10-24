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
    "a call-centre agent in Manila on night shift", "a nurse in Quezon City",
    "a student in Cebu", "a small sari-sari store owner",
    "an office worker in Makati who commutes by jeepney and MRT",
    "a parent in Davao juggling school runs", "a freelancer paid via GCash",
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
    ("mixed", "a summary of a call or meeting where other people promised things, plus one thing the speaker must do"),
    ("note", "a plan they are describing (a garden layout, a room makeover, a trip outline) with no tasks for themselves"),
    ("todo", "a problem they noticed (something broken, something running out) and what they will do about it"),
    ("todo", "a problem they noticed, said with no plan of their own"),
    ("todo", "an appointment or meetup with a day and time, plus something to bring or prepare"),
    ("todo", "a shopping list said as a run of items with no verbs"),
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
    "open with a greeting like 'hey', 'hey so' or 'okay okay so um'",
    "use 'like' and 'basically' as verbal tics the way people do",
    "refer back to something with 'it' or 'them' (e.g. 'finish the slides and send them to Bea')",
]

SYSTEM = (
    "You create training data for a notes app. The user dictates a voice "
    "memo; the app turns the transcript into a note or a to-do list. You "
    "write ONE realistic transcript as a speech recogniser would output it, "
    "and the exact JSON the app should produce from it."
)

RULES = """Labelling rules for "output":
- kind: "todo" if the memo is mainly things to do; "note" if it is mainly thoughts, a summary, a plan being described or a reflection, even if it contains a task or two.
- title: 2 to 5 words, a natural name for the note or list (e.g. "Weekend errands", "Notes from the Hannah call", "Groceries"). If the memo opens with a date-only lead-in like "for tomorrow" or "this weekend", use that phrase as the title verbatim with a capital letter (e.g. "For tomorrow").
- tasks: what the SPEAKER says they will do, need to do or should do, as a short imperative starting with a verb ("Buy milk", "Call the vet about Luna's booster shot"). Rules:
  * Never invent a task. Things other people will do ("Priya will redo the page", "the landlord agreed to fix the gate") are not the speaker's tasks.
  * Infer an action only when the speaker states a problem or a need and says nothing about what they will do about it ("we're out of rice" -> "Buy rice"; "the water heater is clicking" -> "Get the water heater checked"). If they do say what they will do ("the tap is dripping, I'll chase the landlord"), that is the only task.
  * An "I should…", "I need to…" or "I'll…" inside a note is still a task.
  * Keep who, what and where so the task makes sense on its own a week later ("Get to Sofia's recital", not "Get there"; "Send Bea the slides", not "Send them").
  * One task per thing: each item of a list and each afterthought is its own task ("buy eggs... oh and bread" -> "Buy eggs", "Buy bread"). The same task said twice is listed once.
  * A plan with a time ("lunch with Grace on Thursday at 12") is a task even without a verb ("Lunch with Grace").
  * Apply corrections: drop what was cancelled, keep the replacement. Never include a date or time inside the task text.
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


# Words a task may add that were not said: the verbs of inferred actions
# ("we're out of rice" -> "Buy rice") and glue.
_FREE = {
    "buy", "get", "fix", "checked", "check", "call", "send", "book", "pay",
    "renew", "refill", "replace", "reply", "follow", "with", "about", "for",
    "the", "a", "an", "to", "of", "and", "my", "his", "her", "their", "our",
    "on", "at", "in", "from", "into", "up", "back", "out", "some", "more",
    "new", "it", "them", "him", "do", "make", "go", "take", "bring", "ask",
    "tell", "remind", "pick", "drop", "sort", "set", "schedule", "message",
    "email", "text", "order", "return", "cancel", "confirm", "prepare",
}


def _stem(w: str) -> str:
    # "Mark's" is still Mark.
    if w.endswith("'s"):
        w = w[:-2]
    return w[:5]


def grounded(text: str, transcript: str) -> bool:
    """Every content word of [text] was said (allowing one inferred word),
    so the label cannot invent a task like "Fix the leaking tap"."""
    said = {_stem(w) for w in re.findall(r"[a-z0-9']+", transcript.lower())}
    words = [w for w in re.findall(r"[a-z0-9']+", text.lower())
             if w not in _FREE and len(w) > 2]
    missing = [w for w in words if _stem(w) not in said]
    return len(missing) <= 1 and (not words or len(missing) < len(words))


# Filler that must never reach a title, a task or the note.
_FILLER = re.compile(
    r"\b(?:hey|um+|uh+|basically|you know|i mean)\b|\blike\s+(?:need|have)\b",
    re.I)


JUDGE = """You check training labels for a notes app. Given a voice memo transcript and the JSON the app should produce, answer whether the label is fully correct under these rules.

{rules}
Check especially:
1. Every task is something the speaker themself will, needs to or should do — not something someone else will do, and not invented.
2. No task the speaker said is missing, including "I should…" inside a note.
3. Each task keeps enough context to make sense alone, and nothing is listed twice.
4. kind is right: a summary, plan or reflection is a note.
5. Each "when" is the date/time phrase for that task, copied from the transcript.

Transcript: {transcript}
Label: {label}"""

JUDGE_SCHEMA = {
    "type": "object",
    "properties": {"problems": {"type": "string"}, "correct": {"type": "boolean"}},
    "required": ["problems", "correct"],
}


def judged_ok(url: str, ex: dict) -> bool:
    body = {
        "messages": [{"role": "user", "content": JUDGE.format(
            rules=RULES, transcript=ex["transcript"],
            label=json.dumps(ex["output"], ensure_ascii=False))}],
        "temperature": 0,
        "max_tokens": 300,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_schema",
                            "json_schema": {"name": "verdict", "schema": JUDGE_SCHEMA}},
    }
    req = urllib.request.Request(f"{url}/v1/chat/completions",
                                 json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        res = json.loads(urllib.request.urlopen(req, timeout=180).read())
        return bool(json.loads(res["choices"][0]["message"]["content"])["correct"])
    except Exception:
        return False


LABEL = """Label this voice memo transcript for a notes app. Think it through, then answer with only the JSON object {{"kind", "title", "tasks": [{{"text", "when"}}], "note"}}.

{rules}
Transcript: {transcript}"""


def relabel(url: str, transcript: str) -> dict | None:
    """A second, independent label with reasoning on. Examples are kept only
    when it agrees with the first, which filters out the teacher's slips."""
    body = {
        "messages": [{"role": "user", "content": LABEL.format(
            rules=RULES, transcript=transcript)}],
        "temperature": 0.6,
        "top_p": 0.95,
        "max_tokens": 3000,
        "chat_template_kwargs": {"enable_thinking": True},
    }
    req = urllib.request.Request(f"{url}/v1/chat/completions",
                                 json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        res = json.loads(urllib.request.urlopen(req, timeout=600).read())
        text = res["choices"][0]["message"]["content"]
        text = text.split("</think>")[-1]
        obj = json.loads(text[text.index("{"):text.rindex("}") + 1])
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def _task_key(text: str) -> set[str]:
    return {_stem(w) for w in re.findall(r"[a-z0-9']+", text.lower())
            if w not in _FREE and len(w) > 2}


def agree(a: dict, b: dict) -> bool:
    """Same kind, the same tasks (by their content words) and the same
    date phrases."""
    if a.get("kind") != b.get("kind"):
        return False
    ta, tb = a.get("tasks", []), b.get("tasks", [])
    if len(ta) != len(tb):
        return False
    left = list(tb)
    for t in ta:
        ka = _task_key(t.get("text", ""))
        best = None
        for u in left:
            kb = _task_key(u.get("text", ""))
            if ka and kb and len(ka & kb) / len(ka | kb) >= 0.5:
                best = u
                break
        if best is None:
            return False
        if (t.get("when") or "").strip().lower() != (best.get("when") or "").strip().lower():
            return False
        left.remove(best)
    return True


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
    for task in tasks:
        if not grounded(task.get("text", ""), t):
            return False  # an invented task
    texts = [o.get("title", ""), o.get("note", "")]
    texts += [task.get("text", "") for task in tasks]
    if any(_FILLER.search(x) for x in texts):
        return False
    # The same task twice ("Sort out the insurance", "Renew the insurance").
    keys = [frozenset(re.findall(r"[a-z]{4,}", task.get("text", "").lower()))
            - _FREE for task in tasks]
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = keys[i], keys[j]
            if a and b and len(a & b) / min(len(a), len(b)) >= 0.8:
                return False
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2500)
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default="http://127.0.0.1:8091")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--no-judge", action="store_true",
                    help="skip the second pass that checks each label")
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
        # Cheap checks first; the judge is a second model call.
        ok = bool(ex) and valid(ex) and (a.no_judge or judged_ok(a.url, ex))
        with lock:
            if ok:
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
