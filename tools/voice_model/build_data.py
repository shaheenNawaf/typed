"""Assembles the v2 training set.

Template memos (generate_data.py) teach the JSON shape and date phrases;
the hand-labelled memos in written/ teach judgement (what is and isn't a
task, notes vs lists, context). Written memos are fewer and better, so
they are repeated; a slice of them is held back for validation.

    python generate_data.py --n 4000 --out data/template.jsonl --seed 2
    python build_data.py --template data/template.jsonl --repeat 3 \
        --train data/train_v2.jsonl --val data/val_v2.jsonl
"""

from __future__ import annotations

import argparse
import glob
import json
import random

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--written", default="written/*.jsonl")
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--val-share", type=float, default=0.06)
    ap.add_argument("--train", required=True)
    ap.add_argument("--val", required=True)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    random.seed(a.seed)

    written = []
    for path in sorted(glob.glob(a.written)):
        for line in open(path, encoding="utf-8"):
            if line.strip():
                row = json.loads(line)
                written.append({"transcript": row["transcript"],
                                "output": json.dumps(row["label"], ensure_ascii=False)})
    random.shuffle(written)
    n_val = max(1, int(len(written) * a.val_share))
    val, keep = written[:n_val], written[n_val:]

    template = [json.loads(l) for l in open(a.template, encoding="utf-8") if l.strip()]
    train = template + keep * a.repeat
    random.shuffle(train)

    with open(a.train, "w", encoding="utf-8") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in train)
    with open(a.val, "w", encoding="utf-8") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in val)
    print(f"train {len(train)} ({len(template)} template + {len(keep)}x{a.repeat} written), val {len(val)}")
