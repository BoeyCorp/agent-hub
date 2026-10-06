#!/usr/bin/env python3
import json
import os
import tempfile
import unittest
from pathlib import Path

from unittest.mock import patch

from scripts.claude_scanner import is_claude_process, kill_session as claude_kill_session, get_proc_starttime
from scripts.antigravity_scanner import is_antigravity_process
from scripts.codex_scanner import is_codex_process


class TestProcessGuards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base_dir = Path(self.tmp.name)
        self.sessions_dir = self.base_dir / "sessions"
        self.sessions_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_invalid_pids(self):
        self.assertFalse(is_claude_process(0))
        self.assertFalse(is_claude_process(-1))
        self.assertFalse(is_claude_process(999999999))
        self.assertFalse(is_claude_process("not_a_pid"))

    def test_non_claude_process_rejected(self):
        # Current python test process is alive, but is not claude
        my_pid = os.getpid()
        self.assertFalse(is_claude_process(my_pid))
        self.assertFalse(is_antigravity_process(my_pid))
        self.assertFalse(is_codex_process(my_pid))

    def test_proc_start_mismatch_detected(self):
        # Even if a PID exists, if expected_proc_start does not match /proc/<pid>/stat starttime, reject it
        my_pid = os.getpid()
        actual_start = get_proc_starttime(my_pid)
        if actual_start:
            # Force mismatch
            wrong_start = str(int(actual_start) + 9999)
            self.assertFalse(is_claude_process(my_pid, expected_proc_start=wrong_start))

    def test_proc_start_unavailable_rejected(self):
        my_pid = os.getpid()
        with patch("scripts.claude_scanner.get_proc_starttime", return_value=None):
            # If procStart was expected but cannot be verified from /proc, must reject
            self.assertFalse(is_claude_process(my_pid, expected_proc_start="12345"))

    def test_kill_session_rejects_unrelated_process(self):
        # Create a fake session file pointing to current test process (Python)
        my_pid = os.getpid()
        session_file = self.sessions_dir / f"{my_pid}.json"
        session_data = {
            "pid": my_pid,
            "sessionId": "test-unrelated-session-123",
            "procStart": get_proc_starttime(my_pid) or "12345"
        }
        session_file.write_text(json.dumps(session_data), encoding="utf-8")

        # kill_session must verify process identity and refuse to terminate python
        result = claude_kill_session("test-unrelated-session-123", self.base_dir)
        self.assertFalse(result)

    def test_kill_session_rejects_nonexistent_pid(self):
        session_file = self.sessions_dir / "99999999.json"
        session_data = {
            "pid": 99999999,
            "sessionId": "test-dead-session-456",
            "procStart": "12345"
        }
        session_file.write_text(json.dumps(session_data), encoding="utf-8")

        result = claude_kill_session("test-dead-session-456", self.base_dir)
        self.assertFalse(result)


if __name__ == "__main__":
    unittest.main()
