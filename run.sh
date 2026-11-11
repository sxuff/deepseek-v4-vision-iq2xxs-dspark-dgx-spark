#!/usr/bin/env bash
# run.sh - one-command setup and launch for this recipe on one NVIDIA GB10.
#
#   git clone https://github.com/sxuff/deepseek-v4-vision-iq2xxs-dspark-dgx-spark && cd deepseek-v4-vision-iq2xxs-dspark-dgx-spark && ./run.sh
#
# Every pin and flag below is copied from this repo's README, manifests or
# receipts; the comment next to each value names its source. Nothing here
# tunes, "improves" or changes a measured setting.
set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"

# ===================== recipe config (per repo) =============================
RECIPE_NAME="deepseek-v4-vision-iq2xxs-dspark-dgx-spark"
PORT="${PORT:-8087}"                             # source: scripts/serve.sh:10 (PORT default 8087; serve.sh honors this env var)
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/deepseek-v4-vision-iq2xxs-dspark-dgx-spark}"
NEEDS_TOOLS="git curl sha256sum cmake python3 uv" # cmake: scripts/build_runtime.sh:26; python3: scripts/download_*.py; uv: scripts/convert_dspark.sh:11-12 - the repo does NOT pin a uv version
NEED_MEM_BYTES=0                                 # no pre-load MemAvailable requirement stated anywhere in the repo; its measured guard is a 6 GiB reserve WHILE serving (README.md:114)
ENGINE_DISK_BYTES=10896058816                    # locally generated DSpark draft GGUF, 10,896,058,816 bytes (manifests/dspark-source.json:3); llama.cpp build-tree size is not stated in the repo
ENGINE_KIND=process
CONTAINER_NAME=""
READY_URL="http://127.0.0.1:${PORT}/v1/models"   # the endpoint the repo's own harness calls first (scripts/benchmark.py:128)
READY_TIMEOUT=1200                               # not a repo-pinned value; matches the harness per-request timeout (scripts/benchmark.py:101)
EXPECTED_LINE="37.47 tok/s (aggregate whole-request completion rate, single stream; 43.01 tok/s server decode)"  # README.md:16, results/summary.json arms.dspark
RECEIPT_PATH="results/summary.json"

# Pinned locations used by the steps below.
LLAMA_SHA=9c9a1546d0159781f96e5c1c9ba479e74ecb54c4          # runtime-manifest.json:17, scripts/build_runtime.sh:8 (tarruda/llama.cpp)
LLAMA_SRC="$SRC_DIR/llama-dsv4-prometheus-exact"            # scripts/serve.sh:5 default LLAMA_ROOT. NOTE: scripts/build_runtime.sh:5 defaults to ./runtime/llama.cpp instead, so this script passes SOURCE_DIR/LLAMA_ROOT explicitly everywhere to reconcile the two defaults.
TARGET_DIR="$MODELS_DIR/DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS"   # scripts/download_target.py:17 default destination
DSPARK_SRC_DIR="$MODELS_DIR/DeepSeek-V4-Flash-Vision-Exp-dspark-source"    # passed to scripts/download_dspark_source.py --destination (its default is ./dspark-source, scripts/download_dspark_source.py:16)
DRAFT="$MODELS_DIR/DeepSeek-V4-Flash-Vision-Exp-DSpark-Native.gguf"        # output filename from scripts/convert_dspark.sh:7
DRAFT_SHA=4bd6ec83b6b31531a55459ee07b7eaede380ccd6a60cbe13003ec7ccf1eb2d77 # manifests/dspark-source.json:4 (generated_gguf_sha256)
DRAFT_BYTES=10896058816                                                    # manifests/dspark-source.json:3 (generated_gguf_bytes)

# These lines feed the shared disk estimate only; download + SHA-256 verification
# is done by the repo's own pinned downloaders in weights_step below.
# Sources: manifests/target.json (5 files) and manifests/dspark-source.json /
# scripts/download_dspark_source.py:19-21 (3 source shards).
# One line per file:  <sha256> <bytes> <hf_repo> <revision> <path-in-repo> <dest-relative-to-MODELS_DIR>
WEIGHTS="
fb9ca39b780779d0edda3a68595860abe839ea6d5713df674a53b273ca1efc63 26774220480 prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF 7ef3f44de46f7ab004257c0187e63b3b199e14e6 DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00001-of-00004.gguf DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS/DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00001-of-00004.gguf
3c329cb41e50b979043d3873991bd35b60d05a795aebb06e7dbeff66d7fbf94c 24813505792 prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF 7ef3f44de46f7ab004257c0187e63b3b199e14e6 DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00002-of-00004.gguf DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS/DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00002-of-00004.gguf
802c5d1e0792aa7b411c66957ccf858190e5ade9221ffb79a85b340b02f5f7f2 26759662848 prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF 7ef3f44de46f7ab004257c0187e63b3b199e14e6 DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00003-of-00004.gguf DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS/DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00003-of-00004.gguf
20755d0e82d931f35c4cde3ef345fb5c612075102986ad0b8cfb000e0cfbf503 6305174400 prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF 7ef3f44de46f7ab004257c0187e63b3b199e14e6 DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00004-of-00004.gguf DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS/DeepSeek-V4-Flash-Vision-Exp-IQ2_XXS-00004-of-00004.gguf
9d57b9bfd58c478c762045e5bf501fe3b9983bfa959921c7f2a6b1eccbeea49d 933258368 prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF 7ef3f44de46f7ab004257c0187e63b3b199e14e6 mmproj-DeepSeek-V4-Flash-Vision-Exp-F16.gguf DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS/mmproj-DeepSeek-V4-Flash-Vision-Exp-F16.gguf
5259a8a51aad179d734aac1861f70a56fdbcf73f8a68a3362e6d25a875ce1b4e 3610456288 deepseek-ai/DeepSeek-V4-Flash-Vision-Exp 6821d6ad3681a4b137b066b76094fa82ebd0a380 model-00046-of-00048.safetensors DeepSeek-V4-Flash-Vision-Exp-dspark-source/model-00046-of-00048.safetensors
7954737da5507ebe0f4161e13ec8e6ba0afe72fea454fd84273c1b30c9bf71a6 3560113064 deepseek-ai/DeepSeek-V4-Flash-Vision-Exp 6821d6ad3681a4b137b066b76094fa82ebd0a380 model-00047-of-00048.safetensors DeepSeek-V4-Flash-Vision-Exp-dspark-source/model-00047-of-00048.safetensors
0de99b7dd23d964b0a631e9e6f14ea1751db6d14bf0f009c6a83b725ca5f909e 3692776348 deepseek-ai/DeepSeek-V4-Flash-Vision-Exp 6821d6ad3681a4b137b066b76094fa82ebd0a380 model-00048-of-00048.safetensors DeepSeek-V4-Flash-Vision-Exp-dspark-source/model-00048-of-00048.safetensors
"

weights_step() {  # the repo's own pinned, resuming, SHA-256-verifying downloaders, then the draft conversion (README.md:51-68)
  if [ "$CHECK" = 1 ]; then
    plan "download+verify the IQ2_XXS target shards and F16 mmproj with scripts/download_target.py (pins: manifests/target.json)"
    plan "download+verify the 3 official DSpark source shards with scripts/download_dspark_source.py (pins: scripts/download_dspark_source.py:13-22)"
    plan "generate the native DSpark draft GGUF with scripts/convert_dspark.sh and verify sha256 ${DRAFT_SHA:0:12}... (manifests/dspark-source.json:4)"
    return
  fi
  python3 scripts/download_target.py --destination "$TARGET_DIR"
  python3 scripts/download_dspark_source.py --destination "$DSPARK_SRC_DIR"
  local mark="$DRAFT.sha256-ok"
  if [ -f "$mark" ] && [ "$(cat "$mark")" = "$DRAFT_SHA $DRAFT_BYTES" ] \
     && [ "$(stat -c %s "$DRAFT" 2>/dev/null)" = "$DRAFT_BYTES" ]; then
    ok "draft generated and verified earlier: $DRAFT"; return
  fi
  if [ "$(stat -c %s "$DRAFT" 2>/dev/null || echo 0)" != "$DRAFT_BYTES" ]; then
    # Conversion command and flags are the repo's own (scripts/convert_dspark.sh:11-13); needs uv, whose version the repo does not pin.
    LLAMA_ROOT="$LLAMA_SRC" DSPARK_SOURCE="$DSPARK_SRC_DIR" DSPARK_OUTPUT="$DRAFT" ./scripts/convert_dspark.sh
  fi
  local got; got="$(sha256sum "$DRAFT" | cut -d' ' -f1)"
  [ "$got" = "$DRAFT_SHA" ] || die "generated draft SHA-256 mismatch: expected $DRAFT_SHA, got $got (manifests/dspark-source.json:4)"
  [ "$(stat -c %s "$DRAFT")" = "$DRAFT_BYTES" ] || die "generated draft size mismatch (manifests/dspark-source.json:3)"
  echo "$DRAFT_SHA $DRAFT_BYTES" > "$mark"
  ok "sha256 ok: $(basename "$DRAFT")"
}

engine_step() {   # tarruda/llama.cpp @ 9c9a1546 + exercised routing patch, CUDA arch 121a-real (runtime-manifest.json, scripts/build_runtime.sh:7-27)
  if [ -x "$LLAMA_SRC/build-sm121/bin/llama-server" ]; then ok "llama-server already built: $LLAMA_SRC/build-sm121"; return; fi
  if [ "$CHECK" = 1 ]; then plan "clone, patch and build tarruda/llama.cpp@${LLAMA_SHA:0:12} with scripts/build_runtime.sh (pin, patch and cmake flags live there)"; return; fi
  SOURCE_DIR="$LLAMA_SRC" BUILD_DIR="$LLAMA_SRC/build-sm121" ./scripts/build_runtime.sh
}

serve_step() {    # the measured DSpark profile (README.md:81-84); every server flag lives in scripts/serve.sh:13-50 (ctx 32768, 1 slot, host 127.0.0.1)
  if [ "$CHECK" = 1 ]; then plan "start scripts/serve.sh MODE=dspark (llama-server on 127.0.0.1:${PORT})"; return; fi
  MODE=dspark LLAMA_ROOT="$LLAMA_SRC" MODEL_DIR="$TARGET_DIR" DRAFT="$DRAFT" PORT="$PORT" \
    nohup ./scripts/serve.sh >"$LOGFILE" 2>&1 &
  echo $! >"$PIDFILE"
}

curl_test() {     # no "model" field: the server hosts one model and the repo's harness discovers the id from /v1/models (scripts/benchmark.py:128-129); temperature 0 per the measured design (results/summary.json design)
  cat <<EOF
curl -s http://127.0.0.1:${PORT}/v1/chat/completions -H 'Content-Type: application/json' \\
  -d '{"messages":[{"role":"user","content":"What is 17*23?"}],"max_tokens":256,"temperature":0}'
EOF
}
# ===================== end of recipe config =================================

# ---------------------------------------------------------------------------
# Shared machinery (identical in every sxuff recipe repo).
# ---------------------------------------------------------------------------
CHECK=0; ACTION=run
usage() {
  cat <<EOF
Usage: ./run.sh [--check] [--stop] [--help]

Sets up and launches ${RECIPE_NAME} on one NVIDIA GB10 (SM121).

  (no flag)  check the machine, build or pull the pinned engine, download the
             pinned weights, verify SHA-256, start the server, print a test.
             Safe to re-run: finished steps are skipped.
  --check    print what would happen; change nothing.
  --stop     stop the server this script started.
  --help     show this text.

Environment:
  HF_TOKEN     Hugging Face token, read from the environment only, never saved.
  MODELS_DIR   weights        (default: ${MODELS_DIR})
  SRC_DIR      engine source  (default: ${SRC_DIR})
  STATE_DIR    pid and log    (default: ${STATE_DIR})
  PORT         server port    (default: ${PORT})

Expected: ${EXPECTED_LINE}
Receipt:  ${RECEIPT_PATH}
EOF
}
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --stop)  ACTION=stop ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $a (see ./run.sh --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok    %s\n' "$*"; }
plan() { printf '    would %s\n' "$*"; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }
CHECK_FAILED=0   # under --check, a failed pre-flight check is reported and the plan continues
fail() { if [ "$CHECK" = 1 ]; then printf '    FAIL  %s\n' "$*"; CHECK_FAILED=1; else die "$*"; fi; }
human(){ numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 B"; }
doit() { if [ "$CHECK" = 1 ]; then plan "$*"; else "$@"; fi; }   # mutate, or describe under --check

PIDFILE="${STATE_DIR}/server.pid"
LOGFILE="${STATE_DIR}/server.log"
STOP_CMD="cd ${REPO_DIR} && ./run.sh --stop"

server_running() {
  if [ "$ENGINE_KIND" = docker ]; then
    [ -n "$(docker ps -q --filter "name=^${CONTAINER_NAME}\$" 2>/dev/null)" ]
  else
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
  fi
}

stop_step() {   # may be overridden in the config block (e.g. to call scripts/stop.sh)
  if ! server_running; then ok "nothing started by this script is running"; return; fi
  if [ "$ENGINE_KIND" = docker ]; then doit docker stop "$CONTAINER_NAME"
  else
    local pid; pid="$(cat "$PIDFILE")"; doit kill "$pid"
    if [ "$CHECK" = 0 ]; then
      for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid"; rm -f "$PIDFILE"
    fi
  fi
  ok "stopped"
}
declare -f stop_override >/dev/null && stop_step() { stop_override; }

if [ "$ACTION" = stop ]; then say "Stopping ${RECIPE_NAME}"; stop_step; exit 0; fi
[ "$CHECK" = 1 ] && say "--check: nothing will be changed"

# git checkout of an exact commit, idempotent. Usage: git_pin <url> <sha> <dir>
git_pin() {
  local url="$1" sha="$2" dir="$3"
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]; then ok "source at ${sha:0:12}: $dir"; return; fi
  if [ ! -d "$dir/.git" ]; then doit git clone --quiet "$url" "$dir"; fi
  if [ "$CHECK" = 1 ]; then plan "check out $sha in $dir"; return; fi
  [ -z "$(git -C "$dir" status --porcelain)" ] || die "$dir has local changes; refusing to move it to $sha"
  git -C "$dir" fetch --quiet origin "$sha" 2>/dev/null || git -C "$dir" fetch --quiet origin
  git -C "$dir" checkout --quiet --detach "$sha"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || die "could not check out $sha in $dir"
  ok "source at ${sha:0:12}: $dir"
}

# docker image by digest, idempotent. Usage: image_pin <repo@sha256:...>
image_pin() {
  if docker image inspect "$1" >/dev/null 2>&1; then ok "image present: $1"; else doit docker pull "$1"; fi
}

# --- 1. machine ------------------------------------------------------------
say "Machine"
[ "$(uname -m)" = aarch64 ] || die "expected aarch64 (GB10), got $(uname -m)"
command -v nvidia-smi >/dev/null || die "nvidia-smi not found"
GPU="$(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader | head -1)"
case "$GPU" in *GB10*", 12.1") ok "GPU: $GPU" ;; *) die "measured on an NVIDIA GB10 (SM121); found: ${GPU:-none}" ;; esac
MISSING=""; for t in $NEEDS_TOOLS; do command -v "$t" >/dev/null || MISSING="$MISSING $t"; done
if [ -n "$MISSING" ]; then fail "missing tool(s):$MISSING"; else ok "tools: $NEEDS_TOOLS"; fi
ALREADY=0; server_running && ALREADY=1
MEM_AVAIL=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) * 1024 ))
if [ "$ALREADY" = 1 ]; then ok "server already running; memory check skipped"
elif [ "$MEM_AVAIL" -lt "$NEED_MEM_BYTES" ]; then
  fail "need $(human "$NEED_MEM_BYTES") available memory, have $(human "$MEM_AVAIL"). Stop other models first (nvidia-smi, docker ps)."
else ok "memory: $(human "$MEM_AVAIL") available, need $(human "$NEED_MEM_BYTES")"; fi
if [ "$ALREADY" = 1 ]; then ok "port ${PORT}: served by this recipe"
else
  # The server binds 127.0.0.1 (or the host network). A listener on 127.0.0.1, a wildcard or ::1
  # blocks it; one bound to another interface address does not, and is only reported.
  PORT_ALL="$(ss -ltnH "sport = :${PORT}" 2>/dev/null || true)"
  PORT_CLASH="$(printf '%s\n' "$PORT_ALL" | awk '{print $4}' | grep -E '^(127\.0\.0\.1|0\.0\.0\.0|\*|\[::\]|\[::1\]|\[::ffff:127\.0\.0\.1\]):' || true)"
  PORT_DOCKER="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E "(127\.0\.0\.1|0\.0\.0\.0|\[::\]|:::?):${PORT}->" || true)"
  if [ -n "$PORT_CLASH$PORT_DOCKER" ]; then
    printf '    port %s is taken:\n%s\n%s\n' "$PORT" "$PORT_CLASH" "$PORT_DOCKER"
    fail "free port ${PORT} or run: PORT=<other> ./run.sh"
  elif [ -n "$PORT_ALL" ]; then
    ok "port ${PORT}: free on 127.0.0.1 (also bound elsewhere: $(printf '%s' "$PORT_ALL" | awk '{print $4}' | tr '\n' ' '))"
  else ok "port ${PORT}: free"; fi
fi

# --- 2. disk ---------------------------------------------------------------
say "Disk"
nearest_dir() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; echo "$d"; }
NEED_DISK=$ENGINE_DISK_BYTES
while read -r sha size repo rev rpath dest; do
  [ -z "${sha:-}" ] && continue
  have=0; [ -f "$MODELS_DIR/$dest" ] && have=$(stat -c %s "$MODELS_DIR/$dest")
  [ "$have" -lt "$size" ] && NEED_DISK=$(( NEED_DISK + size - have ))
done <<< "$WEIGHTS"
FREE_DISK=$(df -B1 --output=avail "$(nearest_dir "$MODELS_DIR")" | tail -1 | tr -d ' ')
if [ "$FREE_DISK" -ge "$NEED_DISK" ]; then ok "need $(human "$NEED_DISK") more, have $(human "$FREE_DISK")"
else fail "need $(human "$NEED_DISK") more disk under $MODELS_DIR, have $(human "$FREE_DISK"). Nothing was deleted."; fi

# --- 3. engine -------------------------------------------------------------
say "Engine"
engine_step

# --- 4. weights: pinned revision + SHA-256 -----------------------------------
hf_fetch() {   # repo rev path dest. The token reaches curl on stdin: never in argv or a file.
  { [ -n "${HF_TOKEN:-}" ] && printf 'header = "Authorization: Bearer %s"\n' "$HF_TOKEN"; true; } |
    curl --fail --location --retry 5 --retry-delay 5 --continue-at - --config - \
         --output "$4.part" "https://huggingface.co/$1/resolve/$2/$3"
  mv "$4.part" "$4"
}
default_weights_step() {
  while read -r sha size repo rev rpath dest; do
    [ -z "${sha:-}" ] && continue
    local f="$MODELS_DIR/$dest" mark="$MODELS_DIR/$dest.sha256-ok"
    if [ -f "$mark" ] && [ "$(cat "$mark")" = "$sha $size" ] && [ "$(stat -c %s "$f" 2>/dev/null)" = "$size" ]; then
      ok "verified earlier: $dest"; continue
    fi
    if [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" != "$size" ]; then
      if [ "$CHECK" = 1 ]; then plan "download $repo@${rev:0:12} $rpath ($(human "$size"))"; continue; fi
      mkdir -p "$(dirname "$f")"; printf '    get   %s (%s)\n' "$rpath" "$(human "$size")"
      hf_fetch "$repo" "$rev" "$rpath" "$f"
    elif [ "$CHECK" = 1 ]; then plan "verify SHA-256 of $dest"; continue; fi
    local got; got="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ "$got" != "$sha" ]; then mv "$f" "$f.sha256-mismatch"; die "SHA-256 mismatch for $dest: expected $sha, got $got (kept as $f.sha256-mismatch)"; fi
    echo "$sha $size" > "$mark"; ok "sha256 ok: $dest"
  done <<< "$WEIGHTS"
}
declare -f weights_step >/dev/null || weights_step() { default_weights_step; }
say "Weights"
weights_step

# --- 5. serve --------------------------------------------------------------
say "Server"
if [ "$ALREADY" = 1 ]; then ok "already running"
elif [ "$CHECK" = 1 ]; then serve_step
else
  mkdir -p "$STATE_DIR"; serve_step
  printf '    wait  for %s (up to %ss; log: %s)\n' "$READY_URL" "$READY_TIMEOUT" "$LOGFILE"
  t=0
  until curl -fsS -o /dev/null "$READY_URL" 2>/dev/null; do
    server_running || die "server exited during start-up; see $LOGFILE"
    [ "$t" -ge "$READY_TIMEOUT" ] && die "not ready after ${READY_TIMEOUT}s; see $LOGFILE"
    sleep 5; t=$((t + 5))
  done
  ok "ready after ${t}s"
fi

# --- 6. done ---------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  if [ "$CHECK_FAILED" = 1 ]; then say "Check finished with FAIL lines above; nothing was changed. ./run.sh would stop at the first one."; exit 1; fi
  say "Check finished; nothing was changed. Run ./run.sh to do it."; exit 0
fi
say "Test it"
curl_test
say "Stop it"
echo "$STOP_CMD"
echo
echo "Expected: ${EXPECTED_LINE} - receipt: ${RECEIPT_PATH}"
