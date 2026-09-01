#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import urllib.request
from pathlib import Path


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def fixture_python() -> str:
    rows = [
        "from dataclasses import dataclass", "", "@dataclass(frozen=True)", "class Event:",
        "    sequence: int", "    topic: str", "    payload: str", "", "EVENTS = [",
    ]
    for i in range(48):
        rows.append(f'    Event(sequence={i}, topic="build.step.{i % 6}", payload="artifact-{i:03d}"),')
    rows.extend([
        "]", "", "def by_topic(events: list[Event]) -> dict[str, list[Event]]:",
        "    result: dict[str, list[Event]] = {}", "    for event in events:",
        "        result.setdefault(event.topic, []).append(event)", "    return result",
    ])
    return "\n".join(rows)


def fixture_json() -> str:
    rows = []
    for i in range(36):
        rows.append({
            "id": f"task-{i:03d}", "owner": f"worker-{i % 4}",
            "state": ["queued", "running", "passed"][i % 3], "attempt": i % 2 + 1,
        })
    return json.dumps(rows, indent=2, separators=(",", ": "))


def cases() -> list[dict]:
    py = fixture_python()
    js = fixture_json()
    return [
        {
            "id": "copy_python", "max_tokens": 1800,
            "messages": [{"role": "user", "content":
                "Return exactly the text between BEGIN and END. Do not add fences, commentary, or the markers.\n"
                f"BEGIN\n{py}\nEND"}],
        },
        {
            "id": "copy_json", "max_tokens": 2200,
            "messages": [{"role": "user", "content":
                "Return exactly the JSON between BEGIN and END. Do not add fences, commentary, or the markers.\n"
                f"BEGIN\n{js}\nEND"}],
        },
        {
            "id": "structured_transform", "max_tokens": 700,
            "messages": [{"role": "user", "content":
                "Using the task records below, return a JSON array containing only records whose state is passed. "
                "Preserve id, owner, state, and attempt exactly. Return JSON only.\n" + js}],
        },
        {
            "id": "novel_code", "max_tokens": 500,
            "messages": [{"role": "user", "content":
                "Write a Python function schedule_jobs(durations, workers) that assigns each positive integer "
                "duration to the currently least-loaded worker. Preserve input order for ties, reject workers below "
                "one, and do not mutate durations. Return only valid Python source with no code fence."}],
        },
    ]


def parse_metrics(text: str) -> dict[str, float]:
    out = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([^\s{]+)(?:\{[^}]*\})?\s+([-+0-9.eE]+)$", line)
        if match:
            try:
                out[match.group(1)] = float(match.group(2))
            except ValueError:
                pass
    return out


def meminfo() -> dict[str, int]:
    out = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        out[key] = int(value.strip().split()[0]) * 1024
    return out


class Client:
    def __init__(self, base_url: str):
        self.base = base_url.rstrip("/")
        self.headers = {"Accept": "application/json", "Content-Type": "application/json"}

    def raw(self, path: str, payload: dict | None = None, timeout: int = 1200) -> bytes:
        data = None if payload is None else canonical(payload)
        request = urllib.request.Request(self.base + path, data=data, headers=self.headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"{path} returned HTTP {response.status}")
            return response.read()

    def json(self, path: str, payload: dict | None = None, timeout: int = 1200):
        return json.loads(self.raw(path, payload, timeout))

    def metrics(self) -> dict[str, float]:
        return parse_metrics(self.raw("/metrics", timeout=30).decode())


def delta(after: dict[str, float], before: dict[str, float], name: str) -> float:
    return after.get(name, 0.0) - before.get(name, 0.0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8087")
    parser.add_argument("--arm", required=True, choices=("baseline", "ngram", "dspark"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    client = Client(args.base_url)
    model_body = client.json("/v1/models", timeout=30)
    model = model_body["data"][0]["id"]
    try:
        slots_before = client.json("/slots", timeout=30)
    except Exception as exc:
        slots_before = {"unavailable": repr(exc)}
    arm_mem_start = meminfo()
    arm_swap_start = arm_mem_start["SwapTotal"] - arm_mem_start["SwapFree"]
    rows = []

    for case in cases():
        payload = {
            "model": model,
            "messages": case["messages"],
            "temperature": 0.0,
            "top_p": 1.0,
            "seed": 42,
            "max_tokens": case["max_tokens"],
            "stream": False,
            "reasoning_effort": "none",
        }
        before = client.metrics()
        before_mem = meminfo()
        started = time.monotonic_ns()
        raw = client.raw("/v1/chat/completions", payload)
        elapsed_ns = time.monotonic_ns() - started
        after_mem = meminfo()
        after = client.metrics()
        response = json.loads(raw)
        choice = response["choices"][0]
        message = choice["message"]
        content = message.get("content") or ""
        reasoning = message.get("reasoning_content") or ""
        predicted_tokens = delta(after, before, "llamacpp:tokens_predicted_total")
        predicted_seconds = delta(after, before, "llamacpp:tokens_predicted_seconds_total")
        draft_tokens = delta(after, before, "llamacpp:spec_decode_num_draft_tokens_total")
        accepted_tokens = delta(after, before, "llamacpp:spec_decode_num_accepted_tokens_total")
        rows.append({
            "id": case["id"],
            "request_sha256": hashlib.sha256(canonical(payload)).hexdigest(),
            "content_sha256": hashlib.sha256(content.encode()).hexdigest(),
            "reasoning_sha256": hashlib.sha256(reasoning.encode()).hexdigest(),
            "content": content,
            "reasoning_content": reasoning,
            "finish_reason": choice.get("finish_reason"),
            "usage": response.get("usage") or {},
            "elapsed_seconds": elapsed_ns / 1e9,
            "server_predicted_tokens": predicted_tokens,
            "server_predicted_seconds": predicted_seconds,
            "server_decode_tokens_per_second": predicted_tokens / predicted_seconds if predicted_seconds > 0 else None,
            "spec_draft_tokens": draft_tokens,
            "spec_accepted_tokens": accepted_tokens,
            "spec_acceptance_rate": accepted_tokens / draft_tokens if draft_tokens > 0 else None,
            "mem_available_before_bytes": before_mem["MemAvailable"],
            "mem_available_after_bytes": after_mem["MemAvailable"],
            "swap_used_after_bytes": after_mem["SwapTotal"] - after_mem["SwapFree"],
            "raw_response_sha256": hashlib.sha256(raw).hexdigest(),
        })

    try:
        slots_after = client.json("/slots", timeout=30)
    except Exception as exc:
        slots_after = {"unavailable": repr(exc)}
    arm_mem_end = meminfo()
    result = {
        "schema_version": 1,
        "arm": args.arm,
        "model": model_body,
        "runtime_fingerprint": "llama.cpp 9c9a1546 + prometheus routing patch, SM121",
        "design": {"temperature": 0.0, "seed": 42, "reasoning_effort": "none", "repetitions": 1},
        "slots_before": slots_before,
        "slots_after": slots_after,
        "arm_memory": {
            "start_mem_available_bytes": arm_mem_start["MemAvailable"],
            "end_mem_available_bytes": arm_mem_end["MemAvailable"],
            "start_swap_used_bytes": arm_swap_start,
            "end_swap_used_bytes": arm_mem_end["SwapTotal"] - arm_mem_end["SwapFree"],
        },
        "rows": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(json.dumps({
        "arm": args.arm,
        "row_count": len(rows),
        "total_completion_tokens": sum(int(r["usage"].get("completion_tokens", 0)) for r in rows),
        "total_elapsed_seconds": sum(r["elapsed_seconds"] for r in rows),
        "total_draft_tokens": sum(r["spec_draft_tokens"] for r in rows),
        "total_accepted_tokens": sum(r["spec_accepted_tokens"] for r in rows),
        "output": str(args.output),
    }, indent=2))


if __name__ == "__main__":
    main()
