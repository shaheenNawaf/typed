"""Synthetic training data for the voice-memo shaper model.

Each example pairs a messy spoken transcript with the JSON the app wants:

    {"kind": "todo"|"note", "title": str,
     "tasks": [{"text": str, "when": str}], "note": str}

`when` is the date/time phrase exactly as spoken ("tomorrow at 3"); the app
resolves it to a real date in Dart, so the model never does calendar maths.

Memos are built from clean parts (so the target is known exactly) and then
roughened the way speech recognition output is: fillers, missing
punctuation, lowercase, repeated words, run-ons.

    python generate_data.py --n 6000 --out data/train.jsonl --seed 1
"""

from __future__ import annotations

import argparse
import json
import random
import re
from dataclasses import dataclass, field

# ── vocabulary ─────────────────────────────────────────────────────────────

PEOPLE = ["Sam", "Priya", "Marco", "Aisha", "Ben", "Leah", "Kenji", "Rosa",
          "Dan", "Mia", "Tom", "Nadia", "Carlos", "Jess", "Omar", "Ella"]
FAMILY = ["mom", "dad", "my sister", "my brother", "grandma", "my aunt"]
ITEMS = ["eggs", "bread", "milk", "coffee", "rice", "bananas", "dish soap",
         "toilet paper", "olive oil", "chicken", "cat food", "batteries",
         "light bulbs", "toothpaste", "onions", "yogurt", "pasta", "tomatoes",
         "detergent", "oat milk", "butter", "garlic", "apples", "cereal"]
PLACES = ["the bank", "the dentist", "the vet", "the landlord", "the plumber",
          "the insurance company", "the pharmacy", "the doctor's office",
          "the school", "the gym", "the airline", "the electric company"]
TOPICS = ["the venue", "the budget", "the invoice", "the contract",
          "the trip", "the deadline", "the slides", "the lease", "the quote",
          "the project plan", "the schedule", "the report", "the order"]
FIXABLES = ["the sink", "the bike", "the printer", "the leaky tap",
            "the car", "the wifi", "the washing machine", "the fence",
            "the cupboard door", "the laptop"]
BILLS = ["rent", "the electric bill", "the phone bill", "the credit card",
         "the water bill", "the internet bill", "the car insurance"]
DOCS = ["the passport", "my license", "the car registration",
        "the gym membership", "the library books", "the lease"]
WHEN = ["tomorrow", "today", "tonight", "on Friday", "on Monday",
        "next week", "this weekend", "by Thursday", "tomorrow morning",
        "tomorrow at 3", "at 5", "at noon", "on Tuesday at 10",
        "the day after tomorrow", "in two days", "next Friday",
        "this afternoon", "on the 3rd", "before Wednesday", "tonight at 8",
        "on Saturday morning", "at 9:30 am", "Sunday", "in a week"]
FILLERS = ["um", "uh", "like", "you know", "so", "okay so", "basically",
           "right", "I mean", "anyway", "oh", "hey", "hey so", "hi",
           "okay okay", "so like", "uh yeah so"]


def pick(xs):
    return random.choice(xs)


@dataclass
class Task:
    text: str               # clean, imperative, capitalised
    when: str = ""
    category: str = "misc"  # shopping | errands | work | home | people


@dataclass
class Memo:
    spoken: list[str] = field(default_factory=list)  # clean spoken clauses
    tasks: list[Task] = field(default_factory=list)
    note: list[str] = field(default_factory=list)    # clean prose sentences
    title: str = ""
    kind: str = "todo"


def cap(s: str) -> str:
    return s[:1].upper() + s[1:]


# ── task generators: (spoken phrase, Task) ──────────────────────────────────
# Spoken phrases may carry a {when} slot; the task keeps the phrase verbatim.

def t_buy():
    a, b = random.sample(ITEMS, 2)
    return pick([
        (f"buy {a}", Task(f"Buy {a}", category="shopping")),
        (f"pick up some {a}", Task(f"Pick up {a}", category="shopping")),
        (f"get {a}", Task(f"Get {a}", category="shopping")),
        (f"grab {a}", Task(f"Grab {a}", category="shopping")),
    ])


def t_call():
    p = pick(PLACES + FAMILY + PEOPLE)
    topic = pick(TOPICS + ["the appointment", "the card", "the bill", ""])
    about = f" about {topic}" if topic else ""
    verb = pick(["call", "ring", "phone"])
    return (f"{verb} {p}{about}", Task(f"Call {p}{about}", category="errands"))


def t_message():
    p = pick(PEOPLE)
    topic = pick(TOPICS)
    verb, clean = pick([("email", "Email"), ("text", "Text"),
                        ("message", "Message"), ("reply to", "Reply to"),
                        ("follow up with", "Follow up with")])
    return (f"{verb} {p} about {topic}",
            Task(f"{clean} {p} about {topic}", category="work"))


def t_pay():
    b = pick(BILLS)
    return (f"pay {b}", Task(f"Pay {b}", category="errands"))


def t_renew():
    d = pick(DOCS)
    verb = pick(["renew", "return", "sort out"])
    return (f"{verb} {d}", Task(f"{cap(verb)} {d}", category="errands"))


def t_home():
    return pick([
        (f"fix {pick(FIXABLES)}", None),
        ("water the plants", Task("Water the plants", category="home")),
        ("take the bins out", Task("Take the bins out", category="home")),
        ("do the laundry", Task("Do the laundry", category="home")),
        ("clean the bathroom", Task("Clean the bathroom", category="home")),
        ("vacuum the living room", Task("Vacuum the living room", category="home")),
        ("feed the cat", Task("Feed the cat", category="home")),
    ])


def t_work():
    topic = pick(TOPICS)
    return pick([
        (f"finish {topic}", Task(f"Finish {topic}", category="work")),
        (f"send {topic} to {pick(PEOPLE)}", None),
        (f"review {topic}", Task(f"Review {topic}", category="work")),
        (f"update {topic}", Task(f"Update {topic}", category="work")),
        (f"book a meeting with {pick(PEOPLE)}", None),
        (f"prepare {topic} for the meeting", Task(f"Prepare {topic} for the meeting", category="work")),
    ])


def _fill_none(pair):
    """Some generators return (spoken, None): the task is the spoken text."""
    spoken, task = pair
    if task is None:
        cat = "work" if any(w in spoken for w in ("send", "meeting")) else "home"
        task = Task(cap(spoken), category=cat)
    return spoken, task


EXPLICIT = [t_buy, t_call, t_message, t_pay, t_renew, t_home, t_work]
BY_CATEGORY = {
    "shopping": [t_buy],
    "work": [t_work, t_message],
    "home": [t_home],
    "errands": [t_call, t_pay, t_renew],
}

# Implicit tasks: no cue words; the model must infer the action.
def t_implicit():
    item = pick(ITEMS)
    p = pick(PEOPLE)
    f = pick(FIXABLES)
    b = pick(BILLS)
    topic = pick(TOPICS)
    place = pick(PLACES)
    options = [
        (f"we're out of {item}", Task(f"Buy {item}", category="shopping")),
        (f"we've run out of {item}", Task(f"Buy {item}", category="shopping")),
        (f"there's no {item} left", Task(f"Buy {item}", category="shopping")),
        (f"{f} is broken again", Task(f"Fix {f}", category="home")),
        (f"{f} still isn't working", Task(f"Fix {f}", category="home")),
        (f"{p}'s birthday is coming up", Task(f"Get a gift for {p}", category="people")),
        (f"I still haven't replied to {p} about {topic}", Task(f"Reply to {p} about {topic}", category="work")),
        (f"{p} is waiting on {topic}", Task(f"Send {topic} to {p}", category="work")),
        (f"{b} is due", Task(f"Pay {b}", category="errands")),
        (f"{place} never got back to me", Task(f"Follow up with {place}", category="errands")),
        (f"{place} still hasn't sorted out the card", Task(f"Call {place} about the card", category="errands")),
        (f"the plants are looking really dry", Task("Water the plants", category="home")),
        (f"the car is making that noise again", Task("Get the car checked", category="home")),
        (f"{pick(DOCS)} expires soon", None),
    ]
    who = pick(["the landlord", "the repair guy", "the technician",
                "the building admin", "a plumber"])
    options += [
        (f"{f} is broken again so I'll call {who}",
         Task(f"Call {who} about {f}", category="home")),
        (f"{f} still isn't working, I'm going to message {who} tonight",
         Task(f"Message {who} about {f}", category="home")),
    ]
    spoken, task = pick(options)
    if task is None:
        doc = spoken.replace(" expires soon", "")
        task = Task(f"Renew {doc}", category="errands")
    return spoken, task


CUES = ["I need to {}", "I have to {}", "remember to {}", "don't forget to {}",
        "I should {}", "I gotta {}", "I've got to {}", "make sure I {}",
        "I'll {}", "remind me to {}", "I want to {}", "{}", "{}", "{}"]


def spoken_task(implicit_ok=True) -> tuple[str, Task]:
    if implicit_ok and random.random() < 0.28:
        spoken, task = t_implicit()
    else:
        spoken, task = _fill_none(pick(EXPLICIT)())
        spoken = pick(CUES).format(spoken)
    if random.random() < 0.35:
        w = pick(WHEN)
        task.when = w
        spoken = f"{spoken} {w}"
    return spoken, task


# ── memo shapes ─────────────────────────────────────────────────────────────

LEADS = {
    "shopping": ["groceries", "shopping list", "for the shop", "okay groceries"],
    "work": ["work stuff", "for work", "things for the office"],
    "home": ["around the house", "house stuff", "chores"],
    "errands": ["errands", "things to sort out"],
}
CATEGORY_TITLES = {
    "shopping": ["Groceries", "Shopping list", "Shopping"],
    "work": ["Work", "Work to-dos", "For work"],
    "home": ["Chores", "Around the house", "House jobs"],
    "errands": ["Errands", "Things to sort out"],
    "people": ["People to remember", "Personal"],
}
WHEN_LEADS = ["for tomorrow", "for the weekend", "today", "this week",
              "for Monday", "tonight"]
# A date-only lead-in is kept as spoken ("For tomorrow"); the app turns it
# into an absolute title ("To-do — Tue, Oct 20") with the same Dart parser
# the rules use, so the model never writes a title that goes stale.
WHEN_TITLES = {lead: lead[:1].upper() + lead[1:] for lead in WHEN_LEADS}


def title_for_tasks(tasks: list[Task]) -> str:
    cats = {t.category for t in tasks}
    if len(cats) == 1:
        return pick(CATEGORY_TITLES.get(cats.pop(), ["To-do"]))
    if cats <= {"errands", "shopping", "home"}:
        return pick(["Errands", "To-do", "Things to do"])
    return "To-do"


def memo_list() -> Memo:
    m = Memo(kind="todo")
    n = random.choice([2, 2, 3, 3, 3, 4, 4, 5])
    cat_lead = None
    when_lead = None
    r = random.random()
    if r < 0.2:
        cat_lead = random.choice(list(LEADS))
    elif r < 0.35:
        when_lead = pick(WHEN_LEADS)

    for _ in range(n):
        if cat_lead:
            # A category lead-in only comes with tasks of that category, so
            # the title always matches what is in the list.
            spoken, task = _fill_none(pick(BY_CATEGORY[cat_lead])())
            spoken = pick(CUES).format(spoken)
            task.category = cat_lead
        else:
            spoken, task = spoken_task()
        m.spoken.append(spoken)
        m.tasks.append(task)

    # Follow-on fragment: "... bread too" is one more thing to buy. It is
    # added to the tasks after the corrections below, which index spoken
    # phrases and tasks together.
    extra_task = None
    for i, t in enumerate(m.tasks):
        if t.category == "shopping" and random.random() < 0.3 and not t.when:
            extra = pick([x for x in ITEMS if x not in t.text])
            m.spoken[i] += pick([f". oh and {extra} too", f", {extra} as well",
                                 f". {extra} too", f", also {extra}"])
            verb = t.text.split()[0]
            extra_task = (t, Task(f"{verb} {extra}", category="shopping"))
            break

    # Correction: say something wrong, then fix it.
    if random.random() < 0.25:
        i = random.randrange(len(m.tasks))
        wrong, _ = spoken_task(implicit_ok=False)
        fix = pick(["scratch that", "no wait", "actually no", "never mind that"])
        m.spoken.insert(i, f"{wrong}, {fix}")
    # Time correction on a dated task.
    elif random.random() < 0.15:
        dated = [i for i, t in enumerate(m.tasks) if t.when]
        if dated:
            i = dated[0]
            new = pick([w for w in WHEN if w != m.tasks[i].when])
            m.spoken[i] += f", actually make it {new}"
            m.tasks[i].when = new

    if extra_task:
        parent, task = extra_task
        m.tasks.insert(m.tasks.index(parent) + 1, task)

    if cat_lead:
        m.spoken.insert(0, pick(LEADS[cat_lead]))
        m.title = pick(CATEGORY_TITLES[cat_lead])
    elif when_lead:
        m.spoken.insert(0, when_lead)
        m.title = WHEN_TITLES[when_lead]
    else:
        m.title = title_for_tasks(m.tasks)

    # Occasional context sentence kept as the note.
    if random.random() < 0.2:
        ctx = pick(CONTEXT)
        m.spoken.append(ctx)
        m.note.append(cap(ctx) + ".")
    return m


CONTEXT = [
    "the shop closes early on Sundays",
    "Sam said the meeting might move",
    "the landlord is away until next week",
    "I'm out of the office on Thursday",
    "the car is still at the garage",
    "the kids have a half day on Friday",
]

NOTE_TOPICS = [
    ("the sync talk", "Sync talk takeaways", [
        "the talk today was about local-first software",
        "the main point was that sync is the hard part, not storage",
        "they used conflict-free data types to merge edits",
        ("I want to read more about how they handle deletes",
         "Read more about how they handle deletes")]),
    ("the app idea", "App idea: weekly recap", [
        "I had an idea for the app",
        "a weekly recap on Sunday evenings could show what you finished",
        "it should feel calm, not like a report card",
        "maybe one line per day and a single highlight"]),
    ("the trip", "Trip thoughts", [
        "the trip itinerary still feels too packed",
        "we could drop the museum on the second day",
        "the train is faster than flying for the last leg",
        "Rosa wants a slower morning on Saturday"]),
    ("the meeting", "Meeting notes", [
        "quick notes from the meeting",
        "the budget is approved for the next quarter",
        "Marco is taking over the vendor contract",
        "we agreed to ship the beta in two weeks"]),
    ("the book", "Notes on the book", [
        "finished the chapter on habits",
        "the idea is to make good habits obvious and easy",
        "tracking streaks helps but only if it stays small",
        "I liked the part about environment design"]),
    ("the run", "Run log", [
        "went for a run this morning",
        "did about five kilometres in thirty minutes",
        "my knee felt better than last week",
        "my knee still clicks a bit going downhill"]),
    ("the kitchen", "Kitchen renovation ideas", [
        "thinking about the kitchen again",
        "open shelves would make it feel bigger",
        "the budget is tight so maybe just paint and new handles",
        "lighting under the cabinets would help a lot"]),
    ("work", "Reflections on the week", [
        "this week felt scattered",
        "too many meetings and not enough deep work",
        "mornings were the most productive",
        ("I should block off Tuesday mornings",
         "Block off Tuesday mornings")]),
    ("the landlord", "Call with the landlord", [
        "the landlord finally called back",
        "he agreed to fix the gate next week",
        "the rent stays the same until March",
        ("I should send him photos of the water damage",
         "Send the landlord photos of the water damage")]),
    ("the garden", "Garden plan", [
        "so the plan for the garden",
        "tomatoes along the back fence",
        "herbs in the raised bed by the door",
        "the compost bin moves to the shady corner"]),
    ("the client", "Client call notes", [
        "the client call went okay",
        "they want the launch moved up a week",
        "Priya will redo the pricing page",
        ("I need to tell the team about the new date",
         "Tell the team about the new launch date")]),
    ("the podcast", "Podcast notes: sleep", [
        "listened to a podcast on sleep",
        "keep the bedroom cool and dark",
        "morning sunlight resets your body clock",
        "caffeine after two hurts deep sleep"]),
    ("the standup", "Standup notes", [
        "notes from standup",
        "Ben is blocked on the API keys",
        "Aisha shipped the login screen",
        ("I should ping IT about the keys",
         "Ping IT about the API keys")]),
    ("the house hunt", "House hunting", [
        "saw two flats today",
        "the one near the park is bright but small",
        "the bigger one needs a lot of work",
        "the agent will send the floor plans"]),
]


def memo_note() -> Memo:
    _, title, sentences = pick(NOTE_TOPICS)
    k = random.randint(2, len(sentences))
    chosen = sentences[:k]
    m = Memo(kind="note", title=title)
    m.spoken = [c[0] if isinstance(c, tuple) else c for c in chosen]
    m.note = [cap(c) + "." for c in chosen if not isinstance(c, tuple)]
    m.tasks = [Task(c[1]) for c in chosen if isinstance(c, tuple)]
    # One incidental task inside a note.
    if random.random() < 0.4:
        spoken, task = spoken_task()
        m.spoken.append(spoken)
        m.tasks.append(task)
    return m


# ── roughen: make clean clauses sound like speech recognition output ───────

JOINS = [". ", ". ", ", and then ", ", also ", " and ", ". plus ", ", after that ",
         ". oh and ", " "]


def roughen(clauses: list[str]) -> str:
    style = random.random()
    parts = []
    for i, c in enumerate(clauses):
        if random.random() < 0.25:
            c = f"{pick(FILLERS)} {c}"
        if random.random() < 0.06:  # stutter: "I need to I need to"
            w = c.split()
            if len(w) > 3:
                c = " ".join(w[:2] + w[:2] + w[2:])
        parts.append(c)
    out = parts[0]
    for p in parts[1:]:
        out += pick(JOINS) + p
    if style < 0.45:      # punctuated, sentence case
        out = ". ".join(cap(s.strip()) for s in out.split(". "))
        if not out.endswith("."):
            out += "."
    elif style < 0.8:     # all lowercase, no final punctuation
        out = out.lower().rstrip(".")
    else:                 # one long run-on
        out = out.replace(". ", " ").lower()
    # Proper names survive lowercasing on most recognisers.
    for name in PEOPLE:
        out = re.sub(rf"{name.lower()}", name, out)
    return out


def target(m: Memo) -> dict:
    return {
        "kind": m.kind,
        "title": m.title,
        "tasks": [{"text": t.text, "when": t.when} for t in m.tasks],
        "note": " ".join(m.note),
    }


def example() -> dict:
    m = memo_list() if random.random() < 0.68 else memo_note()
    return {"transcript": roughen(m.spoken),
            "output": json.dumps(target(m), ensure_ascii=False)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    random.seed(a.seed)
    with open(a.out, "w", encoding="utf-8") as f:
        for _ in range(a.n):
            f.write(json.dumps(example(), ensure_ascii=False) + "\n")
