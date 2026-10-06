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


if __name__ == "__main__":
    unittest.main()
