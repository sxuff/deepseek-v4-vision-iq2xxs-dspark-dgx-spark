#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
python3 -m py_compile scripts/*.py tests/*.py
bash -n scripts/*.sh
python3 scripts/verify.py
python3 -m unittest discover -s tests -v
