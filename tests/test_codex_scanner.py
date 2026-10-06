#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from scripts import codex_scanner


class TestCodexScanner(unittest.TestCase):
    def test_empty_result_structure(self):
        res = codex_scanner.empty_result()
        self.assertEqual(res["id"], "codex")
        self.assertEqual(res["name"], "Codex")
        self.assertFalse(res["ready"])
        self.assertIn("activeSessions", res)
        self.assertIn("recentSessions", res)
        self.assertIn("quotaGroups", res)
        self.assertIn("todayTokenCost", res)
        self.assertEqual(res["todayTokenCost"], 0.0)

    def test_clean_model_display_name(self):
        self.assertEqual(codex_scanner.clean_model_display_name("gpt-6-luna"), "GPT-6 Luna")
        self.assertEqual(codex_scanner.clean_model_display_name("gpt-5"), "GPT-5")
        self.assertEqual(codex_scanner.clean_model_display_name("o3-mini"), "OpenAI o3-mini")

    def test_scan_codex_with_temp_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            sessions_dir = base / "sessions" / "2026" / "10" / "06"
            sessions_dir.mkdir(parents=True, exist_ok=True)
            res = codex_scanner.scan(base, force=True)
            self.assertEqual(res["id"], "codex")
            self.assertIn("todayPrompts", res)
            self.assertIn("quotaGroups", res)

    def test_codex_session_task_complete_is_waiting(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            cid = "01a10f08-d494-7501-a1c4-a0772361481d"
            sessions_dir = base / "sessions" / "2026" / "10" / "06"
            sessions_dir.mkdir(parents=True, exist_ok=True)
            rollout = sessions_dir / f"rollout-2026-10-06T10-26-39-{cid}.jsonl"

            lines = [
                {"type": "session_meta", "payload": {"id": cid, "cwd": "/home/boeyadmin"}},
                {"type": "event_msg", "payload": {"type": "task_started", "turn_id": "turn-1"}},
                {"type": "response_item", "payload": {"role": "user", "content": [{"type": "input_text", "text": "review code"}]}},
                {"type": "event_msg", "payload": {"type": "item_completed", "item": {"type": "AgentMessage"}}},
                {"type": "event_msg", "payload": {"type": "task_complete", "turn_id": "turn-1"}},
            ]
            with open(rollout, "w", encoding="utf-8") as f:
                for line in lines:
                    f.write(json.dumps(line) + "\n")

            # Set mtime to past (> 2s ago)
            import os, time
            past_mtime = time.time() - 60
            os.utime(rollout, (past_mtime, past_mtime))

            # Simulate held lock
            from unittest.mock import patch
            with patch("scripts.codex_scanner.check_active_lock_threads", return_value={cid: 99999}):
                with patch("scripts.codex_scanner.fetch_codex_rpc_cached", return_value={}):
                    res = codex_scanner.scan(base, force=True)

            self.assertTrue(res["hasActiveSession"])
            self.assertEqual(res["activeStatus"], "Waiting")
            self.assertEqual(len(res["recentSessions"]), 1)
            sess = res["recentSessions"][0]
            self.assertTrue(sess["isActive"])
            self.assertFalse(sess["notFullyIdle"])
            self.assertFalse(sess["isWorking"])
            self.assertEqual(sess["preview"], "review code")
            self.assertEqual(sess["stepCount"], 1)

    def test_codex_session_task_started_is_working(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            cid = "01a10f08-d494-7501-a1c4-a0772361481d"
            sessions_dir = base / "sessions" / "2026" / "10" / "06"
            sessions_dir.mkdir(parents=True, exist_ok=True)
            rollout = sessions_dir / f"rollout-2026-10-06T10-26-39-{cid}.jsonl"

            lines = [
                {"type": "session_meta", "payload": {"id": cid, "cwd": "/home/boeyadmin"}},
                {"type": "event_msg", "payload": {"type": "task_started", "turn_id": "turn-1"}},
                {"type": "response_item", "payload": {"role": "user", "content": [{"type": "input_text", "text": "generating code"}]}},
            ]
            with open(rollout, "w", encoding="utf-8") as f:
                for line in lines:
                    f.write(json.dumps(line) + "\n")

            from unittest.mock import patch
            with patch("scripts.codex_scanner.check_active_lock_threads", return_value={cid: 99999}):
                with patch("scripts.codex_scanner.fetch_codex_rpc_cached", return_value={}):
                    res = codex_scanner.scan(base, force=True)

            self.assertTrue(res["hasActiveSession"])
            self.assertEqual(res["activeStatus"], "Working")
            self.assertEqual(len(res["recentSessions"]), 1)
            sess = res["recentSessions"][0]
            self.assertTrue(sess["isActive"])
            self.assertTrue(sess["notFullyIdle"])
            self.assertTrue(sess["isWorking"])

    def test_codex_session_without_lock_is_idle(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            cid = "01a10f08-d494-7501-a1c4-a0772361481d"
            sessions_dir = base / "sessions" / "2026" / "10" / "06"
            sessions_dir.mkdir(parents=True, exist_ok=True)
            rollout = sessions_dir / f"rollout-2026-10-06T10-26-39-{cid}.jsonl"

            lines = [
                {"type": "session_meta", "payload": {"id": cid, "cwd": "/home/boeyadmin"}},
                {"type": "event_msg", "payload": {"type": "task_complete", "turn_id": "turn-1"}},
            ]
            with open(rollout, "w", encoding="utf-8") as f:
                for line in lines:
                    f.write(json.dumps(line) + "\n")

            from unittest.mock import patch
            with patch("scripts.codex_scanner.check_active_lock_threads", return_value={}):
                with patch("scripts.codex_scanner.fetch_codex_rpc_cached", return_value={}):
                    res = codex_scanner.scan(base, force=True)

            self.assertFalse(res["hasActiveSession"])
            self.assertEqual(res["activeStatus"], "Idle")
            sess = res["recentSessions"][0]
            self.assertFalse(sess["isActive"])
            self.assertFalse(sess["notFullyIdle"])
            self.assertFalse(sess["isWorking"])


if __name__ == "__main__":
    unittest.main()
