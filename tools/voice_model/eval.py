"""Score a shaper on the hand-written test memos (eval_memos.jsonl).

    python eval.py --preds data/rules_preds.jsonl          # precomputed
    python eval.py --model out/qwen3-0.6b                  # HF model dir
    python eval.py --gguf out/model.gguf --server http://127.0.0.1:8080
"""

from __future__ import annotations

import argparse
import json
import time

from common import END, GRAMMAR, parse, prompt, score, summarize

MEMOS = [json.loads(l) for l in open("eval_memos.jsonl", encoding="utf-8")
         if l.strip()]


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


def run_server(url: str, show: bool) -> list[dict]:
    import urllib.request
    preds, t0 = [], time.time()
    for m in MEMOS:
        body = json.dumps({"prompt": prompt(m["transcript"]), "n_predict": 320,
                           "temperature": 0, "stop": [END],
                           "grammar": GRAMMAR}).encode()
        req = urllib.request.Request(f"{url}/completion", body,
                                     {"Content-Type": "application/json"})
        text = json.loads(urllib.request.urlopen(req).read())["content"]
        if show:
            print(m["transcript"][:70], "\n  ->", text, "\n")
        preds.append(parse(text))
    print(f"{(time.time() - t0) / len(MEMOS):.2f}s per memo")
    return preds


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preds")
    ap.add_argument("--model")
    ap.add_argument("--server")
    ap.add_argument("--show", action="store_true")
    a = ap.parse_args()
    if a.preds:
        preds = [parse(l) for l in open(a.preds, encoding="utf-8")]
    elif a.model:
        preds = run_hf(a.model, a.show)
    else:
        preds = run_server(a.server, a.show)
    rows = [score(p, m["expect"]) for p, m in zip(preds, MEMOS)]
    print(json.dumps(summarize(rows)))
