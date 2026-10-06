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

    def test_invalid_json_handling_does_not_overwrite(self):
        corrupted = '{ "broken_json": [ '
        self.claude_path.write_text(corrupted, encoding="utf-8")
        self.agy_path.write_text(corrupted, encoding="utf-8")

        from scripts.hub_hooks import load_json
        with self.assertRaises(ValueError):
            load_json(self.claude_path)
        with self.assertRaises(ValueError):
            load_json(self.agy_path)

        with self.assertRaises(ValueError):
            install_claude_hooks(self.claude_path)
        with self.assertRaises(ValueError):
            install_antigravity_hooks(self.agy_path)

        # Content on disk must NOT be overwritten!
        self.assertEqual(self.claude_path.read_text(encoding="utf-8"), corrupted)
        self.assertEqual(self.agy_path.read_text(encoding="utf-8"), corrupted)

        # Status call handles error cleanly
        status = get_status(self.claude_path, self.agy_path)
        self.assertFalse(status["claudeInstalled"])
        self.assertFalse(status["antigravityInstalled"])
        self.assertIn("errors", status)

    def test_antigravity_hooks_preserves_custom_handlers(self):
        initial = {
            "herdr": {
                "PreInvocation": [{"type": "command", "command": "bash herdr.sh"}]
            },
            "agent-hub-sync": {
                "enabled": True,
                "customSetting": "preserved_val",
                "PreInvocation": [{"type": "command", "command": "bash my_script.sh", "timeout": 5}]
            }
        }
        self.agy_path.write_text(json.dumps(initial, indent=2), encoding="utf-8")

        # Install agent-hub hook
        changed = install_antigravity_hooks(self.agy_path)
        self.assertTrue(changed)

        with open(self.agy_path) as f:
            data = json.load(f)

        # Check other key preserved
        self.assertIn("herdr", data)
        self.assertEqual(data["herdr"]["PreInvocation"][0]["command"], "bash herdr.sh")

        # Check custom metadata preserved
        entry = data["agent-hub-sync"]
        self.assertEqual(entry.get("customSetting"), "preserved_val")

        # Check custom handler still present in PreInvocation alongside ours
        pre_commands = [h["command"] for h in entry["PreInvocation"]]
        self.assertIn("bash my_script.sh", pre_commands)
        self.assertEqual(len(entry["PreInvocation"]), 2)

        # Remove agent-hub hook
        removed = remove_antigravity_hooks(self.agy_path)
        self.assertTrue(removed)

        with open(self.agy_path) as f:
            data_after = json.load(f)

        # herdr and customSetting must still be present
        self.assertIn("herdr", data_after)
        self.assertIn("agent-hub-sync", data_after)
        entry_after = data_after["agent-hub-sync"]
        self.assertEqual(entry_after.get("customSetting"), "preserved_val")

        # PreInvocation must still have bash my_script.sh, but our hook command is gone
        pre_after = [h["command"] for h in entry_after.get("PreInvocation", [])]
        self.assertIn("bash my_script.sh", pre_after)
        self.assertEqual(len(pre_after), 1)

        # PostInvocation and Stop should be removed since they only had our command
        self.assertNotIn("PostInvocation", entry_after)
        self.assertNotIn("Stop", entry_after)


if __name__ == "__main__":
    unittest.main()
