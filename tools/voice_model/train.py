"""Fine-tune a small causal LM on transcript → JSON pairs.

Full fine-tune (models here are <1B, which fits a 16 GB GPU), loss on the
completion only.

    python train.py --base Qwen/Qwen3-0.6B --train data/train.jsonl \
        --val data/val.jsonl --out out/qwen3-0.6b
"""

from __future__ import annotations

import argparse
import json

import torch
from datasets import Dataset
from transformers import AutoModelForCausalLM, AutoTokenizer
from trl import SFTConfig, SFTTrainer

from common import END, prompt


def load(path: str) -> Dataset:
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    return Dataset.from_list([
        {"prompt": prompt(r["transcript"]), "completion": r["output"] + END}
        for r in rows
    ])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--train", required=True, nargs="+")
    ap.add_argument("--val", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=float, default=3)
    ap.add_argument("--lr", type=float, default=5e-5)
    ap.add_argument("--batch", type=int, default=16)
    a = ap.parse_args()

    tok = AutoTokenizer.from_pretrained(a.base)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(a.base,
                                                 dtype=torch.bfloat16)

    from datasets import concatenate_datasets
    train = concatenate_datasets([load(p) for p in a.train]).shuffle(seed=0)
    val = load(a.val)

    cfg = SFTConfig(
        output_dir=a.out,
        num_train_epochs=a.epochs,
        learning_rate=a.lr,
        lr_scheduler_type="cosine",
        warmup_steps=50,
        per_device_train_batch_size=a.batch,
        per_device_eval_batch_size=a.batch,
        gradient_accumulation_steps=1,
        bf16=True,
        logging_steps=25,
        eval_strategy="epoch",
        save_strategy="no",
        max_length=512,
        completion_only_loss=True,
        report_to=[],
        dataloader_num_workers=0,
    )
    trainer = SFTTrainer(model=model, args=cfg, train_dataset=train,
                         eval_dataset=val, processing_class=tok)
    trainer.train()
    trainer.save_model(a.out)
    tok.save_pretrained(a.out)
    print("saved", a.out)
