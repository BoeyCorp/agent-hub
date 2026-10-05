#!/usr/bin/env python3
"""Unified Live Hook Updates Manager for Agent Hub.

Installs and removes non-destructive hooks for both Claude Code (~/.claude/settings.json)
and Google Antigravity (~/.gemini/config/hooks.json) so the top-bar widget updates the
moment an agent starts, submits a prompt, executes a step, or completes a task.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

HOOK_COMMAND = "omarchy-shell -q boeycorp.agent-hub refresh"
HOOK_TIMEOUT = 5

CLAUDE_HOOK_EVENTS = [
    "SessionStart",
    "UserPromptSubmit",
    "Stop",
    "Notification",
    "PermissionRequest",
    "SessionEnd"
]

ANTIGRAVITY_HOOK_KEY = "agent-hub-sync"


def default_claude_settings_path() -> Path:
    base = os.environ.get("CLAUDE_USAGE_DATA_DIR") or os.path.expanduser("~/.claude")
    return Path(base).expanduser() / "settings.json"


def default_antigravity_hooks_path() -> Path:
    base = os.environ.get("ANTIGRAVITY_CONFIG_DIR") or os.path.expanduser("~/.gemini/config")
    return Path(base).expanduser() / "hooks.json"


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_json(path: Path, data: dict[str, Any], bak_suffix: str = ".agent-hub.bak") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_suffix(path.suffix + bak_suffix)
        try:
            backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        except Exception:
            pass
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    tmp.replace(path)


# --- Claude Code Hooks ---

def claude_hooks_installed(settings: dict[str, Any]) -> bool:
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False
    for event in CLAUDE_HOOK_EVENTS:
        for group in hooks.get(event, []) or []:
            if not isinstance(group, dict):
                continue
            for entry in group.get("hooks", []) or []:
                if isinstance(entry, dict) and entry.get("command") == HOOK_COMMAND:
                    return True
    return False


def install_claude_hooks(path: Path) -> bool:
    settings = load_json(path)
    hooks = settings.setdefault("hooks", {})
    changed = False

    for event in CLAUDE_HOOK_EVENTS:
        groups = hooks.setdefault(event, [])
        already = any(
            isinstance(g, dict) and any(
                isinstance(e, dict) and e.get("command") == HOOK_COMMAND
                for e in (g.get("hooks") or [])
            )
            for g in groups
        )
        if already:
            continue
        groups.append({
            "matcher": "*",
            "hooks": [{"type": "command", "command": HOOK_COMMAND, "timeout": HOOK_TIMEOUT}]
        })
        changed = True

    if changed:
        save_json(path, settings)
    return changed


def remove_claude_hooks(path: Path) -> bool:
    settings = load_json(path)
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False

    changed = False
    for event in CLAUDE_HOOK_EVENTS:
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue

        new_groups = []
        for group in groups:
            if not isinstance(group, dict):
                new_groups.append(group)
                continue
            entries = group.get("hooks") or []
            kept = [e for e in entries if not (isinstance(e, dict) and e.get("command") == HOOK_COMMAND)]
            if len(kept) != len(entries):
                changed = True
            if kept:
                new_groups.append({**group, "hooks": kept})

        if new_groups:
            hooks[event] = new_groups
        elif event in hooks:
            del hooks[event]
            changed = True

    if not hooks:
        settings.pop("hooks", None)

    if changed:
        save_json(path, settings)
    return changed


# --- Antigravity Hooks ---

def antigravity_hooks_installed(config: dict[str, Any]) -> bool:
    entry = config.get(ANTIGRAVITY_HOOK_KEY)
    if not isinstance(entry, dict) or entry.get("enabled") is False:
        return False
    for event in ("PreInvocation", "PostInvocation", "Stop"):
        handlers = entry.get(event, [])
        if any(isinstance(h, dict) and HOOK_COMMAND in str(h.get("command", "")) for h in handlers):
            return True
    return False


def install_antigravity_hooks(path: Path) -> bool:
    config = load_json(path)
    # Antigravity hooks command: execute refresh and return empty JSON object on stdout
    cmd = f"{HOOK_COMMAND} >/dev/null 2>&1 || true; echo '{{}}'"
    handler = {"type": "command", "command": cmd, "timeout": HOOK_TIMEOUT}

    target = {
        "enabled": True,
        "PreInvocation": [handler],
        "PostInvocation": [handler],
        "Stop": [handler]
    }

    if config.get(ANTIGRAVITY_HOOK_KEY) == target:
        return False

    config[ANTIGRAVITY_HOOK_KEY] = target
    save_json(path, config)
    return True


def remove_antigravity_hooks(path: Path) -> bool:
    config = load_json(path)
    if ANTIGRAVITY_HOOK_KEY in config:
        del config[ANTIGRAVITY_HOOK_KEY]
        save_json(path, config)
        return True
    return False


# --- Combined API ---

def get_status(claude_path: Path | None = None, agy_path: Path | None = None) -> dict[str, Any]:
    c_p = claude_path or default_claude_settings_path()
    a_p = agy_path or default_antigravity_hooks_path()
    c_inst = claude_hooks_installed(load_json(c_p))
    a_inst = antigravity_hooks_installed(load_json(a_p))
    return {
        "claudeInstalled": c_inst,
        "antigravityInstalled": a_inst,
        "installed": c_inst or a_inst,
        "allInstalled": c_inst and a_inst
    }


def install_all(claude_path: Path | None = None, agy_path: Path | None = None) -> dict[str, Any]:
    c_p = claude_path or default_claude_settings_path()
    a_p = agy_path or default_antigravity_hooks_path()
    c_changed = install_claude_hooks(c_p)
    a_changed = install_antigravity_hooks(a_p)
    return {
        "changed": c_changed or a_changed,
        "claudeChanged": c_changed,
        "antigravityChanged": a_changed,
        "installed": True
    }


def remove_all(claude_path: Path | None = None, agy_path: Path | None = None) -> dict[str, Any]:
    c_p = claude_path or default_claude_settings_path()
    a_p = agy_path or default_antigravity_hooks_path()
    c_changed = remove_claude_hooks(c_p)
    a_changed = remove_antigravity_hooks(a_p)
    return {
        "changed": c_changed or a_changed,
        "claudeChanged": c_changed,
        "antigravityChanged": a_changed,
        "installed": False
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage Live Refresh Hooks for Agent Hub")
    parser.add_argument("action", choices=["install", "remove", "status"])
    parser.add_argument("--agent", choices=["all", "claude", "antigravity"], default="all")
    parser.add_argument("--claude-path", default=None)
    parser.add_argument("--agy-path", default=None)
    args = parser.parse_args()

    c_path = Path(args.claude_path).expanduser() if args.claude_path else default_claude_settings_path()
    a_path = Path(args.agy_path).expanduser() if args.agy_path else default_antigravity_hooks_path()

    if args.action == "status":
        print(json.dumps(get_status(c_path, a_path), indent=2))
        return

    if args.action == "install":
        if args.agent == "claude":
            res = {"claudeInstalled": True, "changed": install_claude_hooks(c_path)}
        elif args.agent == "antigravity":
            res = {"antigravityInstalled": True, "changed": install_antigravity_hooks(a_path)}
        else:
            res = install_all(c_path, a_path)
        print(json.dumps(res, indent=2))
        return

    if args.action == "remove":
        if args.agent == "claude":
            res = {"claudeInstalled": False, "changed": remove_claude_hooks(c_path)}
        elif args.agent == "antigravity":
            res = {"antigravityInstalled": False, "changed": remove_antigravity_hooks(a_path)}
        else:
            res = remove_all(c_path, a_path)
        print(json.dumps(res, indent=2))
        return


if __name__ == "__main__":
    sys.exit(main() or 0)
