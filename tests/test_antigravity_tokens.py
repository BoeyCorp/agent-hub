#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from scripts.antigravity_scanner import parse_transcripts, scan


class TestAntigravityTokens(unittest.TestCase):
    def test_parse_transcripts_extracts_tokens(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            brain = Path(tmpdir) / "brain"
            cid = "test-session-123"
            tpath = brain / cid / ".system_generated" / "logs" / "transcript.jsonl"
            tpath.parent.mkdir(parents=True, exist_ok=True)

            today_str = "2026-10-05"
            lines = [
                {"step_index": 0, "type": "USER_INPUT", "created_at": "2026-10-05T08:00:00Z", "content": "Hello agent"},
                {"step_index": 1, "type": "PLANNER_RESPONSE", "created_at": "2026-10-05T08:00:02Z", "input_tokens": 1500, "output_tokens": 200, "cache_read_tokens": 300, "tool_calls": []},
                {"step_index": 2, "type": "PLANNER_RESPONSE", "created_at": "2026-10-05T08:00:05Z", "input_tokens": 2500, "output_tokens": 400, "cache_read_tokens": 100, "tool_calls": []}
            ]
            with open(tpath, "w") as f:
                for l in lines:
                    f.write(json.dumps(l) + "\n")

            tool_cnt, models, mlist, latest_m, tokens_by_model = parse_transcripts(
                brain, today_str=today_str, recent_dates=[today_str], default_model="Gemini 3.8 Flash (High)", base_dir=Path(tmpdir)
            )

            # Sum: (1500 + 200 + 300) + (2500 + 400 + 100) = 2000 + 3000 = 5000
            total_tok = sum(tokens_by_model.values())
            self.assertEqual(total_tok, 5000)


if __name__ == "__main__":
    unittest.main()
