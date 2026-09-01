#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import time
import urllib.request
from pathlib import Path

REPO = "deepseek-ai/DeepSeek-V4-Flash-Vision-Exp"
REVISION = "6821d6ad3681a4b137b066b76094fa82ebd0a380"
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "dspark-source"
CHUNK = 16 * 1024 * 1024
WEIGHTS = [
    {"path": "model-00046-of-00048.safetensors", "bytes": 3610456288, "sha256": "5259a8a51aad179d734aac1861f70a56fdbcf73f8a68a3362e6d25a875ce1b4e"},
    {"path": "model-00047-of-00048.safetensors", "bytes": 3560113064, "sha256": "7954737da5507ebe0f4161e13ec8e6ba0afe72fea454fd84273c1b30c9bf71a6"},
    {"path": "model-00048-of-00048.safetensors", "bytes": 3692776348, "sha256": "0de99b7dd23d964b0a631e9e6f14ea1751db6d14bf0f009c6a83b725ca5f909e"},
]
SMALL = ["config.json", "generation_config.json", "tokenizer.json", "tokenizer_config.json", "LICENSE", "README.md", "model.safetensors.index.full.json"]
BASE = f"https://huggingface.co/{REPO}/resolve/{REVISION}"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(CHUNK):
            digest.update(block)
    return digest.hexdigest()


def retrieve(url: str, dest: Path, expected_size: int | None = None) -> None:
    part = dest.with_suffix(dest.suffix + ".part")
    offset = part.stat().st_size if part.exists() else 0
    headers = {"User-Agent": "Hermes-Pinned-DSpark-Extractor/1.0"}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=180) as response:
        if offset and response.status != 206:
            part.unlink(missing_ok=True)
            return retrieve(url, dest, expected_size)
        with part.open("ab" if offset else "wb") as output:
            while block := response.read(CHUNK):
                output.write(block)
    if expected_size is not None and part.stat().st_size != expected_size:
        raise RuntimeError(f"size mismatch for {dest.name}: {part.stat().st_size} != {expected_size}")
    os.replace(part, dest)


def weight(item: dict) -> dict:
    path = DEST / item["path"]
    if not path.exists() or path.stat().st_size != item["bytes"] or sha256_file(path) != item["sha256"]:
        path.unlink(missing_ok=True)
        retrieve(f"{BASE}/{item['path']}", path, item["bytes"])
    actual = sha256_file(path)
    if actual != item["sha256"]:
        raise RuntimeError(f"sha256 mismatch for {item['path']}: {actual}")
    return {**item, "verified": True}


def main() -> int:
    global DEST
    parser = argparse.ArgumentParser(description="Download and verify the three official DSpark source shards")
    parser.add_argument("--destination", type=Path, default=DEST)
    args = parser.parse_args()
    DEST = args.destination.expanduser()
    started = time.time()
    DEST.mkdir(parents=True, exist_ok=True)
    small_paths = []
    for name in SMALL:
        remote = "model.safetensors.index.json" if name.endswith(".full.json") else name
        path = DEST / name
        retrieve(f"{BASE}/{remote}", path)
        small_paths.append({"path": name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        rows = list(pool.map(weight, WEIGHTS))

    full = json.loads((DEST / "model.safetensors.index.full.json").read_text())
    mtp_map = {name: shard for name, shard in full["weight_map"].items() if name.startswith("mtp.")}
    shards = sorted(set(mtp_map.values()))
    expected_shards = sorted(item["path"] for item in WEIGHTS)
    if shards != expected_shards:
        raise RuntimeError(f"unexpected DSpark shard set: {shards}")
    if len(mtp_map) != 4708:
        raise RuntimeError(f"unexpected DSpark tensor count: {len(mtp_map)}")
    reduced = {
        "metadata": {
            "total_size": sum(item["bytes"] for item in WEIGHTS),
            "source_repository": REPO,
            "source_revision": REVISION,
            "tensor_scope": "mtp.* only",
        },
        "weight_map": mtp_map,
    }
    (DEST / "model.safetensors.index.json").write_text(json.dumps(reduced, indent=2, sort_keys=True) + "\n")
    report = {
        "repository": REPO,
        "revision": REVISION,
        "complete": True,
        "mtp_tensor_count": len(mtp_map),
        "verified_weight_bytes": sum(item["bytes"] for item in rows),
        "elapsed_seconds": round(time.time() - started, 3),
        "weight_files": rows,
        "metadata_files": small_paths,
        "reduced_index_sha256": sha256_file(DEST / "model.safetensors.index.json"),
    }
    (DEST / "verification-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
