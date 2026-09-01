#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_ROOT="${LLAMA_ROOT:-$REPO_ROOT/runtime/llama.cpp}"
SOURCE="${DSPARK_SOURCE:-$REPO_ROOT/dspark-source}"
OUTPUT="${DSPARK_OUTPUT:-$REPO_ROOT/artifacts/DeepSeek-V4-Flash-Vision-Exp-DSpark-Native.gguf}"
VENV="${CONVERT_VENV:-$REPO_ROOT/.venv-convert}"

mkdir -p "$(dirname "$OUTPUT")"
uv venv "$VENV"
uv pip install --python "$VENV/bin/python" --index-strategy unsafe-best-match   -r "$LLAMA_ROOT/requirements/requirements-convert_hf_to_gguf.txt"
"$VENV/bin/python" "$LLAMA_ROOT/convert_hf_to_gguf.py" "$SOURCE"   --outfile "$OUTPUT"   --outtype auto   --dspark   --target-model-dir "$SOURCE"

stat -c '%s %n' "$OUTPUT"
sha256sum "$OUTPUT"
