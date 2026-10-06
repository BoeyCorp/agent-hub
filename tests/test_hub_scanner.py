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
        x_tools = {"bash": 5, "read_file": 2, "edit_file": 1}
        combined = normalize_combined_tools(c_tools, a_tools, x_tools)

        self.assertEqual(combined["Terminal / Commands"], 30)
        self.assertEqual(combined["File Viewing / Reading"], 15)
        self.assertEqual(combined["File Editing"], 8)

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

    def test_group_session_hierarchy(self):
        from scripts.hub_scanner import group_session_hierarchy
        sessions = [
            {"conversationId": "parent-1", "title": "Main Project", "isSubagent": False, "parentConversationId": ""},
            {"conversationId": "sub-1", "title": "Sub Task 1", "isSubagent": True, "parentConversationId": "parent-1"},
            {"conversationId": "parent-2", "title": "Another Project", "isSubagent": False, "parentConversationId": ""},
            {"conversationId": "sub-2", "title": "Sub Task 2", "isSubagent": True, "parentConversationId": "parent-1"},
        ]
        grouped = group_session_hierarchy(sessions)
        self.assertEqual(len(grouped), 4)
        self.assertEqual(grouped[0]["conversationId"], "parent-1")
        self.assertEqual(grouped[1]["conversationId"], "sub-1")
        self.assertEqual(grouped[1]["indent"], 1)
        self.assertEqual(grouped[2]["conversationId"], "sub-2")
        self.assertEqual(grouped[2]["indent"], 1)
        self.assertEqual(grouped[3]["conversationId"], "parent-2")

    def test_scan_hub_schema_contract(self):
        res = scan_hub(enable_claude=True, enable_antigravity=True, force=True)
        self.assertEqual(res.get("schemaVersion"), 1)
        self.assertEqual(res.get("id"), "agent-hub")
        self.assertIn("todayPrompts", res)
        self.assertIn("todaySteps", res)
        self.assertIn("todayTotalTokens", res)
        self.assertIn("todayTokenCost", res)
        self.assertIn("todayTokenCostByAgent", res)
        self.assertIn("todayCacheReadTokens", res)
        self.assertIn("todayCacheHitRate", res)
        self.assertIn("activeSessions", res)
        self.assertIn("recentSessions", res)
        self.assertIn("quotaGroups", res)
        self.assertIn("providers", res)
        self.assertIn("claude", res["providers"])
        self.assertIn("antigravity", res["providers"])
        self.assertIn("codex", res["providers"])
        self.assertIn("codexData", res)
        self.assertIn("agentStates", res)
        self.assertIn("claude", res["agentStates"])
        self.assertIn("antigravity", res["agentStates"])
        self.assertIn("codex", res["agentStates"])
        self.assertIn("color", res["agentStates"]["claude"])
        self.assertIn("color", res["agentStates"]["antigravity"])
        self.assertIn("color", res["agentStates"]["codex"])

    def test_focus_script_help(self):
        import subprocess
        script = Path(__file__).resolve().parent.parent / "scripts" / "hub_focus_or_resume.py"
        res = subprocess.run(["python3", str(script), "--help"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("--cid", res.stdout)


if __name__ == "__main__":
    unittest.main()

