#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-dspark}"
LLAMA_ROOT="${LLAMA_ROOT:-$HOME/src/llama-dsv4-prometheus-exact}"
MODEL_DIR="${MODEL_DIR:?set MODEL_DIR to the verified IQ2_XXS target directory}"
MODEL="${MODEL:-$MODEL_DIR/DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00001-of-00004.gguf}"
MMPROJ="${MMPROJ:-$MODEL_DIR/mmproj-DeepSeek-V4-Flash-Vision-Exp-F16.gguf}"
DRAFT="${DRAFT:-}"
PORT="${PORT:-8087}"
CTX="${CTX:-32768}"

args=(
  --model "$MODEL"
  --mmproj "$MMPROJ"
  --no-mmproj-offload
  --host 127.0.0.1
  --port "$PORT"
  --ctx-size "$CTX"
  -np 1
  -ngl 999
  -fa on
  -b 2048
  -ub 512
  --no-mmap
  --no-warmup
  --jinja
  --reasoning-preserve
  --metrics
)

case "$MODE" in
  baseline)
    ;;
  ngram)
    args+=(
      --spec-type ngram-mod
      --spec-ngram-mod-n-match 24
      --spec-ngram-mod-n-min 48
      --spec-ngram-mod-n-max 64
    )
    ;;
  dspark)
    [[ -n "$DRAFT" ]] || { printf 'DRAFT is required for MODE=dspark
' >&2; exit 2; }
    args+=(
      --spec-type draft-dspark
      --spec-draft-model "$DRAFT"
      --spec-draft-ngl all
    )
    ;;
  *)
    printf 'MODE must be baseline, ngram, or dspark
' >&2
    exit 2
    ;;
esac

exec "$LLAMA_ROOT/build-sm121/bin/llama-server" "${args[@]}"
