#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from scripts.hub_hooks import (
    install_claude_hooks,
    remove_claude_hooks,
    claude_hooks_installed,
    install_antigravity_hooks,
    remove_antigravity_hooks,
    antigravity_hooks_installed,
    get_status,
    install_all,
    remove_all
)


class TestHubHooks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self.tmp.name)
        self.claude_path = self.tmp_dir / "claude_settings.json"
        self.agy_path = self.tmp_dir / "agy_hooks.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_claude_hooks_lifecycle(self):
        self.assertFalse(claude_hooks_installed({}))
        changed = install_claude_hooks(self.claude_path)
        self.assertTrue(changed)

        with open(self.claude_path) as f:
            data = json.load(f)
        self.assertTrue(claude_hooks_installed(data))

        # Idempotent install
        self.assertFalse(install_claude_hooks(self.claude_path))

        # Remove
        removed = remove_claude_hooks(self.claude_path)
        self.assertTrue(removed)
        with open(self.claude_path) as f:
            data = json.load(f)
        self.assertFalse(claude_hooks_installed(data))

    def test_antigravity_hooks_lifecycle(self):
        self.assertFalse(antigravity_hooks_installed({}))
        changed = install_antigravity_hooks(self.agy_path)
        self.assertTrue(changed)

        with open(self.agy_path) as f:
            data = json.load(f)
        self.assertTrue(antigravity_hooks_installed(data))

        # Idempotent install
        self.assertFalse(install_antigravity_hooks(self.agy_path))

        # Remove
        removed = remove_antigravity_hooks(self.agy_path)
        self.assertTrue(removed)
        with open(self.agy_path) as f:
            data = json.load(f)
        self.assertFalse(antigravity_hooks_installed(data))

    def test_install_all_and_remove_all(self):
        res = install_all(self.claude_path, self.agy_path)
        self.assertTrue(res["changed"])
        self.assertTrue(res["installed"])

        status = get_status(self.claude_path, self.agy_path)
        self.assertTrue(status["allInstalled"])

        rem = remove_all(self.claude_path, self.agy_path)
        self.assertTrue(rem["changed"])
        status2 = get_status(self.claude_path, self.agy_path)
        self.assertFalse(status2["installed"])


if __name__ == "__main__":
    unittest.main()
