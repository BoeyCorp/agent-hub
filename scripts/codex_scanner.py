#!/usr/bin/env python3
"""Query Codex local state, history, session transcripts, and app-server rate limits."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import select
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path
from typing import Any


def default_base_dir() -> Path:
    return Path(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"))


def expand_path(value: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def date_string(value: dt.date) -> str:
    return value.strftime("%Y-%m-%d")


def sanitize_plain_text(val: Any, max_len: int = 250) -> str:
    if val is None:
        return ""
    text = str(val)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


def recent_date_strings() -> list[str]:
    today = dt.datetime.now().date()
    return [date_string(today - dt.timedelta(days=offset)) for offset in range(6, -1, -1)]


_MS_EPOCH_THRESHOLD = 10_000_000_000


def normalize_timestamp_seconds(value: Any) -> float:
    if value is None:
        return 0.0
    try:
        v = float(value)
        return v / 1000.0 if v > _MS_EPOCH_THRESHOLD else v
    except (TypeError, ValueError):
        return 0.0


def local_date_from_timestamp(value: Any) -> str:
    if value is None:
        return date_string(dt.datetime.now().date())
    if isinstance(value, (int, float)):
        try:
            seconds = normalize_timestamp_seconds(value)
            return date_string(dt.datetime.fromtimestamp(seconds).date())
        except Exception:
            return date_string(dt.datetime.now().date())
    raw = str(value).strip()
    if not raw:
        return date_string(dt.datetime.now().date())
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone()
        return date_string(parsed.date())
    except Exception:
        pass
    try:
        clean = raw.split(".")[0]
        parsed = dt.datetime.fromisoformat(clean)
        return date_string(parsed.date())
    except Exception:
        return date_string(dt.datetime.now().date())


def empty_result() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "id": "codex",
        "name": "Codex",
        "ready": False,
        "active": False,
        "activeStatus": "Idle",
        "hasActiveSession": False,
        "hasLocalStats": False,
        "tierLabel": "OpenAI Codex",
        "currentModel": "GPT-6 Luna",
        "todayPrompts": 0,
        "todaySessions": 0,
        "todaySteps": 0,
        "todayTotalTokens": 0,
        "todayTokensByModel": {},
        "todayCacheReadTokens": 0,
        "todayCacheCreationTokens": 0,
        "todayInputTokens": 0,
        "todayOutputTokens": 0,
        "todayCacheHitRate": 0.0,
        "recentDays": [],
        "totalPrompts": 0,
        "totalSessions": 0,
        "totalSteps": 0,
        "activeSessions": [],
        "recentSessions": [],
        "toolUsage": {},
        "modelUsage": {},
        "modelList": [],
        "quotaGroups": [],
        "limits": [],
        "recentWorkspaces": [],
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "quotaUpdatedAt": "",
        "quotaUpdatedMs": 0,
        "lastFullRefreshMs": 0,
        "usageStatusText": "No Codex data found",
        "authHelpText": "Run `codex login` to authenticate."
    }


def clean_model_display_name(model_id: str) -> str:
    if not model_id or not isinstance(model_id, str):
        return "GPT-6 Luna"
    m = model_id.strip()
    name_map = {
        "gpt-6-luna": "GPT-6 Luna",
        "gpt-6": "GPT-6",
        "gpt-5.6-terra": "GPT-5.6 Terra",
        "gpt-5.6-luna": "GPT-5.6 Luna",
        "gpt-5.5": "GPT-5.5",
        "gpt-5": "GPT-5",
        "o3": "OpenAI o3",
        "o3-mini": "OpenAI o3-mini",
        "o1": "OpenAI o1",
        "o1-mini": "OpenAI o1-mini",
        "gpt-4o": "GPT-4o",
        "gpt-4o-mini": "GPT-4o Mini",
        "codex": "Codex",
    }
    low = m.lower()
    if low in name_map:
        return name_map[low]
    # General cleanup
    parts = m.replace("-", " ").replace("_", " ").split()
    return " ".join(p.capitalize() for p in parts)


def get_model_color(model_name: str) -> str:
    low = model_name.lower()
    if "gpt-6" in low or "luna" in low:
        return "#10A37F"  # OpenAI Emerald
    elif "terra" in low or "5.6" in low:
        return "#0EA5E9"  # Cyan/Blue
    elif "5.5" in low or "gpt-5" in low:
        return "#8B5CF6"  # Purple
    elif "o3" in low or "o1" in low:
        return "#F59E0B"  # Amber
    return "#10A37F"


def check_active_lock_threads(base_dir: Path) -> dict[str, int]:
    """Inspect thread-writer-locks for held file locks, returning {thread_id: pid}."""
    locks_dir = base_dir / "thread-writer-locks"
    active_map: dict[str, int] = {}
    if not locks_dir.exists():
        return active_map

    for p in locks_dir.glob("*.lock"):
        if p.name.startswith("."):
            continue
        tid = p.stem
        try:
            with open(p, "r") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        except (BlockingIOError, OSError):
            # Lock is held! Find PID if possible via fuser
            pid = 0
            try:
                out = subprocess.check_output(["fuser", str(p)], stderr=subprocess.DEVNULL, text=True).strip()
                pids = [int(x) for x in out.split() if x.isdigit()]
                if pids:
                    pid = pids[0]
            except Exception:
                pass
            active_map[tid] = pid
    return active_map


def fetch_codex_rpc_cached(base_dir: Path, force: bool = False) -> dict[str, Any]:
    """Query codex app-server RPC for account, tier, and rateLimits with a caching layer."""
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")) / "omarchy" / "agent-usage"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / "codex-rpc-cache.json"

    now = time.time()
    if not force and cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            cached_at = data.get("_cachedAt", 0)
            if now - cached_at < 90:  # 90 second TTL
                return data
        except Exception:
            pass

    codex_bin = shutil.which("codex", path=f"{Path.home()}/.local/share/mise/shims:{Path.home()}/.local/bin:{os.environ.get('PATH', '')}")
    if not codex_bin:
        codex_bin = "codex"

    rpc_result = {
        "tierLabel": "OpenAI Codex",
        "email": "",
        "authMode": "",
        "quotaGroups": [],
        "limits": [],
        "currentModel": "GPT-6 Luna",
        "_cachedAt": now
    }

    try:
        proc = subprocess.Popen(
            [codex_bin, "-s", "read-only", "-a", "on-request", "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True
        )

        def rpc_call(req_id: int, method: str, params: dict[str, Any] | None = None, timeout: float = 3.5) -> dict[str, Any] | None:
            payload = {"id": req_id, "method": method, "params": params or {}}
            try:
                proc.stdin.write(json.dumps(payload) + "\n")
                proc.stdin.flush()
            except Exception:
                return None
            deadline = time.time() + timeout
            while time.time() < deadline:
                r, _, _ = select.select([proc.stdout], [], [], 0.15)
                if r:
                    line = proc.stdout.readline()
                    if not line:
                        break
                    try:
                        m = json.loads(line)
                        if m.get("id") == req_id:
                            return m
                    except Exception:
                        pass
            return None

        # 1. Initialize
        rpc_call(1, "initialize", {"clientInfo": {"name": "agent-hub", "version": "1.0"}}, timeout=4.0)
        proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
        proc.stdin.flush()

        # 2. Account
        acc_resp = rpc_call(2, "account/read", timeout=3.0)
        plan_type = "free"
        if acc_resp and "result" in acc_resp:
            acc_data = acc_resp["result"].get("account") or {}
            plan_type = acc_data.get("planType") or acc_data.get("type") or "free"
            rpc_result["email"] = acc_data.get("email", "")
            rpc_result["authMode"] = acc_data.get("type", "chatgpt")
            tier_display = f"ChatGPT {plan_type.capitalize()}" if plan_type else "OpenAI Codex"
            rpc_result["tierLabel"] = tier_display

        # 3. Rate Limits
        lim_resp = rpc_call(3, "account/rateLimits/read", timeout=3.0)
        if lim_resp and "result" in lim_resp:
            rl = lim_resp["result"].get("rateLimits") or {}
            buckets = []
            legacy_limits = []

            primary = rl.get("primary")
            if primary and isinstance(primary, dict):
                used_pct = int(primary.get("usedPercent") or 0)
                rem_pct = max(0, 100 - used_pct)
                window_mins = int(primary.get("windowDurationMins") or 0)
                if window_mins == 300:
                    lbl = "5-Hour Limit"
                    win = "5h"
                elif window_mins == 10080:
                    lbl = "Weekly Limit"
                    win = "weekly"
                elif window_mins >= 40000:
                    lbl = "Monthly Limit"
                    win = "monthly"
                else:
                    lbl = f"{window_mins // 60}h Limit" if window_mins >= 60 else "Rate Limit"
                    win = "custom"

                resets_at_sec = primary.get("resetsAt")
                resets_at_iso = dt.datetime.fromtimestamp(resets_at_sec, tz=dt.timezone.utc).isoformat() if resets_at_sec else ""

                b_item = {
                    "id": "codex-primary",
                    "name": f"{lbl} Remaining",
                    "label": lbl,
                    "window": win,
                    "remainingFraction": round(rem_pct / 100.0, 4),
                    "remainingPercent": rem_pct,
                    "usedPercent": used_pct,
                    "resetTime": resets_at_iso,
                    "color": "#10A37F",
                    "burnRatePerHour": 0.0,
                    "burnRateText": "",
                    "forecastText": "Paced to reset",
                    "forecastStatus": "stable" if rem_pct > 20 else ("warning" if rem_pct > 10 else "critical")
                }
                buckets.append(b_item)
                legacy_limits.append({
                    "group": "codex-primary",
                    "groupName": "OpenAI Codex",
                    "title": f"OpenAI Codex {lbl}",
                    "icon": "",
                    "color": "#10A37F",
                    "used": used_pct,
                    "allowance": 100,
                    "percent": round(used_pct / 100.0, 3),
                    "resetsAt": resets_at_iso,
                    "burnRatePerHour": 0.0,
                    "burnRateText": "",
                    "forecastText": "Paced to reset",
                    "forecastStatus": "stable"
                })

            secondary = rl.get("secondary")
            if secondary and isinstance(secondary, dict):
                used_pct = int(secondary.get("usedPercent") or 0)
                rem_pct = max(0, 100 - used_pct)
                window_mins = int(secondary.get("windowDurationMins") or 0)
                lbl = "Secondary Limit"
                if window_mins == 300:
                    lbl = "5-Hour Limit"
                elif window_mins == 10080:
                    lbl = "Weekly Limit"

                resets_at_sec = secondary.get("resetsAt")
                resets_at_iso = dt.datetime.fromtimestamp(resets_at_sec, tz=dt.timezone.utc).isoformat() if resets_at_sec else ""

                b_item = {
                    "id": "codex-secondary",
                    "name": f"{lbl} Remaining",
                    "label": lbl,
                    "window": "secondary",
                    "remainingFraction": round(rem_pct / 100.0, 4),
                    "remainingPercent": rem_pct,
                    "usedPercent": used_pct,
                    "resetTime": resets_at_iso,
                    "color": "#10A37F",
                    "burnRatePerHour": 0.0,
                    "burnRateText": "",
                    "forecastText": "Paced to reset",
                    "forecastStatus": "stable" if rem_pct > 20 else ("warning" if rem_pct > 10 else "critical")
                }
                buckets.append(b_item)
                legacy_limits.append({
                    "group": "codex-secondary",
                    "groupName": "OpenAI Codex",
                    "title": f"OpenAI Codex {lbl}",
                    "icon": "",
                    "color": "#10A37F",
                    "used": used_pct,
                    "allowance": 100,
                    "percent": round(used_pct / 100.0, 3),
                    "resetsAt": resets_at_iso,
                    "burnRatePerHour": 0.0,
                    "burnRateText": "",
                    "forecastText": "Paced to reset",
                    "forecastStatus": "stable"
                })

            if buckets:
                rpc_result["quotaGroups"] = [
                    {
                        "name": "OpenAI Codex",
                        "description": f"{rpc_result['tierLabel']} Usage Limits & Reset Forecasting",
                        "color": "#10A37F",
                        "buckets": buckets
                    }
                ]
                rpc_result["limits"] = legacy_limits

        try:
            if proc.stdin and not proc.stdin.closed:
                proc.stdin.close()
            if proc.stdout and not proc.stdout.closed:
                proc.stdout.close()
            proc.terminate()
            proc.wait(timeout=1.0)
        except Exception:
            pass
    except Exception:
        pass
    finally:
        if 'proc' in locals() and proc:
            try:
                if proc.stdin and not proc.stdin.closed:
                    proc.stdin.close()
                if proc.stdout and not proc.stdout.closed:
                    proc.stdout.close()
                proc.kill()
            except Exception:
                pass

    # Save to cache
    try:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(rpc_result, f)
    except Exception:
        pass

    return rpc_result


def scan_codex_sessions(base_dir: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Scan native rollout files in ~/.codex/sessions/**/*.jsonl."""
    sessions: list[dict[str, Any]] = []
    daily_stats: dict[str, int] = Counter()
    model_stats: dict[str, dict[str, int]] = {}
    today_model_tokens: dict[str, int] = Counter()
    tool_counter: Counter[str] = Counter()
    ws_counter: Counter[str] = Counter()

    today_str = date_string(dt.datetime.now().date())
    sessions_root = base_dir / "sessions"

    files: list[Path] = []
    if sessions_root.exists():
        for p in sessions_root.rglob("*.jsonl"):
            try:
                files.append(p)
            except OSError:
                pass

    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    total_tokens_all = 0
    today_cache_read = 0
    today_cache_write = 0
    today_input = 0
    today_output = 0

    seen_ids = set()

    for path in files:
        cid = ""
        cwd = "/home/boeyadmin"
        model = "GPT-6 Luna"
        first_prompt = ""
        last_prompt = ""
        step_count = 0
        session_tokens = 0
        mtime_sec = path.stat().st_mtime
        date_str = local_date_from_timestamp(mtime_sec)

        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        entry = json.loads(line)
                    except Exception:
                        continue

                    etype = entry.get("type")
                    payload = entry.get("payload") or {}

                    if etype == "session_meta":
                        cid = payload.get("id") or payload.get("session_id") or ""
                        cwd = payload.get("cwd") or cwd
                        if "base_instructions" in payload:
                            prov = payload["base_instructions"].get("provenance") or {}
                            if prov.get("model"):
                                model = clean_model_display_name(prov["model"])
                    elif etype == "turn_context":
                        m = payload.get("model") or payload.get("model_slug")
                        if m:
                            model = clean_model_display_name(m)
                    elif etype == "event_msg":
                        msg_type = payload.get("type")
                        if msg_type in ("user_message", "user_input"):
                            text = payload.get("message") or payload.get("text") or ""
                            if not first_prompt:
                                first_prompt = text
                            last_prompt = text
                            daily_stats[date_str] += 1
                        elif msg_type == "token_count":
                            info = payload.get("info") or {}
                            last_usage = info.get("last_token_usage") or {}
                            cread = int(last_usage.get("cached_input_tokens") or 0)
                            cwrite = int(last_usage.get("cache_write_input_tokens") or 0)
                            inp = max(0, int(last_usage.get("input_tokens") or 0) - cread - cwrite)
                            out = int(last_usage.get("output_tokens") or 0)
                            tot = cread + cwrite + inp + out
                            session_tokens += tot
                            total_tokens_all += tot

                            # Accumulate model usage
                            mbucket = model_stats.setdefault(model, {
                                "prompts": 0, "steps": 0, "tokens": 0,
                                "todayPrompts": 0, "todaySteps": 0, "todayTokens": 0
                            })
                            mbucket["tokens"] += tot

                            if date_str == today_str:
                                today_cache_read += cread
                                today_cache_write += cwrite
                                today_input += inp
                                today_output += out
                                today_model_tokens[model] += tot
                                mbucket["todayTokens"] += tot
                        elif msg_type in ("assistant_message", "agent_message", "turn_completed"):
                            step_count += 1
                        elif msg_type in ("tool_call", "function_call"):
                            tname = payload.get("name") or payload.get("tool") or "tool"
                            tool_counter[tname] += 1
                    elif etype == "response_item":
                        p = payload.get("payload") or payload
                        if isinstance(p, dict) and p.get("type") == "token_count":
                            info = p.get("info") or {}
                            last_usage = info.get("last_token_usage") or {}
                            cread = int(last_usage.get("cached_input_tokens") or 0)
                            inp = max(0, int(last_usage.get("input_tokens") or 0) - cread)
                            out = int(last_usage.get("output_tokens") or 0)
                            tot = cread + inp + out
                            session_tokens += tot
                            total_tokens_all += tot
                            if date_str == today_str:
                                today_cache_read += cread
                                today_input += inp
                                today_output += out
                                today_model_tokens[model] += tot
        except Exception:
            continue

        if not cid:
            cid = path.stem.replace("rollout-", "")
        if cid in seen_ids:
            continue
        seen_ids.add(cid)

        # Update model prompts and steps
        mbucket = model_stats.setdefault(model, {
            "prompts": 0, "steps": 0, "tokens": 0,
            "todayPrompts": 0, "todaySteps": 0, "todayTokens": 0
        })
        mbucket["prompts"] += 1
        mbucket["steps"] += step_count
        if date_str == today_str:
            mbucket["todayPrompts"] += 1
            mbucket["todaySteps"] += step_count

        ws_clean = sanitize_plain_text(cwd, 300)
        ws_name = Path(ws_clean).name if ws_clean else "Workspace"
        ws_counter[ws_clean] += 1

        title = first_prompt or last_prompt or f"Session {cid[:8]}"
        preview = last_prompt or first_prompt or title
        iso_mod = dt.datetime.fromtimestamp(mtime_sec, tz=dt.timezone.utc).isoformat() if mtime_sec else ""

        sessions.append({
            "conversationId": cid,
            "title": sanitize_plain_text(title, 150),
            "preview": sanitize_plain_text(preview, 250),
            "stepCount": step_count,
            "lastModified": iso_mod,
            "date": date_str,
            "workspace": ws_clean,
            "workspaceName": ws_name,
            "status": "idle",
            "agentName": "Codex",
            "notFullyIdle": False,
            "killed": False,
            "isActive": False,
            "isSubagent": False,
            "parentConversationId": None,
            "model": model,
            "timestamp": mtime_sec
        })

    extra_data = {
        "dailyStats": daily_stats,
        "modelStats": model_stats,
        "todayModelTokens": today_model_tokens,
        "todayCacheRead": today_cache_read,
        "todayCacheWrite": today_cache_write,
        "todayInput": today_input,
        "todayOutput": today_output,
        "totalTokens": total_tokens_all,
        "toolCounter": tool_counter,
        "wsCounter": ws_counter
    }
    return sessions, extra_data


def scan(base_dir: Path | None = None, force: bool = False, alert_threshold: int | None = None) -> dict[str, Any]:
    """Execute complete Codex scanner, returning unified JSON dictionary."""
    base_dir = base_dir or default_base_dir()

    today_str = date_string(dt.datetime.now().date())
    recent_dates = recent_date_strings()

    # 1. Fetch sessions
    sessions, extra = scan_codex_sessions(base_dir)

    # 2. Check active lock files
    active_locks = check_active_lock_threads(base_dir)
    has_active_session = len(active_locks) > 0

    active_sessions: list[dict[str, Any]] = []
    any_working = False

    for s in sessions:
        cid = s["conversationId"]
        if cid in active_locks:
            s["isActive"] = True
            s["status"] = "active"
            s["pid"] = active_locks[cid]
            # If PID found or thread snapshot recently updated, mark as working
            s["notFullyIdle"] = bool(active_locks[cid] > 0)
            if s["notFullyIdle"]:
                any_working = True
            active_sessions.append(s)

    # If active lock not in sessions list (e.g. brand new session)
    for tid, pid in active_locks.items():
        if tid not in [s["conversationId"] for s in sessions]:
            item = {
                "conversationId": tid,
                "title": f"Codex Session {tid[:8]}",
                "preview": "Active turn in progress...",
                "stepCount": 1,
                "lastModified": dt.datetime.now(dt.timezone.utc).isoformat(),
                "date": today_str,
                "workspace": "/home/boeyadmin",
                "workspaceName": "boeyadmin",
                "status": "active",
                "agentName": "Codex",
                "notFullyIdle": True,
                "killed": False,
                "isActive": True,
                "isSubagent": False,
                "parentConversationId": None,
                "model": "GPT-6 Luna",
                "pid": pid,
                "timestamp": time.time()
            }
            sessions.insert(0, item)
            active_sessions.insert(0, item)
            any_working = True

    active_status = "Working" if any_working else ("Waiting" if has_active_session else "Idle")

    # 3. Fetch RPC limits & account info
    rpc_data = fetch_codex_rpc_cached(base_dir, force=force)

    # 4. Model usage formatting
    model_stats = extra["modelStats"]
    total_tokens_all = extra["totalTokens"]
    model_list = []

    for mname, mdata in model_stats.items():
        sh_frac = (mdata["tokens"] / total_tokens_all) if total_tokens_all > 0 else 0.0
        model_list.append({
            "name": mname,
            "prompts": mdata["prompts"],
            "steps": mdata["steps"],
            "tokens": mdata["tokens"],
            "todayPrompts": mdata["todayPrompts"],
            "todaySteps": mdata["todaySteps"],
            "todayTokens": mdata["todayTokens"],
            "shareFraction": round(sh_frac, 4),
            "sharePercent": round(sh_frac * 100.0, 1),
            "color": get_model_color(mname)
        })

    model_list.sort(key=lambda x: x["tokens"], reverse=True)
    if not model_list:
        model_list.append({
            "name": rpc_data.get("currentModel", "GPT-6 Luna"),
            "prompts": 0, "steps": 0, "tokens": 0,
            "todayPrompts": 0, "todaySteps": 0, "todayTokens": 0,
            "shareFraction": 1.0, "sharePercent": 100.0,
            "color": "#10A37F"
        })

    current_model = model_list[0]["name"] if model_list else "GPT-6 Luna"

    # 5. Daily history
    daily_stats = extra["dailyStats"]
    recent_days = []
    for d in recent_dates:
        cnt = daily_stats.get(d, 0)
        recent_days.append({
            "date": d,
            "messageCount": cnt,
            "prompts": cnt,
            "steps": cnt
        })

    today_prompts = daily_stats.get(today_str, 0)
    today_steps = sum(m["todaySteps"] for m in model_list)
    today_total_tokens = sum(extra["todayModelTokens"].values())

    cache_read = extra["todayCacheRead"]
    cache_write = extra["todayCacheWrite"]
    inp = extra["todayInput"]
    denom = cache_read + cache_write + inp
    cache_hit_rate = round((cache_read / denom) * 100.0, 1) if denom > 0 else 0.0

    # 6. Workspaces
    recent_workspaces = [
        {"path": ws, "name": Path(ws).name, "count": cnt}
        for ws, cnt in extra["wsCounter"].most_common(5)
    ]

    tools_dict = dict(extra["toolCounter"].most_common(10))

    result = {
        "schemaVersion": 1,
        "id": "codex",
        "name": "Codex",
        "ready": True,
        "active": has_active_session,
        "activeStatus": active_status,
        "hasActiveSession": has_active_session,
        "hasLocalStats": True,
        "tierLabel": rpc_data.get("tierLabel", "OpenAI Codex"),
        "currentModel": current_model,
        "todayPrompts": today_prompts,
        "todaySessions": len([s for s in sessions if s.get("date") == today_str]) or (1 if has_active_session else 0),
        "todaySteps": today_steps,
        "todayTotalTokens": today_total_tokens,
        "todayTokensByModel": dict(extra["todayModelTokens"]),
        "todayCacheReadTokens": cache_read,
        "todayCacheCreationTokens": cache_write,
        "todayInputTokens": inp,
        "todayOutputTokens": extra["todayOutput"],
        "todayCacheHitRate": cache_hit_rate,
        "recentDays": recent_days,
        "totalPrompts": sum(daily_stats.values()),
        "totalSessions": len(sessions),
        "totalSteps": sum(s.get("stepCount", 0) for s in sessions),
        "activeSessions": active_sessions,
        "recentSessions": sessions[:10],
        "toolUsage": tools_dict,
        "modelUsage": extra["modelStats"],
        "modelList": model_list,
        "quotaGroups": rpc_data.get("quotaGroups", []),
        "limits": rpc_data.get("limits", []),
        "recentWorkspaces": recent_workspaces,
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "quotaUpdatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "quotaUpdatedMs": int(time.time() * 1000),
        "lastFullRefreshMs": int(time.time() * 1000),
        "usageStatusText": active_status,
        "authHelpText": ""
    }

    return result


scan_codex = scan


def kill_session(session_id: str, base_dir: Path | None = None) -> bool:
    """Terminate the process running a given Codex session ID."""
    base_dir = base_dir or default_base_dir()
    lock_file = base_dir / "thread-writer-locks" / f"{session_id}.lock"
    if lock_file.exists():
        try:
            out = subprocess.check_output(["fuser", "-k", str(lock_file)], stderr=subprocess.DEVNULL, text=True)
            return True
        except Exception:
            pass
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Codex Usage Scanner")
    parser.add_argument("path", nargs="?", default=None, help="Path to ~/.codex")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--force", action="store_true", help="Bypass cache and force refresh")
    parser.add_argument("--kill", type=str, default=None, help="Kill the running session by ID")
    args = parser.parse_args()

    base_dir = expand_path(args.path) if args.path else default_base_dir()

    if args.kill:
        ok = kill_session(args.kill, base_dir)
        print(json.dumps({"success": ok, "conversationId": args.kill}))
        return

    res = scan(base_dir, force=args.force)
    print(json.dumps(res, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
