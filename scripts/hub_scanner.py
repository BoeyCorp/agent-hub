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
    import codex_scanner
except ImportError:
    from scripts import claude_scanner, antigravity_scanner, codex_scanner


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


def group_session_hierarchy(sessions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Group subagent sessions hierarchically directly under their parent sessions."""
    if not sessions:
        return []

    by_id = {s["conversationId"]: s for s in sessions if s.get("conversationId")}
    parent_to_children: dict[str, list[dict[str, Any]]] = {}
    standalone: list[dict[str, Any]] = []

    for s in sessions:
        parent_id = s.get("parentConversationId")
        if s.get("isSubagent") and parent_id and parent_id in by_id:
            parent_to_children.setdefault(parent_id, []).append(s)
        else:
            standalone.append(s)

    result: list[dict[str, Any]] = []
    for s in standalone:
        result.append(s)
        cid = s.get("conversationId")
        if cid and cid in parent_to_children:
            for child in parent_to_children[cid]:
                child_copy = dict(child)
                child_copy["indent"] = 1
                child_copy["isSubagent"] = True
                result.append(child_copy)

    return result


def normalize_combined_tools(claude_tools: dict[str, int], antigravity_tools: dict[str, int], codex_tools: dict[str, int] | None = None) -> dict[str, int]:
    """Combine and normalize tool executions across Claude Code, Antigravity, and Codex."""
    cx = codex_tools or {}
    norm = {
        "Terminal / Commands": claude_tools.get("Bash", 0) + antigravity_tools.get("run_command", 0) + cx.get("bash", 0) + cx.get("exec_command", 0),
        "File Viewing / Reading": claude_tools.get("Read", 0) + antigravity_tools.get("view_file", 0) + cx.get("read_file", 0) + cx.get("view_file", 0),
        "File Editing": claude_tools.get("Edit", 0) + antigravity_tools.get("replace_file_content", 0) + cx.get("edit_file", 0) + cx.get("patch_file", 0),
        "File Writing": claude_tools.get("Write", 0) + antigravity_tools.get("write_to_file", 0) + cx.get("write_file", 0),
        "Code & File Search": claude_tools.get("Grep", 0) + claude_tools.get("Glob", 0) + antigravity_tools.get("grep_search", 0) + antigravity_tools.get("find_by_name", 0) + cx.get("file_search", 0) + cx.get("grep", 0),
        "Subagents & Tasks": claude_tools.get("Agent", 0) + claude_tools.get("Task", 0) + antigravity_tools.get("invoke_subagent", 0) + antigravity_tools.get("manage_task", 0),
        "Web & Online Search": claude_tools.get("WebFetch", 0) + claude_tools.get("WebSearch", 0) + antigravity_tools.get("search_web", 0) + antigravity_tools.get("read_url_content", 0) + cx.get("web_search", 0),
    }
    # Add any extra specific tools that have notable usage (> 0)
    for k, v in claude_tools.items():
        if k not in ("Bash", "Read", "Edit", "Write", "Grep", "Glob", "Agent", "Task", "WebFetch", "WebSearch"):
            norm[f"Claude: {k}"] = v
    for k, v in antigravity_tools.items():
        if k not in ("run_command", "view_file", "replace_file_content", "write_to_file", "grep_search", "find_by_name", "invoke_subagent", "manage_task", "search_web", "read_url_content"):
            norm[f"Antigravity: {k}"] = v
    for k, v in cx.items():
        if k not in ("bash", "exec_command", "read_file", "view_file", "edit_file", "patch_file", "write_file", "file_search", "grep", "web_search"):
            norm[f"Codex: {k}"] = v

    # Sort descending and filter zeroes
    return {k: v for k, v in sorted(norm.items(), key=lambda x: x[1], reverse=True) if v > 0}


def merge_recent_days(*day_lists: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for d_list in day_lists:
        for d in (d_list or []):
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
    enable_codex: bool = True,
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
    codex_data: dict[str, Any] = {}

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

    def fetch_codex():
        try:
            return codex_scanner.scan(codex_scanner.default_base_dir(), force=force)
        except Exception as e:
            empty = codex_scanner.empty_result()
            empty["usageStatusText"] = f"Error: {e}"
            return empty

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        f_claude = executor.submit(fetch_claude) if enable_claude else None
        f_agy = executor.submit(fetch_antigravity) if enable_antigravity else None
        f_codex = executor.submit(fetch_codex) if enable_codex else None

        if f_claude:
            claude_data = f_claude.result()
        else:
            claude_data = claude_scanner.empty_result()

        if f_agy:
            antigravity_data = f_agy.result()
        else:
            antigravity_data = antigravity_scanner.empty_result()

        if f_codex:
            codex_data = f_codex.result()
        else:
            codex_data = codex_scanner.empty_result()

    # Ensure todayTokenCost is always populated for each provider
    for a_data, cost_func, def_model in [
        (claude_data, claude_scanner.estimate_claude_token_cost, "Claude (Default)"),
        (antigravity_data, antigravity_scanner.estimate_antigravity_token_cost, "Gemini 3.8 Flash (High)"),
        (codex_data, codex_scanner.estimate_codex_token_cost, "GPT-6 Luna"),
    ]:
        if "todayTokenCost" not in a_data or a_data.get("todayTokenCost") is None or (a_data.get("todayTokenCost") == 0.0 and int(a_data.get("todayTotalTokens", 0)) > 0):
            tok = int(a_data.get("todayTotalTokens", 0))
            if tok > 0:
                inp = int(a_data.get("todayInputTokens", 0))
                out = int(a_data.get("todayOutputTokens", 0))
                cread = int(a_data.get("todayCacheReadTokens", 0))
                cwrite = int(a_data.get("todayCacheCreationTokens", 0))
                if inp == 0 and out == 0:
                    inp, out = int(tok * 0.8), int(tok * 0.2)
                try:
                    c = cost_func(a_data.get("currentModel", def_model), inp, out, cread, cwrite)
                except TypeError:
                    c = cost_func(a_data.get("currentModel", def_model), inp, out, cread)
                a_data["todayTokenCost"] = round(c, 2)
            else:
                a_data["todayTokenCost"] = 0.0

    # Determine overall activity state
    claude_active = bool(claude_data.get("hasActiveSession", False))
    claude_working = claude_data.get("activeStatus") == "Working"
    agy_active = bool(antigravity_data.get("hasActiveSession", False))
    agy_working = antigravity_data.get("activeStatus") == "Working"
    codex_active = bool(codex_data.get("hasActiveSession", False))
    codex_working = codex_data.get("activeStatus") == "Working"

    has_active = claude_active or agy_active or codex_active
    if claude_working or agy_working or codex_working:
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
    x_active_sessions = annotate_sessions(
        codex_data.get("activeSessions", []),
        agent_id="codex",
        agent_name="Codex",
        agent_color="#10A37F",
        agent_icon="assets/codex.svg"
    )
    active_sessions = c_active_sessions + a_active_sessions + x_active_sessions

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
    x_recent_sessions = annotate_sessions(
        codex_data.get("recentSessions", []),
        agent_id="codex",
        agent_name="Codex",
        agent_color="#10A37F",
        agent_icon="assets/codex.svg"
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
    x_recent_sessions.sort(key=session_sort_key, reverse=True)

    claude_data["activeSessions"] = c_active_sessions
    claude_data["recentSessions"] = c_recent_sessions
    antigravity_data["activeSessions"] = a_active_sessions
    antigravity_data["recentSessions"] = a_recent_sessions
    codex_data["activeSessions"] = x_active_sessions
    codex_data["recentSessions"] = x_recent_sessions

    all_recent = c_recent_sessions + a_recent_sessions + x_recent_sessions
    all_recent.sort(key=session_sort_key, reverse=True)
    all_recent = group_session_hierarchy(all_recent)

    # Combined totals
    today_prompts = int(claude_data.get("todayPrompts", 0)) + int(antigravity_data.get("todayPrompts", 0)) + int(codex_data.get("todayPrompts", 0))
    today_steps = int(claude_data.get("todaySteps", 0)) + int(antigravity_data.get("todaySteps", 0)) + int(codex_data.get("todaySteps", 0))
    today_tokens = int(claude_data.get("todayTotalTokens", 0)) + int(antigravity_data.get("todayTotalTokens", 0)) + int(codex_data.get("todayTotalTokens", 0))
    today_sessions = int(claude_data.get("todaySessions", 0)) + int(antigravity_data.get("todaySessions", 0)) + int(codex_data.get("todaySessions", 0))
    today_token_cost = round(
        float(claude_data.get("todayTokenCost", 0.0))
        + float(antigravity_data.get("todayTokenCost", 0.0))
        + float(codex_data.get("todayTokenCost", 0.0)),
        2
    )

    # Combined prompt cache metrics
    c_cache_read = int(claude_data.get("todayCacheReadTokens", 0))
    c_cache_create = int(claude_data.get("todayCacheCreationTokens", 0))
    c_input = int(claude_data.get("todayInputTokens", 0))
    c_output = int(claude_data.get("todayOutputTokens", 0))

    a_cache_read = int(antigravity_data.get("todayCacheReadTokens", 0))
    a_input = int(antigravity_data.get("todayInputTokens", 0))
    a_output = int(antigravity_data.get("todayOutputTokens", 0))

    x_cache_read = int(codex_data.get("todayCacheReadTokens", 0))
    x_input = int(codex_data.get("todayInputTokens", 0))
    x_output = int(codex_data.get("todayOutputTokens", 0))

    today_cache_read = c_cache_read + a_cache_read + x_cache_read
    today_cache_create = c_cache_create
    today_input = c_input + a_input + x_input
    today_output = c_output + a_output + x_output

    cache_denom = today_cache_read + today_cache_create + today_input
    today_cache_hit_rate = round((today_cache_read / cache_denom) * 100.0, 1) if cache_denom > 0 else 0.0

    total_prompts = int(claude_data.get("totalPrompts", 0)) + int(antigravity_data.get("totalPrompts", 0)) + int(codex_data.get("totalPrompts", 0))
    total_steps = int(claude_data.get("totalSteps", 0)) + int(antigravity_data.get("totalSteps", 0)) + int(codex_data.get("totalSteps", 0))
    total_sessions = int(claude_data.get("totalSessions", 0)) + int(antigravity_data.get("totalSessions", 0)) + int(codex_data.get("totalSessions", 0))

    # Quota groups consolidation
    quota_groups = list(claude_data.get("quotaGroups", [])) + list(antigravity_data.get("quotaGroups", [])) + list(codex_data.get("quotaGroups", []))

    # Normalized tools
    tool_usage = normalize_combined_tools(
        claude_data.get("toolUsage", {}),
        antigravity_data.get("toolUsage", {}),
        codex_data.get("toolUsage", {})
    )

    # Merged 7-day activity
    recent_days = merge_recent_days(
        claude_data.get("recentDays", []),
        antigravity_data.get("recentDays", []),
        codex_data.get("recentDays", [])
    )

    now_iso = dt.datetime.now(dt.timezone.utc).isoformat()
    now_ms = int(time.time() * 1000)

    # Determine status text
    status_text = overall_status if has_active else "Idle"

    result = {
        "schemaVersion": 1,
        "id": "agent-hub",
        "name": "Agent Hub",
        "ready": bool(claude_data.get("ready") or antigravity_data.get("ready") or codex_data.get("ready")),
        "active": has_active,
        "activeStatus": overall_status,
        "hasActiveSession": has_active,
        "todayPrompts": today_prompts,
        "todaySteps": today_steps,
        "todaySessions": today_sessions,
        "todayTotalTokens": today_tokens,
        "todayTokenCost": today_token_cost,
        "todayTokenCostByAgent": {
            "claude": float(claude_data.get("todayTokenCost", 0.0)),
            "antigravity": float(antigravity_data.get("todayTokenCost", 0.0)),
            "codex": float(codex_data.get("todayTokenCost", 0.0))
        },
        "todayCacheReadTokens": today_cache_read,
        "todayCacheCreationTokens": today_cache_create,
        "todayInputTokens": today_input,
        "todayOutputTokens": today_output,
        "todayCacheHitRate": today_cache_hit_rate,
        "todayTokensByAgent": {
            "claude": int(claude_data.get("todayTotalTokens", 0)),
            "antigravity": int(antigravity_data.get("todayTotalTokens", 0)),
            "codex": int(codex_data.get("todayTotalTokens", 0))
        },
        "activeAgentCounts": {
            "claude": len(c_active_sessions),
            "antigravity": len(a_active_sessions),
            "codex": len(x_active_sessions)
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
            "antigravity": antigravity_data,
            "codex": codex_data
        },
        "codexData": codex_data,
        "updatedAt": now_iso,
        "lastFullRefreshMs": max(
            int(claude_data.get("lastFullRefreshMs") or 0),
            int(antigravity_data.get("lastFullRefreshMs") or 0),
            int(codex_data.get("lastFullRefreshMs") or 0),
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
    """Kill session on specified agent ('claude', 'antigravity', or 'codex')."""
    if agent_target == "claude":
        return claude_scanner.kill_session(session_id, claude_scanner.default_base_dir())
    elif agent_target == "antigravity":
        return antigravity_scanner.kill_session(session_id, antigravity_scanner.default_base_dir())
    elif agent_target == "codex":
        return codex_scanner.kill_session(session_id, codex_scanner.default_base_dir())
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Unified Agent Hub Scanner")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--force", action="store_true", help="Bypass cache and force refresh")
    parser.add_argument("--kill", type=str, default=None, help="Kill session format: '<agent>:<session_id>'")
    parser.add_argument("--claude-only", action="store_true", help="Only scan Claude Code")
    parser.add_argument("--antigravity-only", action="store_true", help="Only scan Antigravity")
    parser.add_argument("--codex-only", action="store_true", help="Only scan Codex")
    parser.add_argument("--no-claude", action="store_true", help="Disable Claude Code scan")
    parser.add_argument("--no-antigravity", action="store_true", help="Disable Antigravity scan")
    parser.add_argument("--no-codex", action="store_true", help="Disable Codex scan")
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

    if args.claude_only:
        enable_claude = True
        enable_antigravity = False
        enable_codex = False
    elif args.antigravity_only:
        enable_claude = False
        enable_antigravity = True
        enable_codex = False
    elif args.codex_only:
        enable_claude = False
        enable_antigravity = False
        enable_codex = True
    else:
        enable_claude = not args.no_claude
        enable_antigravity = not args.no_antigravity
        enable_codex = not args.no_codex

    result = scan_hub(
        enable_claude=enable_claude,
        enable_antigravity=enable_antigravity,
        enable_codex=enable_codex,
        force=args.force,
        alert_threshold=args.notify_low_quota
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
