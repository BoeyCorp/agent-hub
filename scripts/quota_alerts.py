#!/usr/bin/env python3
"""Desktop alerts for quota limits with warning/critical levels that re-arm.

State is tracked per bucket (``agent|group|bucket``) as one of ``ok``,
``warning`` or ``critical`` (percent *left*, whichever way the UI displays it):

* Crossing into a worse level fires one notification; staying there does not.
* Dropping back to ``ok`` (a reset or top-up) re-arms the bucket, optionally
  announcing the recovery, so the next drop alerts again.
* Easing from ``critical`` to ``warning`` stays quiet but keeps the bucket armed
  for another escalation.
* Alerts for the same agent found in one pass are merged into one notification.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

STATE_FILE = "quota_alert_state.json"
LOCK_FILE = "quota_alert.lock"
LEVELS = {"ok": 0, "warning": 1, "critical": 2}
HYSTERESIS_PCT = 2.0
AGENT_NAMES = {"claude": "Claude Code", "antigravity": "Google Antigravity", "codex": "OpenAI Codex"}

Notifier = Callable[[str, str, str], None]


def level_for(left_pct: float, warn_pct: float, crit_pct: float, current: str = "ok") -> str:
    """Level for ``left_pct``; recovery needs a 2-point margin to avoid flapping."""
    if left_pct <= crit_pct:
        return "critical"
    if current == "critical" and left_pct <= crit_pct + HYSTERESIS_PCT:
        return "critical"
    if left_pct <= warn_pct:
        return "warning"
    if current != "ok" and left_pct <= warn_pct + HYSTERESIS_PCT:
        return "warning"
    return "ok"


def _prior_level(entry: Any) -> str:
    """Persisted level for a bucket; corrupt or unknown values count as ``ok``.

    ``ok`` means a bucket that is really low alerts again once, which is safer
    than silently skipping it.
    """
    level = entry.get("level") if isinstance(entry, dict) else None
    return level if isinstance(level, str) and level in LEVELS else "ok"


def bucket_left_pct(bucket: dict[str, Any]) -> float | None:
    pct = bucket.get("remainingPercent")
    if pct is None and bucket.get("remainingFraction") is not None:
        pct = float(bucket["remainingFraction"]) * 100.0
    try:
        return None if pct is None else float(pct)
    except (TypeError, ValueError):
        return None


def send_notification(urgency: str, headline: str, details: str) -> None:
    """Deliver via Omarchy's notifier, falling back to notify-send."""
    candidates = []
    if shutil.which("omarchy-notification-send"):
        candidates.append(["omarchy-notification-send", "--app-name", "agent-hub", "-u", urgency,
                           "-g", "󰚩", headline, details])
    if shutil.which("notify-send"):
        candidates.append(["notify-send", "-a", "agent-hub", "-u", urgency, headline, details])
    for cmd in candidates:
        try:
            if subprocess.run(cmd, capture_output=True, timeout=4).returncode == 0:
                return
        except Exception:
            continue


def check_alerts(
    cache_dir: Path,
    groups_by_agent: dict[str, list[dict[str, Any]]],
    warn_pct: float = 25,
    crit_pct: float = 10,
    notify_replenish: bool = True,
    notifier: Notifier | None = None,
    now: float | None = None,
) -> list[dict[str, str]]:
    """Evaluate every bucket, send notifications, and return what was sent."""
    import fcntl

    notifier = notifier or send_notification
    now = time.time() if now is None else now
    if crit_pct > warn_pct:
        crit_pct = warn_pct
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    lock_fd = None
    try:
        lock_fd = open(cache_dir / LOCK_FILE, "w")
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (BlockingIOError, OSError):
        if lock_fd:
            lock_fd.close()
        return []

    sent: list[dict[str, str]] = []
    try:
        state: dict[str, dict[str, Any]] = {}
        try:
            with open(cache_dir / STATE_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                state = loaded
        except Exception:
            state = {}

        for agent_id, groups in groups_by_agent.items():
            worsened: list[tuple[str, float, str]] = []
            recovered: list[str] = []
            for group in groups or []:
                for bucket in group.get("buckets") or []:
                    left = bucket_left_pct(bucket)
                    if left is None:
                        continue
                    label = bucket.get("label") or bucket.get("name") or "Limit"
                    key = f"{agent_id}|{group.get('name', '')}|{bucket.get('id', '')}"
                    prev = _prior_level(state.get(key))
                    new = level_for(left, warn_pct, crit_pct, prev)
                    if LEVELS[new] > LEVELS[prev]:
                        worsened.append((label, left, new))
                    elif new == "ok" and prev != "ok":
                        recovered.append(label)
                    state[key] = {"level": new, "left": round(left, 1), "at": now}

            name = AGENT_NAMES.get(agent_id, agent_id)
            if worsened:
                worst = min(w[1] for w in worsened)
                critical = any(w[2] == "critical" for w in worsened)
                headline = f"{name} quota {'critical' if critical else 'low'} ({int(round(worst))}% left)"
                details = ", ".join(f"{lbl} ({int(round(pct))}% left)" for lbl, pct, _ in worsened)
                urgency = "critical" if critical else "normal"
                notifier(urgency, headline, details)
                sent.append({"agent": agent_id, "kind": "low", "headline": headline, "details": details})
            if recovered and notify_replenish:
                headline = f"{name} quota replenished"
                details = ", ".join(recovered) + " reset and ready to use."
                notifier("normal", headline, details)
                sent.append({"agent": agent_id, "kind": "recovered", "headline": headline, "details": details})

        try:
            tmp = cache_dir / (STATE_FILE + ".tmp")
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(state, f, indent=2)
            tmp.replace(cache_dir / STATE_FILE)
        except Exception:
            pass
    finally:
        try:
            fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
            lock_fd.close()
        except Exception:
            pass
    return sent
