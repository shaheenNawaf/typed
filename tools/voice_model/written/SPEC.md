# Written training memos (v2)

Hand-labelled voice-memo examples for the shaper model: a realistic
transcript, as a speech recogniser would output it, and the exact JSON the
app should produce. They replace the local 8B teacher, whose labels invented
and dropped tasks too often to train on.

Never copy, paraphrase or read `eval_memos.jsonl` or `eval_holdout.jsonl`;
they are the test sets.

## Format

One JSON object per line:

```
{"transcript": "...", "label": {"kind": "todo"|"note", "title": "...",
  "tasks": [{"text": "...", "when": "..."}], "note": "..."}}
```

Check a file with `python check_written.py written/<file>.jsonl`; every line
must pass.

## Labelling rules

**kind**: `"todo"` if the memo is mainly things to do; `"note"` if it is
mainly thoughts, a summary of a call or meeting, a plan being described, an
idea or a reflection, even if it contains a task or two.

**title**: 2 to 5 words, a natural name ("Weekend errands", "Notes from the
supplier call", "Groceries", "Garden plan"). If the memo opens with a
date-only lead-in such as "for tomorrow" or "this weekend", the title is
that phrase verbatim with a capital letter ("For tomorrow").

**tasks**: what the *speaker* says they will do, need to do or should do,
as a short imperative that starts with a verb, in sentence case ("Buy milk",
"Call the vet about Luna's booster shot").

- Never invent a task. What other people will do ("Priya will redo the
  page", "the landlord agreed to fix the gate") is not the speaker's task.
- Infer an action only when the speaker states a problem or a need and says
  nothing about what they will do about it: "we're out of rice" → "Buy
  rice"; "the water heater is clicking" → "Get the water heater checked".
  If they do say what they will do ("the tap is dripping, I'll chase the
  landlord"), only that is a task.
- "I should…", "I need to…", "I'll…" inside a note is still a task.
- Keep who, what and where so the task makes sense alone a week later:
  "Send Bea the slides", not "Send them"; "Get to Sofia's recital", not
  "Get there". Keep quantities: "Buy five kilos of rice".
- One task per thing. Each item of a list and each afterthought is its own
  task ("buy eggs… oh and bread" → "Buy eggs", "Buy bread"). The same task
  said twice is listed once ("sort out the car insurance… it needs
  renewing" → one task).
- A plan with a time is a task even without a verb ("lunch with Grace on
  Thursday at 12" → "Lunch with Grace").
- Corrections ("scratch that", "no wait", "actually make it…") are applied:
  drop what was cancelled, keep the replacement.
- No date or time inside the task text.
- No filler anywhere in the label: no "um", "like", "basically", "hey".

**when**: the date/time phrase for that task copied *exactly* as it appears
in the transcript, including its preposition ("tomorrow at 3", "by
Friday", "on the 30th", "before end of day", "tonight"), or `""`. A
lead-in date ("for tomorrow, …") goes into the tasks only when the memo
clearly means all of them. A date that belongs to something else is not
the task's `when` ("move my checkup from Tuesday to Thursday" → when `""`).

**note**: for a note, its content as clean sentences (filler removed,
punctuation fixed, corrections applied) without the task sentences; for a
to-do list, any sentence of context that is not a task, else `""`.

## Transcripts

Realistic speech-to-text: about a third all lowercase with no punctuation,
some long run-ons, the rest punctuated. Mix in fillers (um, uh, like as a
tic, basically, you know, I mean), greetings ("hey", "hey so", "okay okay
so"), stutters ("I need to I need to"), corrections and afterthoughts.
Lengths from a few words to about 80 words. English only. No money logging
("spent 250 on lunch") and no app commands ("new task", "title is"): the
app handles those without the model.
