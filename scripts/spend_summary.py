#!/usr/bin/env python3
"""Rolling spend summary (estimated API cost) for the Overview tab, Spend tab, and bar badge.

Built from ``monthly_analytics.aggregate_monthly`` and cached for a few minutes
so the 10-60 s widget refresh never rescans transcripts.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Callable

CACHE_FILE = "spend_summary.json"
TTL_S = 300
AGENTS = ("claude", "antigravity", "codex")


def summarize(analytics: dict[str, Any]) -> dict[str, Any]:
    """Reduce an analytics payload to today / 7-day / 30-day spend figures and graphical charts."""
    daily = analytics.get("daily") or []
    last7 = daily[-7:]
    last14 = daily[-14:]

    def agent_cost(rows: list[dict[str, Any]], agent: str) -> float:
        return round(sum(float(((r.get("agents") or {}).get(agent) or {}).get("cost", 0.0)) for r in rows), 2)

    def agent_tokens(rows: list[dict[str, Any]], agent: str) -> int:
        return sum(int(((r.get("agents") or {}).get(agent) or {}).get("tokens", 0)) for r in rows)

    today = daily[-1] if daily else {}
    week_cost = round(sum(float(r.get("cost", 0.0)) for r in last7), 2)
    month_cost = round(sum(float(r.get("cost", 0.0)) for r in daily), 2)
    avg_daily_week = round(week_cost / max(1, len(last7)), 2)

    # Graphical 14-day history for timeline/histogram charts
    daily_history: list[dict[str, Any]] = []
    peak_daily_cost = 0.0
    for r in last14:
        c = round(float(r.get("cost", 0.0)), 2)
        if c > peak_daily_cost:
            peak_daily_cost = c
        daily_history.append({
            "date": r.get("date", ""),
            "dayOfWeek": r.get("dayOfWeek", ""),
            "dayOfMonth": int(r.get("dayOfMonth", 0)),
            "cost": c,
            "tokens": int(r.get("tokens", 0)),
            "prompts": int(r.get("prompts", 0)),
            "claudeCost": round(float(((r.get("agents") or {}).get("claude") or {}).get("cost", 0.0)), 2),
            "antigravityCost": round(float(((r.get("agents") or {}).get("antigravity") or {}).get("cost", 0.0)), 2),
            "codexCost": round(float(((r.get("agents") or {}).get("codex") or {}).get("cost", 0.0)), 2),
        })

    # Agent breakdown with 7d and 30d spend & token metrics
    by_agent_analytics = analytics.get("byAgent") or {}
    by_agent_detail: dict[str, dict[str, Any]] = {}
    for a in AGENTS:
        a_stat = by_agent_analytics.get(a) or {}
        m_cost = round(float(a_stat.get("cost", 0.0)) or agent_cost(daily, a), 2)
        w_cost = agent_cost(last7, a)
        w_tokens = agent_tokens(last7, a)
        m_tokens = int(a_stat.get("tokens", 0)) or agent_tokens(daily, a)
        by_agent_detail[a] = {
            "weekCost": w_cost,
            "monthCost": m_cost,
            "weekTokens": w_tokens,
            "monthTokens": m_tokens,
            "costPercent": round((m_cost / max(0.01, month_cost)) * 100.0, 1) if month_cost > 0 else 0.0,
        }

    # Top models by spend
    raw_models = analytics.get("byModel") or []
    top_models: list[dict[str, Any]] = []
    for m in raw_models[:6]:
        top_models.append({
            "name": m.get("name", "Unknown"),
            "tokens": int(m.get("tokens", 0)),
            "cost": round(float(m.get("cost", 0.0)), 2),
            "sharePercent": float(m.get("sharePercent", 0.0)),
        })

    # Cache savings & summary metrics
    summary_data = analytics.get("summary") or {}
    cache_savings = {
        "cacheReadTokens": int(summary_data.get("totalCacheReadTokens", 0)),
        "overallCacheHitRate": float(summary_data.get("overallCacheHitRate", 0.0)),
        "activeDays": int(summary_data.get("activeDaysCount", 0)),
        "busiestDay": summary_data.get("busiestDay") or {},
    }

    return {
        "todayCost": round(float(today.get("cost", 0.0)), 2),
        "weekCost": week_cost,
        "monthCost": month_cost,
        "avgDailyCost": avg_daily_week,
        "projectedMonthCost": round(avg_daily_week * 30, 2),
        "days": len(daily),
        "weekByAgent": {a: agent_cost(last7, a) for a in AGENTS},
        "monthByAgent": {a: agent_cost(daily, a) for a in AGENTS},
        # Graphical & extended spend data
        "dailyHistory": daily_history,
        "peakDailyCost": peak_daily_cost,
        "byAgentDetail": by_agent_detail,
        "topModels": top_models,
        "cacheSavings": cache_savings,
        "pricing": analytics.get("pricing") or {},
    }


def get_spend(
    cache_dir: Path,
    now: float | None = None,
    ttl: float = TTL_S,
    aggregate: Callable[[], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Return the spend summary, recomputing at most once per ``ttl`` seconds."""
    now = time.time() if now is None else now
    path = Path(cache_dir) / CACHE_FILE
    try:
        with open(path, "r", encoding="utf-8") as f:
            cached = json.load(f)
        if isinstance(cached, dict) and now - float(cached.get("computedAt", 0)) < ttl:
            return cached
    except Exception:
        pass

    try:
        if aggregate is None:
            try:
                import monthly_analytics
            except ImportError:
                from scripts import monthly_analytics
            aggregate = lambda: monthly_analytics.aggregate_monthly(num_days=30)  # noqa: E731
        result = summarize(aggregate())
    except Exception:
        return {}

    result["computedAt"] = now
    try:
        Path(cache_dir).mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(result, f)
        tmp.replace(path)
    except Exception:
        pass
    return result
