#!/usr/bin/env python3
"""Turn quota-collector failures into actionable, per-agent status for the UI.

``derive_status`` returns a dict with:

``state``    ``ok`` | ``signin`` | ``expired`` | ``rateLimited`` | ``offline`` | ``error``
``reason``   a few characters for the bar chip (``sign in``, ``rate limited`` ...)
``message``  what is wrong and what to do about it
``command``  argv of the command that fixes it (empty when nothing to run)
``stale``    True when old limits are still shown despite the failure
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

AGENT_LABELS = {"claude": "Claude Code", "antigravity": "Google Antigravity", "codex": "OpenAI Codex"}
SIGN_IN_COMMANDS = {
    "claude": ["claude", "auth", "login"],
    "antigravity": ["agy"],
    "codex": ["codex", "login"],
}
BACKOFF_FILES = {
    "claude": "claude_usage_quota_backoff.json",
    "antigravity": "quota_backoff.json",
}
FAILURE_WINDOW_S = 30 * 60

_EXPIRED = re.compile(r"expired|re-?authenticate|refresh token", re.I)
_RATE = re.compile(r"\b429\b|rate.?limit|too many requests|throttl", re.I)
_OFFLINE = re.compile(r"network|connection|resolve|timed out|timeout|unreachable|offline|ssl|dns|temporary failure", re.I)
_SIGNIN = re.compile(r"not (logged|signed)|log ?in|sign ?in|credential|unauthori[sz]ed|\b40[13]\b|invalid.*token|authenticat|no .*token|auth", re.I)


def classify_error(text: str) -> str:
    """Map a collector error string to a status state."""
    text = text or ""
    if _EXPIRED.search(text):
        return "expired"
    if _RATE.search(text):
        return "rateLimited"
    if _OFFLINE.search(text):
        return "offline"
    if _SIGNIN.search(text):
        return "signin"
    return "error"


def read_failure(agent_id: str, base_dir: Path | None, now: float) -> dict[str, Any] | None:
    """Recent quota failure recorded by the agent's scanner, if any."""
    name = BACKOFF_FILES.get(agent_id)
    if not name or base_dir is None:
        return None
    try:
        with open(Path(base_dir) / "cache" / name, "r", encoding="utf-8") as f:
            data = json.load(f)
        if now - float(data.get("last_failure", 0)) <= FAILURE_WINDOW_S:
            return data
    except Exception:
        pass
    return None


def credentials_missing(agent_id: str, home: Path) -> bool:
    paths = {
        "claude": home / ".claude" / ".credentials.json",
        "codex": home / ".codex" / "auth.json",
    }
    path = paths.get(agent_id)
    return bool(path) and not path.exists()


def _ok() -> dict[str, Any]:
    return {"state": "ok", "reason": "", "message": "", "command": [], "commandText": "", "stale": False}


def derive_status(
    agent_id: str,
    has_groups: bool,
    base_dir: Path | None = None,
    home: Path | None = None,
    now: float | None = None,
    failure: dict[str, Any] | None = None,
) -> dict[str, Any]:
    now = time.time() if now is None else now
    home = home or Path.home()
    label = AGENT_LABELS.get(agent_id, agent_id)
    command = SIGN_IN_COMMANDS.get(agent_id, [])
    command_text = " ".join(command)

    failure = failure if failure is not None else read_failure(agent_id, base_dir, now)
    state = "ok"
    error_text = ""
    retry_in = 0.0
    if failure:
        error_text = str(failure.get("last_error") or "")
        state = classify_error(error_text)
        retry_in = max(0.0, float(failure.get("next_allowed", 0)) - now)
    elif not has_groups and credentials_missing(agent_id, home):
        state = "signin"

    if state == "ok":
        return _ok()

    if state == "signin":
        reason = "sign in"
        message = f"Not signed in to {label}. Run `{command_text}` to see its limits."
    elif state == "expired":
        reason = "sign-in expired"
        message = f"{label} sign-in expired. Run `{command_text}` to renew it."
    elif state == "rateLimited":
        reason = "rate limited"
        wait = f" Retrying in {int(retry_in)}s." if retry_in >= 1 else " Retrying automatically."
        message = f"{label} is rate limiting quota checks.{wait}"
    elif state == "offline":
        reason = "offline"
        message = f"Can't reach {label}'s usage service. Check your connection; retrying automatically."
    else:
        reason = "refresh failed"
        detail = re.sub(r"\s+", " ", error_text).strip()[:80]
        message = f"Could not refresh {label} limits" + (f": {detail}." if detail else ".") + " Retrying automatically."

    fixable = state in ("signin", "expired")
    return {
        "state": state,
        "reason": reason,
        "message": message,
        "command": command if fixable else [],
        "commandText": command_text if fixable else "",
        "stale": bool(has_groups),
    }
