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
        for p in ("claude", "antigravity", "codex"):
            self.assertIn(p, res["agentStates"])
            st = res["agentStates"][p]
            self.assertIn("color", st)
            self.assertIn("name", st)
            self.assertIsInstance(st["active"], bool)
            self.assertIsInstance(st["working"], bool)
            self.assertIsInstance(st["waiting"], bool)
            self.assertEqual(st["waiting"], st["active"] and not st["working"])
            self.assertIn(st["status"], ("Working", "Waiting", "Idle"))
            if st["working"]:
                self.assertTrue(st["active"])
                self.assertEqual(st["status"], "Working")
            elif st["waiting"]:
                self.assertTrue(st["active"])
                self.assertEqual(st["status"], "Waiting")
            else:
                self.assertFalse(st["active"])
                self.assertEqual(st["status"], "Idle")

    def test_agent_activity_states_invariants(self):
        from unittest.mock import patch

        cases = [
            # (c_active, c_status, a_active, a_status, x_active, x_status, expected_overall)
            (True, "Working", False, "Idle", True, "Waiting", "Working"),
            (False, "Idle", True, "Waiting", True, "Waiting", "Waiting"),
            (False, "Idle", False, "Idle", False, "Idle", "Idle"),
            (False, "Idle", False, "Idle", True, "Working", "Working"),
        ]

        from scripts import hub_scanner

        for c_act, c_stat, a_act, a_stat, x_act, x_stat, exp_overall in cases:
            c_mock = {"hasActiveSession": c_act, "activeStatus": c_stat, "activeSessions": [], "recentSessions": [], "quotaGroups": [], "todayPrompts": 0, "todaySteps": 0, "todayTotalTokens": 0, "todayTokenCost": 0.0, "todayCacheReadTokens": 0, "todayCacheCreationTokens": 0, "todayInputTokens": 0, "todayOutputTokens": 0, "todayCacheHitRate": 0.0, "recentDays": [], "toolUsage": {}, "models": []}
            a_mock = {"hasActiveSession": a_act, "activeStatus": a_stat, "activeSessions": [], "recentSessions": [], "quotaGroups": [], "todayPrompts": 0, "todaySteps": 0, "todayTotalTokens": 0, "todayTokenCost": 0.0, "todayCacheReadTokens": 0, "todayCacheCreationTokens": 0, "todayInputTokens": 0, "todayOutputTokens": 0, "todayCacheHitRate": 0.0, "recentDays": [], "toolUsage": {}, "models": []}
            x_mock = {"hasActiveSession": x_act, "activeStatus": x_stat, "activeSessions": [], "recentSessions": [], "quotaGroups": [], "todayPrompts": 0, "todaySteps": 0, "todayTotalTokens": 0, "todayTokenCost": 0.0, "todayCacheReadTokens": 0, "todayCacheCreationTokens": 0, "todayInputTokens": 0, "todayOutputTokens": 0, "todayCacheHitRate": 0.0, "recentDays": [], "toolUsage": {}, "models": []}

            with patch.object(hub_scanner.claude_scanner, "scan", return_value=c_mock), \
                 patch.object(hub_scanner.antigravity_scanner, "scan", return_value=a_mock), \
                 patch.object(hub_scanner.codex_scanner, "scan", return_value=x_mock):
                res = scan_hub(enable_claude=True, enable_antigravity=True, enable_codex=True, force=True)

            self.assertEqual(res["activeStatus"], exp_overall)

            # Test Codex states specifically
            codex_st = res["agentStates"]["codex"]
            self.assertEqual(codex_st["active"], x_act)
            self.assertEqual(codex_st["working"], x_act and x_stat == "Working")
            self.assertEqual(codex_st["waiting"], x_act and x_stat != "Working")
            self.assertEqual(codex_st["status"], x_stat if x_act else "Idle")

    def test_focus_script_help(self):
        import subprocess
        script = Path(__file__).resolve().parent.parent / "scripts" / "hub_focus_or_resume.py"
        res = subprocess.run(["python3", str(script), "--help"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("--cid", res.stdout)


if __name__ == "__main__":
    unittest.main()

