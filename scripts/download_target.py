#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "manifests" / "target.json").read_text())
DEST = Path(os.environ.get("MODEL_DIR", str(Path.home() / "models" / "DeepSeek-V4-Flash-Vision-Exp-Prometheus-IQ2_XXS")))
REPORT = DEST / "verification-report.json"
BASE = f"https://huggingface.co/{MANIFEST['repository']}/resolve/{MANIFEST['revision']}"
CHUNK = 16 * 1024 * 1024


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            block = f.read(CHUNK)
            if not block:
                return h.hexdigest()
            h.update(block)


def download_one(item: dict) -> dict:
    name = item["path"]
    expected_size = int(item["bytes"])
    expected_sha = item["sha256"]
    final = DEST / name
    part = final.with_suffix(final.suffix + ".part")
    final.parent.mkdir(parents=True, exist_ok=True)

    if final.exists() and final.stat().st_size == expected_size:
        actual = sha256_file(final)
        if actual == expected_sha:
            return {"path": name, "bytes": expected_size, "sha256": actual, "verified": True, "reused": True}
        final.rename(final.with_suffix(final.suffix + ".invalid"))

    if part.exists() and part.stat().st_size > expected_size:
        part.unlink()

    attempts = 0
    while True:
        current_size = part.stat().st_size if part.exists() else 0
        if current_size >= expected_size:
            break
        attempts += 1
        if attempts > 20:
            raise RuntimeError(f"too many retries for {name}")
        offset = part.stat().st_size if part.exists() else 0
        headers = {"User-Agent": "Hermes-Pinned-HF-Downloader/1.0"}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        req = urllib.request.Request(f"{BASE}/{name}", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                status = getattr(response, "status", None)
                if offset and status != 206:
                    part.unlink(missing_ok=True)
                    continue
                mode = "ab" if offset else "wb"
                with part.open(mode) as out:
                    while True:
                        block = response.read(CHUNK)
                        if not block:
                            break
                        out.write(block)
            current = part.stat().st_size
            if current > expected_size:
                part.unlink()
                raise RuntimeError(f"oversized transfer for {name}: {current} > {expected_size}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            print(f"retry {attempts} {name} at {offset}: {exc}", file=sys.stderr, flush=True)
            time.sleep(min(30, 2**min(attempts, 5)))

    actual = sha256_file(part)
    if actual != expected_sha:
        raise RuntimeError(f"sha256 mismatch for {name}: {actual} != {expected_sha}")
    os.replace(part, final)
    return {"path": name, "bytes": expected_size, "sha256": actual, "verified": True, "reused": False}


def main() -> int:
    global DEST, REPORT
    parser = argparse.ArgumentParser(description="Download and verify the pinned IQ2_XXS target plus projector")
    parser.add_argument("--destination", type=Path, default=DEST)
    args = parser.parse_args()
    DEST = args.destination.expanduser()
    REPORT = DEST / "verification-report.json"
    DEST.mkdir(parents=True, exist_ok=True)
    started = time.time()
    rows = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            futures = {pool.submit(download_one, item): item for item in MANIFEST["files"]}
            for future in concurrent.futures.as_completed(futures):
                row = future.result()
                rows.append(row)
                print(json.dumps(row, sort_keys=True), flush=True)
        rows.sort(key=lambda x: x["path"])
        report = {
            "repository": MANIFEST["repository"],
            "revision": MANIFEST["revision"],
            "complete": len(rows) == len(MANIFEST["files"]) and all(r["verified"] for r in rows),
            "verified_files": len(rows),
            "verified_bytes": sum(r["bytes"] for r in rows),
            "elapsed_seconds": round(time.time() - started, 3),
            "files": rows,
        }
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2), flush=True)
        return 0 if report["complete"] else 1
    except Exception as exc:
        report = {
            "repository": MANIFEST["repository"],
            "revision": MANIFEST["revision"],
            "complete": False,
            "error": repr(exc),
            "elapsed_seconds": round(time.time() - started, 3),
            "files": sorted(rows, key=lambda x: x["path"]),
        }
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise


if __name__ == "__main__":
    raise SystemExit(main())
