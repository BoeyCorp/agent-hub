#!/usr/bin/env python3
"""Monthly Usage & Analytics Engine for Agent Hub.

Aggregates 30-day and calendar-month telemetry across Claude Code,
Google Antigravity, and OpenAI Codex with an incremental file-level caching layer.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

# Import cost estimation helpers from existing scanners
try:
    from scripts import claude_scanner, antigravity_scanner, codex_scanner
except ImportError:
    import claude_scanner, antigravity_scanner, codex_scanner


def default_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    p = Path(base) / "agent-hub"
    p.mkdir(parents=True, exist_ok=True)
    return p


def default_cache_file() -> Path:
    return default_cache_dir() / "monthly_analytics_cache.json"


def sanitize_str(val: Any, max_len: int = 120) -> str:
    if val is None:
        return ""
    import re
    text = str(val)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


def get_rolling_date_list(num_days: int = 30, end_date: dt.date | None = None) -> list[str]:
    """Return sorted list of ISO date strings for the rolling window ending at end_date."""
    end = end_date or dt.datetime.now().date()
    return [(end - dt.timedelta(days=i)).strftime("%Y-%m-%d") for i in range(num_days - 1, -1, -1)]


def get_calendar_month_date_list(year: int | None = None, month: int | None = None) -> list[str]:
    """Return sorted list of ISO date strings for a specific calendar month."""
    today = dt.datetime.now().date()
    y = year or today.year
    m = month or today.month

    # First day of the month
    start = dt.date(y, m, 1)
    # First day of next month
    if m == 12:
        next_month = dt.date(y + 1, 1, 1)
    else:
        next_month = dt.date(y, m + 1, 1)

    days_in_month = (next_month - start).days
    return [(start + dt.timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days_in_month)]


def scan_claude_monthly(date_set: set[str], base_dir: Path | None = None, file_cache: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    """Scan ~/.claude for 30-day activity with incremental transcript caching."""
    base = base_dir or (Path.home() / ".claude")
    history_file = base / "history.jsonl"
    projects_dir = base / "projects"
    f_cache = file_cache if file_cache is not None else {}

    results: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "prompts": 0,
        "steps": 0,
        "tokens": 0,
        "cost": 0.0,
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadTokens": 0,
        "cacheCreationTokens": 0,
        "models": Counter()
    })

    # 1. Parse history.jsonl
    if history_file.exists():
        try:
            with open(history_file, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        entry = json.loads(line)
                        ts = entry.get("timestamp")
                        if ts:
                            # Handle seconds or milliseconds epoch
                            sec = ts / 1000.0 if ts > 10_000_000_000 else ts
                            d = dt.datetime.fromtimestamp(sec).strftime("%Y-%m-%d")
                            if d in date_set:
                                results[d]["prompts"] += 1
                    except Exception:
                        continue
        except Exception:
            pass

    # 2. Parse projects transcripts
    if projects_dir.exists():
        for p in projects_dir.glob("*/*.jsonl"):
            try:
                st = p.stat()
                mtime = st.st_mtime
                size = st.st_size
            except Exception:
                continue

            file_key = str(p)
            cached = f_cache.get(file_key)

            if cached and cached.get("mtime") == mtime and cached.get("size") == size and "daily" in cached:
                daily_data = cached["daily"]
                for day, data in daily_data.items():
                    if day in date_set:
                        r = results[day]
                        r["steps"] += data.get("steps", 0)
                        r["tokens"] += data.get("tokens", 0)
                        r["cost"] += data.get("cost", 0.0)
                        r["inputTokens"] += data.get("inputTokens", 0)
                        r["outputTokens"] += data.get("outputTokens", 0)
                        r["cacheReadTokens"] += data.get("cacheReadTokens", 0)
                        r["cacheCreationTokens"] += data.get("cacheCreationTokens", 0)
                        for m_name, m_tok in data.get("models", {}).items():
                            r["models"][m_name] += m_tok
                continue

            # Need to parse this file
            file_daily: dict[str, dict[str, Any]] = defaultdict(lambda: {
                "steps": 0,
                "tokens": 0,
                "cost": 0.0,
                "inputTokens": 0,
                "outputTokens": 0,
                "cacheReadTokens": 0,
                "cacheCreationTokens": 0,
                "models": Counter()
            })

            file_model = "Claude (Default)"
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if not line.strip():
                            continue
                        try:
                            entry = json.loads(line)
                        except Exception:
                            continue

                        etype = entry.get("type")
                        msg = entry.get("message") or {}
                        ca = entry.get("timestamp") or ""
                        if not ca:
                            continue

                        # Extract ISO date from timestamp string or number
                        if isinstance(ca, (int, float)):
                            sec = ca / 1000.0 if ca > 10_000_000_000 else ca
                            day = dt.datetime.fromtimestamp(sec).strftime("%Y-%m-%d")
                        else:
                            day = str(ca)[:10]

                        if etype == "assistant" and isinstance(msg, dict):
                            file_daily[day]["steps"] += 1
                            m = msg.get("model")
                            if m and isinstance(m, str):
                                file_model = sanitize_str(m, 80)

                            usage = msg.get("usage") or {}
                            if isinstance(usage, dict):
                                u_in = int(usage.get("input_tokens") or 0)
                                u_out = int(usage.get("output_tokens") or 0)
                                u_create = int(usage.get("cache_creation_input_tokens") or 0)
                                u_read = int(usage.get("cache_read_input_tokens") or 0)
                                tot = u_in + u_out + u_create + u_read

                                d_stat = file_daily[day]
                                d_stat["inputTokens"] += u_in
                                d_stat["outputTokens"] += u_out
                                d_stat["cacheCreationTokens"] += u_create
                                d_stat["cacheReadTokens"] += u_read
                                d_stat["tokens"] += tot
                                d_stat["models"][file_model] += tot
                                d_stat["cost"] += claude_scanner.estimate_claude_token_cost(
                                    file_model, u_in, u_out, u_read, u_create
                                )
            except Exception:
                continue

            # Update cache entry
            cached_daily: dict[str, dict[str, Any]] = {}
            for day, d_stat in file_daily.items():
                cached_daily[day] = {
                    "steps": d_stat["steps"],
                    "tokens": d_stat["tokens"],
                    "cost": round(d_stat["cost"], 4),
                    "inputTokens": d_stat["inputTokens"],
                    "outputTokens": d_stat["outputTokens"],
                    "cacheReadTokens": d_stat["cacheReadTokens"],
                    "cacheCreationTokens": d_stat["cacheCreationTokens"],
                    "models": dict(d_stat["models"])
                }
                if day in date_set:
                    r = results[day]
                    r["steps"] += d_stat["steps"]
                    r["tokens"] += d_stat["tokens"]
                    r["cost"] += d_stat["cost"]
                    r["inputTokens"] += d_stat["inputTokens"]
                    r["outputTokens"] += d_stat["outputTokens"]
                    r["cacheReadTokens"] += d_stat["cacheReadTokens"]
                    r["cacheCreationTokens"] += d_stat["cacheCreationTokens"]
                    for m_name, m_tok in d_stat["models"].items():
                        r["models"][m_name] += m_tok

            f_cache[file_key] = {
                "mtime": mtime,
                "size": size,
                "daily": cached_daily
            }

    return results


def scan_antigravity_monthly(date_set: set[str], base_dir: Path | None = None, file_cache: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    """Scan ~/.gemini/antigravity-cli for 30-day activity with incremental transcript caching."""
    base = base_dir or (Path.home() / ".gemini" / "antigravity-cli")
    history_file = base / "history.jsonl"
    brain_dir = base / "brain"
    f_cache = file_cache if file_cache is not None else {}

    results: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "prompts": 0,
        "steps": 0,
        "tokens": 0,
        "cost": 0.0,
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadTokens": 0,
        "cacheCreationTokens": 0,
        "models": Counter()
    })

    # 1. Parse history.jsonl
    if history_file.exists():
        try:
            with open(history_file, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        entry = json.loads(line)
                        ts = entry.get("timestamp")
                        if ts:
                            sec = ts / 1000.0 if ts > 10_000_000_000 else ts
                            d = dt.datetime.fromtimestamp(sec).strftime("%Y-%m-%d")
                            if d in date_set:
                                results[d]["prompts"] += 1
                    except Exception:
                        continue
        except Exception:
            pass

    # 2. Parse brain transcripts
    if brain_dir.exists():
        for p in brain_dir.glob("*/.system_generated/logs/transcript*.jsonl"):
            try:
                st = p.stat()
                mtime = st.st_mtime
                size = st.st_size
            except Exception:
                continue

            file_key = str(p)
            cached = f_cache.get(file_key)

            if cached and cached.get("mtime") == mtime and cached.get("size") == size and "daily" in cached:
                daily_data = cached["daily"]
                for day, data in daily_data.items():
                    if day in date_set:
                        r = results[day]
                        r["steps"] += data.get("steps", 0)
                        r["tokens"] += data.get("tokens", 0)
                        r["cost"] += data.get("cost", 0.0)
                        r["inputTokens"] += data.get("inputTokens", 0)
                        r["outputTokens"] += data.get("outputTokens", 0)
                        r["cacheReadTokens"] += data.get("cacheReadTokens", 0)
                        for m_name, m_tok in data.get("models", {}).items():
                            r["models"][m_name] += m_tok
                continue

            file_daily: dict[str, dict[str, Any]] = defaultdict(lambda: {
                "steps": 0,
                "tokens": 0,
                "cost": 0.0,
                "inputTokens": 0,
                "outputTokens": 0,
                "cacheReadTokens": 0,
                "models": Counter()
            })

            file_model = "Gemini 3.8 Flash (High)"
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if not line.strip():
                            continue
                        try:
                            entry = json.loads(line)
                        except Exception:
                            continue

                        ca = entry.get("created_at") or ""
                        day = str(ca)[:10] if ca else ""
                        if not day:
                            continue

                        stype = entry.get("type")
                        if stype == "PLANNER_RESPONSE":
                            file_daily[day]["steps"] += 1

                        # Token usage
                        u_in = int(entry.get("input_tokens") or 0)
                        u_out = int(entry.get("output_tokens") or 0)
                        u_read = int(entry.get("cache_read_tokens") or 0)
                        tot = u_in + u_out + u_read

                        m = entry.get("model")
                        if m and isinstance(m, str):
                            file_model = sanitize_str(m, 80)

                        if tot > 0:
                            d_stat = file_daily[day]
                            d_stat["inputTokens"] += u_in
                            d_stat["outputTokens"] += u_out
                            d_stat["cacheReadTokens"] += u_read
                            d_stat["tokens"] += tot
                            d_stat["models"][file_model] += tot
                            d_stat["cost"] += antigravity_scanner.estimate_antigravity_token_cost(
                                file_model, u_in, u_out, u_read
                            )
            except Exception:
                continue

            # Update cache entry
            cached_daily: dict[str, dict[str, Any]] = {}
            for day, d_stat in file_daily.items():
                cached_daily[day] = {
                    "steps": d_stat["steps"],
                    "tokens": d_stat["tokens"],
                    "cost": round(d_stat["cost"], 4),
                    "inputTokens": d_stat["inputTokens"],
                    "outputTokens": d_stat["outputTokens"],
                    "cacheReadTokens": d_stat["cacheReadTokens"],
                    "models": dict(d_stat["models"])
                }
                if day in date_set:
                    r = results[day]
                    r["steps"] += d_stat["steps"]
                    r["tokens"] += d_stat["tokens"]
                    r["cost"] += d_stat["cost"]
                    r["inputTokens"] += d_stat["inputTokens"]
                    r["outputTokens"] += d_stat["outputTokens"]
                    r["cacheReadTokens"] += d_stat["cacheReadTokens"]
                    for m_name, m_tok in d_stat["models"].items():
                        r["models"][m_name] += m_tok

            f_cache[file_key] = {
                "mtime": mtime,
                "size": size,
                "daily": cached_daily
            }

    return results


def scan_codex_monthly(date_set: set[str], base_dir: Path | None = None, file_cache: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    """Scan ~/.codex for 30-day activity with incremental session caching."""
    base = base_dir or (Path.home() / ".codex")
    sessions_root = base / "sessions"
    history_file = base / "history.jsonl"
    f_cache = file_cache if file_cache is not None else {}

    results: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "prompts": 0,
        "steps": 0,
        "tokens": 0,
        "cost": 0.0,
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadTokens": 0,
        "cacheCreationTokens": 0,
        "models": Counter()
    })

    # 1. Parse history.jsonl
    if history_file.exists():
        try:
            with open(history_file, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        entry = json.loads(line)
                        ts = entry.get("timestamp")
                        if ts:
                            sec = ts / 1000.0 if ts > 10_000_000_000 else ts
                            d = dt.datetime.fromtimestamp(sec).strftime("%Y-%m-%d")
                            if d in date_set:
                                results[d]["prompts"] += 1
                    except Exception:
                        continue
        except Exception:
            pass

    # 2. Parse sessions
    if sessions_root.exists():
        for p in sessions_root.rglob("*.jsonl"):
            try:
                st = p.stat()
                mtime = st.st_mtime
                size = st.st_size
            except Exception:
                continue

            file_key = str(p)
            cached = f_cache.get(file_key)

            if cached and cached.get("mtime") == mtime and cached.get("size") == size and "daily" in cached:
                daily_data = cached["daily"]
                for day, data in daily_data.items():
                    if day in date_set:
                        r = results[day]
                        r["prompts"] += data.get("prompts", 0)
                        r["steps"] += data.get("steps", 0)
                        r["tokens"] += data.get("tokens", 0)
                        r["cost"] += data.get("cost", 0.0)
                        r["inputTokens"] += data.get("inputTokens", 0)
                        r["outputTokens"] += data.get("outputTokens", 0)
                        r["cacheReadTokens"] += data.get("cacheReadTokens", 0)
                        r["cacheCreationTokens"] += data.get("cacheCreationTokens", 0)
                        for m_name, m_tok in data.get("models", {}).items():
                            r["models"][m_name] += m_tok
                continue

            file_daily: dict[str, dict[str, Any]] = defaultdict(lambda: {
                "prompts": 0,
                "steps": 0,
                "tokens": 0,
                "cost": 0.0,
                "inputTokens": 0,
                "outputTokens": 0,
                "cacheReadTokens": 0,
                "cacheCreationTokens": 0,
                "models": Counter()
            })

            file_date = dt.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")
            file_model = "GPT-6 Luna"

            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if not line.strip():
                            continue
                        try:
                            entry = json.loads(line)
                        except Exception:
                            continue

                        etype = entry.get("type")
                        payload = entry.get("payload") or {}

                        if etype == "turn_context":
                            m = payload.get("model") or payload.get("model_slug")
                            if m:
                                file_model = codex_scanner.clean_model_display_name(m)
                        elif etype == "event_msg":
                            mtype = payload.get("type")
                            if mtype in ("user_message", "user_input"):
                                file_daily[file_date]["prompts"] += 1
                            elif mtype in ("assistant_message", "agent_message", "turn_completed"):
                                file_daily[file_date]["steps"] += 1
                            elif mtype == "token_count":
                                info = payload.get("info") or {}
                                usage = info.get("last_token_usage") or {}
                                cread = int(usage.get("cached_input_tokens") or 0)
                                cwrite = int(usage.get("cache_write_input_tokens") or 0)
                                inp = max(0, int(usage.get("input_tokens") or 0) - cread - cwrite)
                                out = int(usage.get("output_tokens") or 0)
                                tot = cread + cwrite + inp + out

                                d_stat = file_daily[file_date]
                                d_stat["inputTokens"] += inp
                                d_stat["outputTokens"] += out
                                d_stat["cacheReadTokens"] += cread
                                d_stat["cacheCreationTokens"] += cwrite
                                d_stat["tokens"] += tot
                                d_stat["models"][file_model] += tot
                                d_stat["cost"] += codex_scanner.estimate_codex_token_cost(
                                    file_model, inp, out, cread, cwrite
                                )
            except Exception:
                continue

            # Update cache entry
            cached_daily: dict[str, dict[str, Any]] = {}
            for day, d_stat in file_daily.items():
                cached_daily[day] = {
                    "prompts": d_stat["prompts"],
                    "steps": d_stat["steps"],
                    "tokens": d_stat["tokens"],
                    "cost": round(d_stat["cost"], 4),
                    "inputTokens": d_stat["inputTokens"],
                    "outputTokens": d_stat["outputTokens"],
                    "cacheReadTokens": d_stat["cacheReadTokens"],
                    "cacheCreationTokens": d_stat["cacheCreationTokens"],
                    "models": dict(d_stat["models"])
                }
                if day in date_set:
                    r = results[day]
                    r["prompts"] += d_stat["prompts"]
                    r["steps"] += d_stat["steps"]
                    r["tokens"] += d_stat["tokens"]
                    r["cost"] += d_stat["cost"]
                    r["inputTokens"] += d_stat["inputTokens"]
                    r["outputTokens"] += d_stat["outputTokens"]
                    r["cacheReadTokens"] += d_stat["cacheReadTokens"]
                    r["cacheCreationTokens"] += d_stat["cacheCreationTokens"]
                    for m_name, m_tok in d_stat["models"].items():
                        r["models"][m_name] += m_tok

            f_cache[file_key] = {
                "mtime": mtime,
                "size": size,
                "daily": cached_daily
            }

    return results


def aggregate_monthly(
    num_days: int = 30,
    end_date: dt.date | None = None,
    start_date: dt.date | None = None,
    mode: str = "rolling",  # "rolling" or "calendar"
    claude_base_dir: Path | None = None,
    antigravity_base_dir: Path | None = None,
    codex_base_dir: Path | None = None,
    cache_path: Path | None = None,
    force: bool = False
) -> dict[str, Any]:
    """Execute complete 30-day cross-agent telemetry aggregation."""
    c_path = cache_path or default_cache_file()
    file_cache: dict[str, Any] = {}

    if not force and c_path.exists():
        try:
            with open(c_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict) and "files" in loaded:
                    file_cache = loaded["files"]
        except Exception:
            file_cache = {}

    # Determine date list
    if start_date is not None:
        end = end_date or dt.datetime.now().date()
        start = start_date
        if start > end:
            start, end = end, start
        if (end - start).days > 365:
            start = end - dt.timedelta(days=365)
        days_span = (end - start).days + 1
        date_list = [(start + dt.timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days_span)]
        period_label = f"{start.strftime('%b %d')} – {end.strftime('%b %d, %Y')}"
    elif mode == "calendar":
        date_list = get_calendar_month_date_list()
        period_label = dt.datetime.now().strftime("%B %Y")
    else:
        date_list = get_rolling_date_list(num_days=num_days, end_date=end_date)
        period_label = f"Last {len(date_list)} Days"

    date_set = set(date_list)

    # Scan agents
    claude_data = scan_claude_monthly(date_set, claude_base_dir, file_cache)
    antigravity_data = scan_antigravity_monthly(date_set, antigravity_base_dir, file_cache)
    codex_data = scan_codex_monthly(date_set, codex_base_dir, file_cache)

    # Save updated file cache
    try:
        with open(c_path, "w", encoding="utf-8") as f:
            json.dump({
                "schemaVersion": 1,
                "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                "files": file_cache
            }, f)
    except Exception:
        pass

    # Merge daily rows
    daily_rows: list[dict[str, Any]] = []
    tot_tokens = 0
    tot_cost = 0.0
    tot_prompts = 0
    tot_steps = 0
    tot_inp = 0
    tot_out = 0
    tot_cache_read = 0
    tot_cache_create = 0

    agent_totals = {
        "claude": {"tokens": 0, "cost": 0.0, "prompts": 0, "steps": 0},
        "antigravity": {"tokens": 0, "cost": 0.0, "prompts": 0, "steps": 0},
        "codex": {"tokens": 0, "cost": 0.0, "prompts": 0, "steps": 0},
    }

    all_models: Counter = Counter()
    model_costs: defaultdict[str, float] = defaultdict(float)

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    max_day_prompts = 1

    for d_str in date_list:
        parsed_dt = dt.datetime.strptime(d_str, "%Y-%m-%d").date()
        dow = day_names[parsed_dt.weekday()]

        c_stat = claude_data.get(d_str, {})
        a_stat = antigravity_data.get(d_str, {})
        x_stat = codex_data.get(d_str, {})

        c_tok = int(c_stat.get("tokens", 0))
        a_tok = int(a_stat.get("tokens", 0))
        x_tok = int(x_stat.get("tokens", 0))
        day_tok = c_tok + a_tok + x_tok

        c_cost = float(c_stat.get("cost", 0.0))
        a_cost = float(a_stat.get("cost", 0.0))
        x_cost = float(x_stat.get("cost", 0.0))
        day_cost = c_cost + a_cost + x_cost

        c_p = int(c_stat.get("prompts", 0))
        a_p = int(a_stat.get("prompts", 0))
        x_p = int(x_stat.get("prompts", 0))
        day_p = c_p + a_p + x_p
        if day_p > max_day_prompts:
            max_day_prompts = day_p

        c_s = int(c_stat.get("steps", 0))
        a_s = int(a_stat.get("steps", 0))
        x_s = int(x_stat.get("steps", 0))
        day_s = c_s + a_s + x_s

        c_inp = int(c_stat.get("inputTokens", 0))
        a_inp = int(a_stat.get("inputTokens", 0))
        x_inp = int(x_stat.get("inputTokens", 0))
        day_inp = c_inp + a_inp + x_inp

        c_out = int(c_stat.get("outputTokens", 0))
        a_out = int(a_stat.get("outputTokens", 0))
        x_out = int(x_stat.get("outputTokens", 0))
        day_out = c_out + a_out + x_out

        c_cread = int(c_stat.get("cacheReadTokens", 0))
        a_cread = int(a_stat.get("cacheReadTokens", 0))
        x_cread = int(x_stat.get("cacheReadTokens", 0))
        day_cread = c_cread + a_cread + x_cread

        c_ccreate = int(c_stat.get("cacheCreationTokens", 0))
        x_ccreate = int(x_stat.get("cacheCreationTokens", 0))
        day_ccreate = c_ccreate + x_ccreate

        denom = day_inp + day_cread
        day_hit_rate = round((day_cread / denom) * 100.0, 1) if denom > 0 else 0.0

        # Model breakdown for day
        day_models: Counter = Counter()
        for m_name, m_cnt in (c_stat.get("models") or {}).items():
            day_models[m_name] += m_cnt
            all_models[m_name] += m_cnt
            model_costs[m_name] += claude_scanner.estimate_claude_token_cost(m_name, m_cnt, 0)
        for m_name, m_cnt in (a_stat.get("models") or {}).items():
            day_models[m_name] += m_cnt
            all_models[m_name] += m_cnt
            model_costs[m_name] += antigravity_scanner.estimate_antigravity_token_cost(m_name, m_cnt, 0)
        for m_name, m_cnt in (x_stat.get("models") or {}).items():
            day_models[m_name] += m_cnt
            all_models[m_name] += m_cnt
            model_costs[m_name] += codex_scanner.estimate_codex_token_cost(m_name, m_cnt, 0)

        top_m = day_models.most_common(1)[0][0] if day_models else ""

        # Accumulate totals
        tot_tokens += day_tok
        tot_cost += day_cost
        tot_prompts += day_p
        tot_steps += day_s
        tot_inp += day_inp
        tot_out += day_out
        tot_cache_read += day_cread
        tot_cache_create += day_ccreate

        agent_totals["claude"]["tokens"] += c_tok
        agent_totals["claude"]["cost"] += c_cost
        agent_totals["claude"]["prompts"] += c_p
        agent_totals["claude"]["steps"] += c_s

        agent_totals["antigravity"]["tokens"] += a_tok
        agent_totals["antigravity"]["cost"] += a_cost
        agent_totals["antigravity"]["prompts"] += a_p
        agent_totals["antigravity"]["steps"] += a_s

        agent_totals["codex"]["tokens"] += x_tok
        agent_totals["codex"]["cost"] += x_cost
        agent_totals["codex"]["prompts"] += x_p
        agent_totals["codex"]["steps"] += x_s

        daily_rows.append({
            "date": d_str,
            "dayOfWeek": dow,
            "dayOfMonth": parsed_dt.day,
            "prompts": day_p,
            "steps": day_s,
            "tokens": day_tok,
            "cost": round(day_cost, 2),
            "inputTokens": day_inp,
            "outputTokens": day_out,
            "cacheReadTokens": day_cread,
            "cacheHitRate": day_hit_rate,
            "topModel": top_m,
            "agents": {
                "claude": {
                    "prompts": c_p,
                    "steps": c_s,
                    "tokens": c_tok,
                    "cost": round(c_cost, 2),
                    "inputTokens": c_inp,
                    "outputTokens": c_out,
                    "cacheReadTokens": c_cread
                },
                "antigravity": {
                    "prompts": a_p,
                    "steps": a_s,
                    "tokens": a_tok,
                    "cost": round(a_cost, 2),
                    "inputTokens": a_inp,
                    "outputTokens": a_out,
                    "cacheReadTokens": a_cread
                },
                "codex": {
                    "prompts": x_p,
                    "steps": x_s,
                    "tokens": x_tok,
                    "cost": round(x_cost, 2),
                    "inputTokens": x_inp,
                    "outputTokens": x_out,
                    "cacheReadTokens": x_cread
                }
            }
        })

    # Summary calculations
    denom_all = tot_inp + tot_cache_read
    overall_hit_rate = round((tot_cache_read / denom_all) * 100.0, 1) if denom_all > 0 else 0.0
    days_cnt = len(date_list)
    active_days = len([d for d in daily_rows if d["prompts"] > 0 or d["tokens"] > 0])

    busiest = max(daily_rows, key=lambda x: (x["prompts"], x["tokens"])) if daily_rows else {
        "date": "", "prompts": 0, "tokens": 0, "cost": 0.0
    }

    # Agent breakdown formatting
    by_agent: dict[str, dict[str, Any]] = {}
    for a_id, a_stats in agent_totals.items():
        by_agent[a_id] = {
            "tokens": a_stats["tokens"],
            "cost": round(a_stats["cost"], 2),
            "prompts": a_stats["prompts"],
            "steps": a_stats["steps"],
            "sharePercent": round((a_stats["tokens"] / tot_tokens) * 100.0, 1) if tot_tokens > 0 else 0.0,
            "costPercent": round((a_stats["cost"] / tot_cost) * 100.0, 1) if tot_cost > 0 else 0.0,
        }

    # Top models formatting
    model_list: list[dict[str, Any]] = []
    for m_name, m_tok in all_models.most_common(8):
        model_list.append({
            "name": m_name,
            "tokens": m_tok,
            "cost": round(model_costs[m_name], 2),
            "sharePercent": round((m_tok / tot_tokens) * 100.0, 1) if tot_tokens > 0 else 0.0
        })

    # Calendar Heatmap cells with 0..4 intensity levels
    heatmap: list[dict[str, Any]] = []
    for d in daily_rows:
        p_cnt = d["prompts"]
        if p_cnt == 0:
            level = 0
        elif p_cnt <= max(1, max_day_prompts // 4):
            level = 1
        elif p_cnt <= max(2, max_day_prompts // 2):
            level = 2
        elif p_cnt <= max(3, (max_day_prompts * 3) // 4):
            level = 3
        else:
            level = 4

        heatmap.append({
            "date": d["date"],
            "dayOfWeek": d["dayOfWeek"],
            "dayOfMonth": d["dayOfMonth"],
            "prompts": p_cnt,
            "tokens": d["tokens"],
            "cost": d["cost"],
            "intensity": level
        })

    return {
        "schemaVersion": 1,
        "period": {
            "start": date_list[0] if date_list else "",
            "end": date_list[-1] if date_list else "",
            "daysCount": days_cnt,
            "label": period_label
        },
        "summary": {
            "totalTokens": tot_tokens,
            "totalInputTokens": tot_inp,
            "totalOutputTokens": tot_out,
            "totalCacheReadTokens": tot_cache_read,
            "totalCacheCreationTokens": tot_cache_create,
            "overallCacheHitRate": overall_hit_rate,
            "totalCost": round(tot_cost, 2),
            "totalPrompts": tot_prompts,
            "totalSteps": tot_steps,
            "activeDaysCount": active_days,
            "avgDailyTokens": round(tot_tokens / max(1, days_cnt)),
            "avgDailyPrompts": round(tot_prompts / max(1, days_cnt), 1),
            "avgDailyCost": round(tot_cost / max(1, days_cnt), 2),
            "busiestDay": {
                "date": busiest.get("date", ""),
                "prompts": busiest.get("prompts", 0),
                "tokens": busiest.get("tokens", 0),
                "cost": busiest.get("cost", 0.0)
            }
        },
        "byAgent": by_agent,
        "byModel": model_list,
        "daily": daily_rows,
        "heatmap": heatmap,
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat()
    }


def main():
    parser = argparse.ArgumentParser(description="Agent Hub Monthly Analytics Engine")
    parser.add_argument("--days", type=int, default=30, help="Number of rolling days to analyze (default: 30)")
    parser.add_argument("--start", type=str, default=None, help="Start date (YYYY-MM-DD) for custom range")
    parser.add_argument("--end", type=str, default=None, help="End date (YYYY-MM-DD) for custom range")
    parser.add_argument("--mode", choices=["rolling", "calendar"], default="rolling", help="Analysis mode")
    parser.add_argument("--force", action="store_true", help="Force re-scan without using cache")
    parser.add_argument("--summary", action="store_true", help="Print human-readable summary instead of JSON")

    args = parser.parse_args()

    start_dt = None
    end_dt = None
    if args.start:
        try:
            start_dt = dt.datetime.strptime(args.start, "%Y-%m-%d").date()
        except ValueError:
            sys.stderr.write(f"Invalid start date: {args.start}\n")
            sys.exit(1)
    if args.end:
        try:
            end_dt = dt.datetime.strptime(args.end, "%Y-%m-%d").date()
        except ValueError:
            sys.stderr.write(f"Invalid end date: {args.end}\n")
            sys.exit(1)

    data = aggregate_monthly(
        num_days=args.days,
        start_date=start_dt,
        end_date=end_dt,
        mode=args.mode,
        force=args.force
    )

    if args.summary:
        s = data["summary"]
        p = data["period"]
        print(f"=== Agent Hub Monthly Analytics ({p['label']}: {p['start']} to {p['end']}) ===")
        print(f"Total Tokens:      {s['totalTokens']:,} (Cache: {s['totalCacheReadTokens']:,}, Hit Rate: {s['overallCacheHitRate']}%)")
        print(f"Estimated Cost:    ${s['totalCost']:.2f} (Avg: ${s['avgDailyCost']:.2f}/day)")
        print(f"Prompts & Turns:   {s['totalPrompts']:,} prompts, {s['totalSteps']:,} steps across {s['activeDaysCount']}/{p['daysCount']} active days")
        print(f"Busiest Day:       {s['busiestDay']['date']} ({s['busiestDay']['prompts']} prompts, {s['busiestDay']['tokens']:,} tokens)")
        print("\nAgent Distribution:")
        for ag, st in data["byAgent"].items():
            print(f"  • {ag.capitalize():12} {st['sharePercent']:5.1f}% tokens ({st['tokens']:,}) | ${st['cost']:.2f} ({st['costPercent']:4.1f}% spend) | {st['prompts']} prompts")
    else:
        print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
