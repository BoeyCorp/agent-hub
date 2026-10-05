#!/usr/bin/env python3
"""Unified Agent Hub Scanner.

Runs Claude Code and Antigravity scanners concurrently, aggregating session,
prompt, token, tool, and quota telemetry into a unified contract for the
Omarchy Agent Hub bar widget.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

# Ensure script directory is on path for provider scanner imports
SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

try:
    import claude_scanner
    import antigravity_scanner
except ImportError:
    from scripts import claude_scanner, antigravity_scanner


def default_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "agent-hub"


def sanitize_plain_text(val: Any, max_len: int = 250) -> str:
    if val is None:
        return ""
    import re
    text = str(val)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


def annotate_sessions(sessions: list[dict[str, Any]], agent_id: str, agent_name: str, agent_color: str, agent_icon: str) -> list[dict[str, Any]]:
    annotated = []
    for s in sessions:
        item = dict(s)
        item["agentId"] = agent_id
        item["agentName"] = agent_name
        item["agentColor"] = agent_color
        item["agentIcon"] = agent_icon
        annotated.append(item)
    return annotated


def normalize_combined_tools(claude_tools: dict[str, int], antigravity_tools: dict[str, int]) -> dict[str, int]:
    """Combine and normalize tool executions across both Claude Code and Antigravity."""
    norm = {
        "Terminal / Commands": claude_tools.get("Bash", 0) + antigravity_tools.get("run_command", 0),
        "File Viewing / Reading": claude_tools.get("Read", 0) + antigravity_tools.get("view_file", 0),
        "File Editing": claude_tools.get("Edit", 0) + antigravity_tools.get("replace_file_content", 0),
        "File Writing": claude_tools.get("Write", 0) + antigravity_tools.get("write_to_file", 0),
        "Code & File Search": claude_tools.get("Grep", 0) + claude_tools.get("Glob", 0) + antigravity_tools.get("grep_search", 0) + antigravity_tools.get("find_by_name", 0),
        "Subagents & Tasks": claude_tools.get("Agent", 0) + claude_tools.get("Task", 0) + antigravity_tools.get("invoke_subagent", 0) + antigravity_tools.get("manage_task", 0),
        "Web & Online Search": claude_tools.get("WebFetch", 0) + claude_tools.get("WebSearch", 0) + antigravity_tools.get("search_web", 0) + antigravity_tools.get("read_url_content", 0),
    }
    # Add any extra specific tools that have notable usage (> 0)
    for k, v in claude_tools.items():
        if k not in ("Bash", "Read", "Edit", "Write", "Grep", "Glob", "Agent", "Task", "WebFetch", "WebSearch"):
            norm[f"Claude: {k}"] = v
    for k, v in antigravity_tools.items():
        if k not in ("run_command", "view_file", "replace_file_content", "write_to_file", "grep_search", "find_by_name", "invoke_subagent", "manage_task", "search_web", "read_url_content"):
            norm[f"Antigravity: {k}"] = v

    # Sort descending and filter zeroes
    return {k: v for k, v in sorted(norm.items(), key=lambda x: x[1], reverse=True) if v > 0}


def merge_recent_days(days_a: list[dict[str, Any]], days_b: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for d in days_a:
        date = d.get("date", "")
        if not date:
            continue
        merged[date] = {
            "date": date,
            "messageCount": int(d.get("messageCount") or d.get("prompts") or 0),
            "prompts": int(d.get("prompts", 0)),
            "steps": int(d.get("steps", 0))
        }
    for d in days_b:
        date = d.get("date", "")
        if not date:
            continue
        p = int(d.get("messageCount") or d.get("prompts") or 0)
        s = int(d.get("steps", 0))
        if date in merged:
            merged[date]["messageCount"] += p
            merged[date]["prompts"] += p
            merged[date]["steps"] += s
        else:
            merged[date] = {
                "date": date,
                "messageCount": p,
                "prompts": p,
                "steps": s
            }
    # Sort by date ascending
    return [merged[k] for k in sorted(merged.keys())]


def scan_hub(
    enable_claude: bool = True,
    enable_antigravity: bool = True,
    force: bool = False,
    alert_threshold: int | None = None
) -> dict[str, Any]:
    cache_dir = default_cache_dir()
    cache_file = cache_dir / "hub_scanner_cache.json"

    # Multi-monitor scan deduplication (TTL: 1.5s)
    if not force and cache_file.exists():
        try:
            mtime = cache_file.stat().st_mtime
            if time.time() - mtime < 1.5:
                with open(cache_file, "r", encoding="utf-8") as f:
                    cached = json.load(f)
                    if isinstance(cached, dict) and cached.get("ready"):
                        return cached
        except Exception:
            pass

    claude_data: dict[str, Any] = {}
    antigravity_data: dict[str, Any] = {}

    def fetch_claude():
        try:
            return claude_scanner.scan(claude_scanner.default_base_dir(), force=force, alert_threshold=alert_threshold)
        except Exception as e:
            empty = claude_scanner.empty_result()
            empty["usageStatusText"] = f"Error: {e}"
            return empty

    def fetch_antigravity():
        try:
            return antigravity_scanner.scan(antigravity_scanner.default_base_dir(), force=force, alert_threshold=alert_threshold)
        except Exception as e:
            empty = antigravity_scanner.empty_result()
            empty["usageStatusText"] = f"Error: {e}"
            return empty

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f_claude = executor.submit(fetch_claude) if enable_claude else None
        f_agy = executor.submit(fetch_antigravity) if enable_antigravity else None

        if f_claude:
            claude_data = f_claude.result()
        else:
            claude_data = claude_scanner.empty_result()

        if f_agy:
            antigravity_data = f_agy.result()
        else:
            antigravity_data = antigravity_scanner.empty_result()

    # Determine overall activity state
    claude_active = bool(claude_data.get("hasActiveSession", False))
    claude_working = claude_data.get("activeStatus") == "Working"
    agy_active = bool(antigravity_data.get("hasActiveSession", False))
    agy_working = antigravity_data.get("activeStatus") == "Working"

    has_active = claude_active or agy_active
    if claude_working or agy_working:
        overall_status = "Working"
    elif has_active:
        overall_status = "Waiting"
    else:
        overall_status = "Idle"

    # Annotate active sessions with agent branding
    c_active_sessions = annotate_sessions(
        claude_data.get("activeSessions", []),
        agent_id="claude",
        agent_name="Claude Code",
        agent_color="#D97757",
        agent_icon="assets/claude.svg"
    )
    a_active_sessions = annotate_sessions(
        antigravity_data.get("activeSessions", []),
        agent_id="antigravity",
        agent_name="Antigravity",
        agent_color="#38BDF8",
        agent_icon="assets/antigravity.svg"
    )
    active_sessions = c_active_sessions + a_active_sessions

    # Annotate and merge recent sessions
    c_recent_sessions = annotate_sessions(
        claude_data.get("recentSessions", []),
        agent_id="claude",
        agent_name="Claude Code",
        agent_color="#D97757",
        agent_icon="assets/claude.svg"
    )
    a_recent_sessions = annotate_sessions(
        antigravity_data.get("recentSessions", []),
        agent_id="antigravity",
        agent_name="Antigravity",
        agent_color="#38BDF8",
        agent_icon="assets/antigravity.svg"
    )

    # Sort active first, then by lastModified / timestamp descending
    def session_sort_key(s: dict[str, Any]) -> tuple[int, float]:
        is_act = 1 if s.get("isActive") else 0
        ts = s.get("timestamp") or 0.0
        lm = s.get("lastModified") or ""
        if lm:
            try:
                dt_obj = dt.datetime.fromisoformat(lm.replace("Z", "+00:00"))
                ts = max(ts, dt_obj.timestamp())
            except Exception:
                pass
        return (is_act, ts)

    c_recent_sessions.sort(key=session_sort_key, reverse=True)
    a_recent_sessions.sort(key=session_sort_key, reverse=True)

    claude_data["activeSessions"] = c_active_sessions
    claude_data["recentSessions"] = c_recent_sessions
    antigravity_data["activeSessions"] = a_active_sessions
    antigravity_data["recentSessions"] = a_recent_sessions

    all_recent = c_recent_sessions + a_recent_sessions
    all_recent.sort(key=session_sort_key, reverse=True)

    # Combined totals
    today_prompts = int(claude_data.get("todayPrompts", 0)) + int(antigravity_data.get("todayPrompts", 0))
    today_steps = int(claude_data.get("todaySteps", 0)) + int(antigravity_data.get("todaySteps", 0))
    today_tokens = int(claude_data.get("todayTotalTokens", 0)) + int(antigravity_data.get("todayTotalTokens", 0))
    today_sessions = int(claude_data.get("todaySessions", 0)) + int(antigravity_data.get("todaySessions", 0))

    total_prompts = int(claude_data.get("totalPrompts", 0)) + int(antigravity_data.get("totalPrompts", 0))
    total_steps = int(claude_data.get("totalSteps", 0)) + int(antigravity_data.get("totalSteps", 0))
    total_sessions = int(claude_data.get("totalSessions", 0)) + int(antigravity_data.get("totalSessions", 0))

    # Quota groups consolidation
    quota_groups = list(claude_data.get("quotaGroups", [])) + list(antigravity_data.get("quotaGroups", []))

    # Normalized tools
    tool_usage = normalize_combined_tools(
        claude_data.get("toolUsage", {}),
        antigravity_data.get("toolUsage", {})
    )

    # Merged 7-day activity
    recent_days = merge_recent_days(
        claude_data.get("recentDays", []),
        antigravity_data.get("recentDays", [])
    )

    now_iso = dt.datetime.now(dt.timezone.utc).isoformat()
    now_ms = int(time.time() * 1000)

    # Determine status text
    claude_m = claude_data.get("currentModel") or "Claude"
    agy_m = antigravity_data.get("currentModel") or "Gemini"
    status_text = f"{overall_status} • {claude_m} / {agy_m}" if has_active else f"Idle • {claude_m} / {agy_m}"

    result = {
        "schemaVersion": 1,
        "id": "agent-hub",
        "name": "Agent Hub",
        "ready": bool(claude_data.get("ready") or antigravity_data.get("ready")),
        "active": has_active,
        "activeStatus": overall_status,
        "hasActiveSession": has_active,
        "todayPrompts": today_prompts,
        "todaySteps": today_steps,
        "todaySessions": today_sessions,
        "todayTotalTokens": today_tokens,
        "todayTokensByAgent": {
            "claude": int(claude_data.get("todayTotalTokens", 0)),
            "antigravity": int(antigravity_data.get("todayTotalTokens", 0))
        },
        "activeAgentCounts": {
            "claude": len(c_active_sessions),
            "antigravity": len(a_active_sessions)
        },
        "totalPrompts": total_prompts,
        "totalSteps": total_steps,
        "totalSessions": total_sessions,
        "activeSessions": active_sessions,
        "recentSessions": all_recent[:15],
        "quotaGroups": quota_groups,
        "toolUsage": tool_usage,
        "recentDays": recent_days,
        "providers": {
            "claude": claude_data,
            "antigravity": antigravity_data
        },
        "updatedAt": now_iso,
        "lastFullRefreshMs": max(
            int(claude_data.get("lastFullRefreshMs") or 0),
            int(antigravity_data.get("lastFullRefreshMs") or 0),
            now_ms
        ),
        "usageStatusText": status_text,
        "authHelpText": ""
    }

    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        tmp = cache_file.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(result, f)
        tmp.replace(cache_file)
    except Exception:
        pass

    return result


def kill_session_by_agent(agent_target: str, session_id: str) -> bool:
    """Kill session on specified agent ('claude' or 'antigravity')."""
    if agent_target == "claude":
        return claude_scanner.kill_session(session_id, claude_scanner.default_base_dir())
    elif agent_target == "antigravity":
        return antigravity_scanner.kill_session(session_id, antigravity_scanner.default_base_dir())
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Unified Agent Hub Scanner")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--force", action="store_true", help="Bypass cache and force refresh")
    parser.add_argument("--kill", type=str, default=None, help="Kill session format: '<agent>:<session_id>'")
    parser.add_argument("--claude-only", action="store_true", help="Only scan Claude Code")
    parser.add_argument("--antigravity-only", action="store_true", help="Only scan Antigravity")
    parser.add_argument("--notify-low-quota", type=int, nargs="?", const=15, default=None, help="Run quota alert check")
    args = parser.parse_args()

    if args.kill:
        parts = args.kill.split(":", 1)
        if len(parts) == 2:
            agent_id, sid = parts[0].strip().lower(), parts[1].strip()
            success = kill_session_by_agent(agent_id, sid)
            print(json.dumps({"success": success, "agent": agent_id, "conversationId": sid}))
            return
        print(json.dumps({"success": False, "error": "Invalid kill format. Expected '<agent>:<session_id>'"}))
        return

    enable_claude = not args.antigravity_only
    enable_antigravity = not args.claude_only

    result = scan_hub(
        enable_claude=enable_claude,
        enable_antigravity=enable_antigravity,
        force=args.force,
        alert_threshold=args.notify_low_quota
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
