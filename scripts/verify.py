#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        while block:=f.read(8<<20): h.update(block)
    return h.hexdigest()

def main() -> int:
    for path in ROOT.rglob("*.json"): json.loads(path.read_text())
    s=json.loads((ROOT/"results/summary.json").read_text())
    assert s["paired"]["rows"]==4
    assert s["paired"]["request_payload_matches"]==4
    assert s["paired"]["exact_output_matches"]==4
    assert abs(s["paired"]["accepted_tokens"]/s["paired"]["draft_tokens"]-s["paired"]["acceptance_rate"])<1e-12
    a=s["arms"]["no-spec"]; b=s["arms"]["dspark"]
    assert abs(a["completion_tokens"]/a["wall_seconds"]-a["aggregate_whole_request_completion_tokens_per_second"])<1e-12
    assert abs(b["completion_tokens"]/b["wall_seconds"]-b["aggregate_whole_request_completion_tokens_per_second"])<1e-12
    assert abs(b["aggregate_whole_request_completion_tokens_per_second"]/a["aggregate_whole_request_completion_tokens_per_second"]-s["paired"]["aggregate_whole_request_speed_ratio"])<1e-12
    target=json.loads((ROOT/"manifests/target.json").read_text())
    assert sum(x["bytes"] for x in target["files"])==target["total_bytes"]==85585821888
    draft=json.loads((ROOT/"manifests/dspark-source.json").read_text())
    assert sum(x["bytes"] for x in draft["selected_weight_files"])==draft["verified_weight_bytes"]==10863345700
    runtime=json.loads((ROOT/"runtime-manifest.json").read_text())
    patch=ROOT/runtime["patch"]
    assert patch.stat().st_size==runtime["patch_bytes"]
    assert sha(patch)==runtime["patch_sha256"]
    readme=(ROOT/"README.md").read_text(); card=(ROOT/"CARD_VALUES.md").read_text()
    for needle in ("20.05 tok/s","37.47 tok/s","1.87x","97.85%","4/4"):
        assert needle in readme, needle
    for needle in ("20.1 tok/s","37.5 tok/s","1.87x","97.9%","4 / 4"):
        assert needle in card, needle
    forbidden=("/home/"+"sxuf","/opt/"+"data","["+"REDACTED"+"]")
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts or "__pycache__" in path.parts or path.suffix in {".pyc", ".png"} or path.stat().st_size>2_000_000: continue
        text=path.read_text(errors="ignore")
        for token in forbidden: assert token not in text, f"{token} in {path}"
    print("VERIFIED: JSON, metrics, manifests, patch, card values, and public-path scan")
    return 0

if __name__=="__main__": raise SystemExit(main())
