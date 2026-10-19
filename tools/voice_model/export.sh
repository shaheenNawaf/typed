#!/usr/bin/env bash
# Convert a trained HF model dir to GGUF and quantise it.
#   ./export.sh out/qwen3-0.6b  out/gguf/qwen3-0.6b
# Needs llama.cpp b11716 (same version the app is built with):
#   LLAMA_SRC = source checkout (for convert_hf_to_gguf.py)
#   LLAMA_BIN = folder with llama-quantize(.exe)
set -euo pipefail
src="$1"; dst="$2"
PY="${PY:-python}"
LLAMA_SRC="${LLAMA_SRC:-$HOME/ml/llama.cpp/src}"
LLAMA_BIN="${LLAMA_BIN:-$HOME/ml/llama.cpp/bin}"
mkdir -p "$(dirname "$dst")"
"$PY" "$LLAMA_SRC/convert_hf_to_gguf.py" "$src" --outtype bf16 --outfile "$dst-bf16.gguf"
for q in Q8_0 Q5_K_M Q4_K_M; do
  "$LLAMA_BIN/llama-quantize" "$dst-bf16.gguf" "$dst-$q.gguf" "$q" > /dev/null
done
ls -la "$dst"-*.gguf
