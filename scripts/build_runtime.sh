#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$REPO_ROOT/runtime/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build-sm121}"
RUNTIME_REPO="https://github.com/tarruda/llama.cpp.git"
RUNTIME_REV="9c9a1546d0159781f96e5c1c9ba479e74ecb54c4"
PATCH="$REPO_ROOT/patches/dsv4-vision-routing.patch"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE_DIR")"
  git clone --filter=blob:none --no-checkout "$RUNTIME_REPO" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --no-tags origin "$RUNTIME_REV"
test "$(git -C "$SOURCE_DIR" rev-parse FETCH_HEAD)" = "$RUNTIME_REV"
git -C "$SOURCE_DIR" checkout --detach "$RUNTIME_REV"
git -C "$SOURCE_DIR" reset --hard "$RUNTIME_REV"
git -C "$SOURCE_DIR" clean -ffd
git -C "$SOURCE_DIR" apply --check "$PATCH"
git -C "$SOURCE_DIR" apply "$PATCH"
git -C "$SOURCE_DIR" diff --check

export CUDACXX="${CUDACXX:-/usr/local/cuda/bin/nvcc}"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR"   -DCMAKE_BUILD_TYPE=Release   -DGGML_CUDA=ON   -DCMAKE_CUDA_COMPILER="$CUDACXX"   -DCMAKE_CUDA_ARCHITECTURES=121a-real
cmake --build "$BUILD_DIR" --target llama-server llama-quantize -j"${JOBS:-8}"
"$BUILD_DIR/bin/llama-server" --version
