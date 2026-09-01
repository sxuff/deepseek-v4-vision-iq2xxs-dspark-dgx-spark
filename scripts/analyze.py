#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path


def arm(data: dict) -> dict:
    rows=data["rows"]
    tokens=sum(int(r["usage"]["completion_tokens"]) for r in rows)
    wall=sum(float(r["elapsed_seconds"]) for r in rows)
    predicted=sum(float(r["server_predicted_tokens"]) for r in rows)
    predicted_seconds=sum(float(r["server_predicted_seconds"]) for r in rows)
    return {
        "rows":len(rows),"completion_tokens":tokens,"wall_seconds":wall,
        "aggregate_whole_request_completion_tokens_per_second":tokens/wall,
        "weighted_server_decode_tokens_per_second":predicted/predicted_seconds,
    }


def main() -> int:
    p=argparse.ArgumentParser()
    p.add_argument("--baseline",type=Path,required=True)
    p.add_argument("--treatment",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    baseline=json.loads(a.baseline.read_text()); treatment=json.loads(a.treatment.read_text())
    if len(baseline["rows"]) != len(treatment["rows"]):
        raise SystemExit("arm row counts differ")
    rows=[]
    for br,tr in zip(baseline["rows"],treatment["rows"]):
        if br["id"] != tr["id"]:
            raise SystemExit("fixture order differs")
        rows.append({
            "fixture_id":br["id"],
            "request_payload_match":br["request_sha256"]==tr["request_sha256"],
            "exact_output_match":br["content_sha256"]==tr["content_sha256"],
            "finish_reason_match":br["finish_reason"]==tr["finish_reason"],
            "completion_tokens_baseline":br["usage"]["completion_tokens"],
            "completion_tokens_treatment":tr["usage"]["completion_tokens"],
            "baseline_wall_seconds":br["elapsed_seconds"],
            "treatment_wall_seconds":tr["elapsed_seconds"],
            "wall_speed_ratio":br["elapsed_seconds"]/tr["elapsed_seconds"],
            "draft_tokens":tr["spec_draft_tokens"],
            "accepted_tokens":tr["spec_accepted_tokens"],
            "acceptance_rate":tr["spec_acceptance_rate"],
        })
    ba=arm(baseline); ta=arm(treatment)
    result={
        "schema_version":1,"baseline":ba,"treatment":ta,
        "paired":{
            "rows":len(rows),
            "request_payload_matches":sum(r["request_payload_match"] for r in rows),
            "exact_output_matches":sum(r["exact_output_match"] for r in rows),
            "finish_reason_matches":sum(r["finish_reason_match"] for r in rows),
            "aggregate_whole_request_speed_ratio":ta["aggregate_whole_request_completion_tokens_per_second"]/ba["aggregate_whole_request_completion_tokens_per_second"],
            "weighted_server_decode_speed_ratio":ta["weighted_server_decode_tokens_per_second"]/ba["weighted_server_decode_tokens_per_second"],
            "draft_tokens":sum(r["draft_tokens"] for r in rows),
            "accepted_tokens":sum(r["accepted_tokens"] for r in rows),
            "rows_detail":rows,
        },
        "metric_definition":"aggregate whole-request tok/s = total completion tokens divided by total wall time, including prefill and first-token latency",
    }
    total_draft=result["paired"]["draft_tokens"]
    result["paired"]["acceptance_rate"]=result["paired"]["accepted_tokens"]/total_draft if total_draft else None
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    print(json.dumps(result,indent=2,sort_keys=True))
    return 0

if __name__=="__main__": raise SystemExit(main())
