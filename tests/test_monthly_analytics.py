#!/usr/bin/env python3
"""Unit tests for Monthly Usage & Analytics Engine."""

import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path

from scripts.monthly_analytics import (
    aggregate_monthly,
    get_calendar_month_date_list,
    get_rolling_date_list,
    scan_claude_monthly,
    scan_antigravity_monthly,
    scan_codex_monthly,
)


class TestMonthlyAnalytics(unittest.TestCase):
    def test_rolling_date_list_length_and_order(self):
        end = dt.date(2026, 10, 9)
        dates = get_rolling_date_list(num_days=30, end_date=end)
        self.assertEqual(len(dates), 30)
        self.assertEqual(dates[-1], "2026-10-09")
        self.assertEqual(dates[0], "2026-09-10")
        self.assertEqual(dates, sorted(dates))

    def test_calendar_month_date_list(self):
        feb_dates = get_calendar_month_date_list(year=2024, month=2)  # leap year
        self.assertEqual(len(feb_dates), 29)
        self.assertEqual(feb_dates[0], "2024-02-01")
        self.assertEqual(feb_dates[-1], "2024-02-29")

        oct_dates = get_calendar_month_date_list(year=2026, month=10)
        self.assertEqual(len(oct_dates), 31)

    def test_mock_transcripts_aggregation(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            claude_dir = base / "claude"
            claude_dir.mkdir()
            agy_dir = base / "gemini"
            agy_dir.mkdir()
            codex_dir = base / "codex"
            codex_dir.mkdir()
            cache_file = base / "test_cache.json"

            # Create mock Claude history
            (claude_dir / "history.jsonl").write_text(
                json.dumps({"timestamp": 1789990000000, "display": "test prompt 1"}) + "\n"
                + json.dumps({"timestamp": 1789990000000, "display": "test prompt 2"}) + "\n"
            )

            # Create mock Claude project transcript
            proj_dir = claude_dir / "projects" / "test_proj"
            proj_dir.mkdir(parents=True)
            mock_day = dt.datetime.fromtimestamp(1789990000).strftime("%Y-%m-%d")
            (proj_dir / "session1.jsonl").write_text(
                json.dumps({
                    "type": "assistant",
                    "timestamp": f"{mock_day}T12:00:00Z",
                    "message": {
                        "model": "claude-3-5-sonnet",
                        "usage": {
                            "input_tokens": 1000,
                            "output_tokens": 200,
                            "cache_read_input_tokens": 4000,
                            "cache_creation_input_tokens": 0
                        }
                    }
                }) + "\n"
            )

            res = aggregate_monthly(
                num_days=30,
                end_date=dt.datetime.fromtimestamp(1789990000).date(),
                claude_base_dir=claude_dir,
                antigravity_base_dir=agy_dir,
                codex_base_dir=codex_dir,
                cache_path=cache_file,
                force=True
            )

            self.assertEqual(res["schemaVersion"], 1)
            self.assertIn("period", res)
            self.assertIn("summary", res)
            self.assertIn("byAgent", res)
            self.assertIn("daily", res)
            self.assertIn("heatmap", res)

            # Invariants
            self.assertEqual(len(res["daily"]), 30)
            self.assertEqual(len(res["heatmap"]), 30)

            day_entry = [d for d in res["daily"] if d["date"] == mock_day][0]
            self.assertEqual(day_entry["prompts"], 2)
            self.assertEqual(day_entry["steps"], 1)
            self.assertEqual(day_entry["tokens"], 5200)
            self.assertEqual(day_entry["inputTokens"], 1000)
            self.assertEqual(day_entry["outputTokens"], 200)
            self.assertEqual(day_entry["cacheReadTokens"], 4000)
            self.assertEqual(day_entry["agents"]["claude"]["prompts"], 2)

            self.assertTrue(cache_file.exists())

    def test_schema_contract_with_real_data(self):
        res = aggregate_monthly(num_days=7)
        self.assertEqual(res["schemaVersion"], 1)
        self.assertEqual(len(res["daily"]), 7)
        self.assertEqual(len(res["heatmap"]), 7)

        s = res["summary"]
        self.assertIn("totalTokens", s)
        self.assertIn("totalCost", s)
        self.assertIn("totalPrompts", s)
        self.assertIn("totalSteps", s)
        self.assertIn("overallCacheHitRate", s)
        self.assertIn("busiestDay", s)

        # Mathematical invariants
        sum_tokens = sum(d["tokens"] for d in res["daily"])
        sum_prompts = sum(d["prompts"] for d in res["daily"])
        sum_steps = sum(d["steps"] for d in res["daily"])
        self.assertEqual(s["totalTokens"], sum_tokens)
        self.assertEqual(s["totalPrompts"], sum_prompts)
        self.assertEqual(s["totalSteps"], sum_steps)

        for h in res["heatmap"]:
            self.assertGreaterEqual(h["intensity"], 0)
            self.assertLessEqual(h["intensity"], 4)

    def test_multi_period_views(self):
        for days in (30, 60, 90):
            res = aggregate_monthly(num_days=days)
            self.assertEqual(res["schemaVersion"], 1)
            self.assertEqual(len(res["daily"]), days)
            self.assertEqual(len(res["heatmap"]), days)
            self.assertEqual(res["period"]["daysCount"], days)

    def test_custom_date_range_aggregation(self):
        start = dt.date(2026, 9, 1)
        end = dt.date(2026, 9, 15)
        res = aggregate_monthly(start_date=start, end_date=end)
        self.assertEqual(res["schemaVersion"], 1)
        self.assertEqual(len(res["daily"]), 15)
        self.assertEqual(res["period"]["start"], "2026-09-01")
        self.assertEqual(res["period"]["end"], "2026-09-15")
        self.assertEqual(res["period"]["daysCount"], 15)
        self.assertEqual(res["period"]["label"], "Sep 01 – Sep 15, 2026")


if __name__ == "__main__":
    unittest.main()
