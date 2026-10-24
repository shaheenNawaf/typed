"""Score a shaper on the hand-written test memos (eval_memos.jsonl).

    python eval.py --preds data/rules_preds.jsonl          # precomputed
    python eval.py --model out/qwen3-0.6b                  # HF model dir
    python eval.py --server http://127.0.0.1:8080 --save data/model_preds.jsonl
    python eval.py --set eval_holdout.jsonl ...            # held-out set
"""

from __future__ import annotations

import argparse
import json
import time

from common import END, GRAMMAR, parse, prompt, score, summarize

# eval_memos.jsonl is the development set (looked at while tuning);
# eval_holdout.jsonl was written before v2 tuning and is only reported on.
MEMOS: list[dict] = []


def load(path: str) -> list[dict]:
    return [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]


def run_hf(model_dir: str, show: bool) -> list[dict]:
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_dir)
    model = AutoModelForCausalLM.from_pretrained(
        model_dir, dtype=torch.bfloat16).to("cuda").eval()
    preds = []
    for m in MEMOS:
        ids = tok(prompt(m["transcript"]), return_tensors="pt").to("cuda")
        with torch.no_grad():
            out = model.generate(**ids, max_new_tokens=320, do_sample=False,
                                 eos_token_id=tok.convert_tokens_to_ids(END))
        text = tok.decode(out[0][ids["input_ids"].shape[1]:],
                          skip_special_tokens=False)
        text = text.split(END)[0]
        if show:
            print(m["transcript"][:70], "\n  ->", text, "\n")
        preds.append(parse(text))
    return preds


def run_server(url: str, show: bool, save: str | None = None) -> list[dict]:
    import urllib.request
    preds, raws, t0 = [], [], time.time()
    for m in MEMOS:
        body = json.dumps({"prompt": prompt(m["transcript"]), "n_predict": 320,
                           "temperature": 0, "stop": [END],
                           "grammar": GRAMMAR}).encode()
        req = urllib.request.Request(f"{url}/completion", body,
                                     {"Content-Type": "application/json"})
        text = json.loads(urllib.request.urlopen(req).read())["content"]
        if show:
            print(m["transcript"][:70], "\n  ->", text, "\n")
        raws.append(text.strip())
        preds.append(parse(text))
    if save:
        # One raw answer per line, for the app-pipeline export
        # (rules_baseline_test.dart).
        with open(save, "w", encoding="utf-8") as f:
            f.writelines(r + "\n" for r in raws)
    print(f"{(time.time() - t0) / len(MEMOS):.2f}s per memo")
    return preds


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preds")
    ap.add_argument("--model")
    ap.add_argument("--server")
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--set", default="eval_memos.jsonl")
    ap.add_argument("--save")
    a = ap.parse_args()
    MEMOS.extend(load(a.set))
    if a.preds:
        preds = [parse(l) for l in open(a.preds, encoding="utf-8")]
    elif a.model:
        preds = run_hf(a.model, a.show)
    else:
        preds = run_server(a.server, a.show, a.save)
    rows = [score(p, m["expect"]) for p, m in zip(preds, MEMOS)]
    print(json.dumps(summarize(rows)))
