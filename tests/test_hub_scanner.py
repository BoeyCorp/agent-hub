#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from scripts.hub_scanner import scan_hub, normalize_combined_tools, merge_recent_days


class TestHubScanner(unittest.TestCase):
    def test_normalize_combined_tools(self):
        c_tools = {"Bash": 10, "Read": 5, "Edit": 3}
        a_tools = {"run_command": 15, "view_file": 8, "replace_file_content": 4}
        combined = normalize_combined_tools(c_tools, a_tools)

        self.assertEqual(combined["Terminal / Commands"], 25)
        self.assertEqual(combined["File Viewing / Reading"], 13)
        self.assertEqual(combined["File Editing"], 7)

    def test_merge_recent_days(self):
        days_a = [
            {"date": "2026-10-04", "messageCount": 5, "prompts": 5, "steps": 20},
            {"date": "2026-10-05", "messageCount": 10, "prompts": 10, "steps": 50},
        ]
        days_b = [
            {"date": "2026-10-03", "messageCount": 2, "prompts": 2, "steps": 10},
            {"date": "2026-10-05", "messageCount": 8, "prompts": 8, "steps": 40},
        ]
        merged = merge_recent_days(days_a, days_b)
        self.assertEqual(len(merged), 3)
        # 2026-10-05 should combine both: 10 + 8 = 18 prompts, 50 + 40 = 90 steps
        d5 = [d for d in merged if d["date"] == "2026-10-05"][0]
        self.assertEqual(d5["prompts"], 18)
        self.assertEqual(d5["steps"], 90)

    def test_scan_hub_schema_contract(self):
        res = scan_hub(enable_claude=True, enable_antigravity=True, force=True)
        self.assertEqual(res.get("schemaVersion"), 1)
        self.assertEqual(res.get("id"), "agent-hub")
        self.assertIn("todayPrompts", res)
        self.assertIn("todaySteps", res)
        self.assertIn("todayTotalTokens", res)
        self.assertIn("activeSessions", res)
        self.assertIn("recentSessions", res)
        self.assertIn("quotaGroups", res)
        self.assertIn("providers", res)
        self.assertIn("claude", res["providers"])
        self.assertIn("antigravity", res["providers"])


if __name__ == "__main__":
    unittest.main()
