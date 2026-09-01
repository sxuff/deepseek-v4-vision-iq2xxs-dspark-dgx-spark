from __future__ import annotations
import json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class Contracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=json.loads((ROOT/"results/summary.json").read_text())
    def test_paired_identity(self):
        self.assertEqual(self.s["paired"]["rows"],4)
        self.assertEqual(self.s["paired"]["request_payload_matches"],4)
        self.assertEqual(self.s["paired"]["exact_output_matches"],4)
        self.assertEqual(self.s["paired"]["finish_reason_matches"],4)
    def test_speed_estimands(self):
        a=self.s["arms"]["no-spec"]; b=self.s["arms"]["dspark"]
        self.assertAlmostEqual(a["completion_tokens"]/a["wall_seconds"],a["aggregate_whole_request_completion_tokens_per_second"],places=12)
        self.assertAlmostEqual(b["completion_tokens"]/b["wall_seconds"],b["aggregate_whole_request_completion_tokens_per_second"],places=12)
        self.assertAlmostEqual(b["aggregate_whole_request_completion_tokens_per_second"]/a["aggregate_whole_request_completion_tokens_per_second"],self.s["paired"]["aggregate_whole_request_speed_ratio"],places=12)
    def test_acceptance(self):
        p=self.s["paired"]
        self.assertAlmostEqual(p["accepted_tokens"]/p["draft_tokens"],p["acceptance_rate"],places=12)
    def test_safety(self):
        self.assertTrue(self.s["gate"]["reserve_6_gib_passed"])
        self.assertTrue(self.s["gate"]["service_swap_zero"])
        self.assertGreater(self.s["arms"]["dspark"]["minimum_mem_available_bytes"],6*2**30)

if __name__=="__main__": unittest.main()
