#!/usr/bin/env python3
"""Quota pace forecasting shared by every agent's quota buckets.

For each limit bucket this computes where "even use" would be by now (the pace
tick), whether usage is ahead of it, and a projected run-out. The result is
attached to the bucket as ``pace*`` fields; the legacy ``burnRate*`` /
``forecast*`` fields are left untouched.

Projection model
----------------
* Short windows (<= 6h, e.g. a 5-hour limit): an exponentially weighted rate
  over this window's recent samples (half-life 30 minutes), so newer samples
  weigh most.
* Long windows (weekly / monthly): the window's average rate blended 50/50 with
  the rate over the last 24 hours, so one busy hour does not predict a weekly
  run-out and a quiet weekend does not hide a heavy week.

Status keys (``paceStatus``)
----------------------------
``runsOut``, ``lasts``, ``idle``, ``collecting``, ``noData``, ``early``,
``noUsage``, ``limitReached``, ``noPace``.
"""

from __future__ import annotations

import datetime as dt
import json
import math
import re
import time
from pathlib import Path
from typing import Any

SHORT_WINDOW_MAX_S = 6 * 3600
HALF_LIFE_S = 30 * 60
IDLE_AFTER_S = 3600
MIN_SAMPLE_SPAN_S = 10 * 60
EARLY_FRACTION = 0.02
STALE_SAMPLE_S = 3600
RESET_DROP = 0.05
SAMPLES_FILE = "quota_pace_samples.json"
KEEP_SECONDS = 8 * 24 * 3600
FINE_SECONDS = 3 * 3600
COARSE_BUCKET_S = 600

Sample = list  # [timestamp, used_fraction, reset_epoch_or_0]


def window_seconds(bucket: dict[str, Any]) -> int | None:
    """Best-effort length of a bucket's limit window in seconds."""
    explicit = bucket.get("windowSeconds")
    try:
        if explicit and float(explicit) > 0:
            return int(float(explicit))
    except (TypeError, ValueError):
        pass

    text = " ".join(str(bucket.get(k) or "") for k in ("window", "label", "name", "id")).lower()
    if not text.strip():
        return None
    if "month" in text:
        return 30 * 86400
    if "week" in text or re.search(r"\b7\s*-?\s*d(ay)?s?\b", text):
        return 7 * 86400
    m = re.search(r"(\d+)\s*-?\s*h(?:our|r)?s?\b", text)
    if m:
        return int(m.group(1)) * 3600
    m = re.search(r"(\d+)\s*-?\s*d(?:ay)?s?\b", text)
    if m:
        return int(m.group(1)) * 86400
    if "session" in text:
        return 5 * 3600
    return None


def window_kind(seconds: int | None) -> str:
    """Short tag for a window length: ``5h``, ``7d``, ``30d`` or ``other``."""
    if not seconds:
        return "other"
    if seconds == 5 * 3600:
        return "5h"
    if seconds == 7 * 86400:
        return "7d"
    if seconds == 30 * 86400:
        return "30d"
    return "other"


def parse_reset_epoch(value: Any) -> float | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def format_duration(seconds: float) -> str:
    """Compact duration such as ``42m``, ``1h 9m`` or ``2d 4h``."""
    seconds = max(0.0, seconds)
    minutes = int(round(seconds / 60.0))
    if minutes < 1:
        return "<1m"
    if minutes < 60:
        return f"{minutes}m"
    hours, mins = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h {mins}m" if mins else f"{hours}h"
    days, hrs = divmod(hours, 24)
    return f"{days}d {hrs}h" if hrs else f"{days}d"


def bucket_used_fraction(bucket: dict[str, Any]) -> float | None:
    rem = bucket.get("remainingFraction")
    try:
        if rem is not None:
            return min(1.0, max(0.0, 1.0 - float(rem)))
        pct = bucket.get("usedPercent")
        if pct is not None:
            return min(1.0, max(0.0, float(pct) / 100.0))
    except (TypeError, ValueError):
        return None
    return None


# --- sample history -------------------------------------------------------

def load_samples(cache_dir: Path) -> dict[str, list[Sample]]:
    try:
        with open(Path(cache_dir) / SAMPLES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {k: v for k, v in data.items() if isinstance(v, list)}
    except Exception:
        pass
    return {}


def save_samples(cache_dir: Path, store: dict[str, list[Sample]]) -> None:
    try:
        cache_dir = Path(cache_dir)
        cache_dir.mkdir(parents=True, exist_ok=True)
        tmp = cache_dir / (SAMPLES_FILE + ".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(store, f)
        tmp.replace(cache_dir / SAMPLES_FILE)
    except Exception:
        pass


def _prune(samples: list[Sample], now: float) -> list[Sample]:
    """Keep every recent sample, thin older ones to one per ten minutes."""
    out: list[Sample] = []
    seen: set[int] = set()
    for s in samples:
        age = now - s[0]
        if age > KEEP_SECONDS:
            continue
        if age > FINE_SECONDS:
            slot = int(s[0] // COARSE_BUCKET_S)
            if slot in seen:
                continue
            seen.add(slot)
        out.append(s)
    return out


def record_sample(samples: list[Sample], now: float, used: float, reset_epoch: float | None) -> list[Sample]:
    """Append a sample, dropping history from before a window reset."""
    reset_val = float(reset_epoch or 0.0)
    if samples:
        prev = samples[-1]
        reset_moved = reset_val and prev[2] and abs(reset_val - prev[2]) > 600
        if used < prev[1] - RESET_DROP or reset_moved:
            samples = []
    if samples and now - samples[-1][0] < 20:
        samples[-1] = [now, used, reset_val]
    else:
        samples.append([now, used, reset_val])
    return _prune(samples, now)


# --- rate estimation ------------------------------------------------------

def weighted_recent_rate(samples: list[Sample], now: float) -> float | None:
    """Fraction-of-limit per hour, newest samples weighing most."""
    num = 0.0
    den = 0.0
    for a, b in zip(samples, samples[1:]):
        dt_s = b[0] - a[0]
        if dt_s <= 0:
            continue
        age = now - (a[0] + b[0]) / 2.0
        w = math.pow(0.5, max(0.0, age) / HALF_LIFE_S)
        num += max(0.0, b[1] - a[1]) * w
        den += (dt_s / 3600.0) * w
    if den <= 0:
        return None
    return num / den


def rate_since(samples: list[Sample], now: float, horizon_s: float) -> float | None:
    """Plain average rise rate (fraction/hour) over the last ``horizon_s``."""
    cutoff = now - horizon_s
    window = [s for s in samples if s[0] >= cutoff]
    if len(window) < 2:
        return None
    span = window[-1][0] - window[0][0]
    if span < 3600:
        return None
    return max(0.0, window[-1][1] - window[0][1]) / (span / 3600.0)


def last_rise_age(samples: list[Sample], now: float) -> float | None:
    """Seconds since usage last increased, or None if it never has in history."""
    for i in range(len(samples) - 1, 0, -1):
        if samples[i][1] > samples[i - 1][1] + 1e-6:
            return now - samples[i][0]
    return None


# --- bucket enrichment ----------------------------------------------------

def _result(status: str, text: str, severity: str = "ok", **extra: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"paceStatus": status, "paceText": text, "paceSeverity": severity}
    out.update(extra)
    return out


def compute_pace(
    bucket: dict[str, Any],
    samples: list[Sample],
    now: float,
    sample_age_s: float | None = None,
) -> dict[str, Any]:
    """Return the ``pace*`` fields for one bucket."""
    win_s = window_seconds(bucket)
    used = bucket_used_fraction(bucket)
    base: dict[str, Any] = {
        "windowSeconds": win_s or 0,
        "windowKind": window_kind(win_s),
        "paceMarker": None,
        "paceAhead": False,
        "paceRatePerHour": 0.0,
        "paceRunOutSeconds": None,
        "paceProjectedUsed": None,
    }
    if used is None:
        base.update(_result("noPace", "No pace for this limit"))
        return base

    if used >= 0.995:
        base.update(_result("limitReached", "Limit reached", "critical"))
        return base

    reset_epoch = parse_reset_epoch(bucket.get("resetTime") or bucket.get("resetsAt") or bucket.get("reset_time"))
    if not win_s or reset_epoch is None:
        base.update(_result("noPace", "No pace for this limit"))
        return base

    remaining_s = max(0.0, reset_epoch - now)
    elapsed_s = min(float(win_s), max(0.0, win_s - remaining_s))
    elapsed_frac = elapsed_s / win_s
    pace_pct = int(round(elapsed_frac * 100))
    base["paceMarker"] = round(elapsed_frac, 4)
    base["paceAhead"] = used > elapsed_frac + 1e-6
    suffix = f" · pace {pace_pct}%"

    if elapsed_frac < EARLY_FRACTION:
        base.update(_result("early", f"Pace starts after {int(EARLY_FRACTION * 100)}% of the window"))
        return base
    if used < 0.005:
        base.update(_result("noUsage", "No usage yet"))
        return base

    short = win_s <= SHORT_WINDOW_MAX_S
    if short:
        if sample_age_s is not None and sample_age_s > STALE_SAMPLE_S:
            base.update(_result("noData", "No recent data" + suffix))
            return base
        span = samples[-1][0] - samples[0][0] if len(samples) >= 2 else 0.0
        if span < MIN_SAMPLE_SPAN_S:
            base.update(_result("collecting", "Collecting data" + suffix))
            return base
        rise_age = last_rise_age(samples, now)
        idle_for = (now - samples[0][0]) if rise_age is None else rise_age
        if idle_for >= IDLE_AFTER_S:
            base.update(_result("idle", f"Idle {format_duration(idle_for)}" + suffix))
            return base
        rate = weighted_recent_rate(samples, now) or 0.0
    else:
        avg_rate = used / (elapsed_s / 3600.0) if elapsed_s > 0 else 0.0
        day_rate = rate_since(samples, now, 24 * 3600)
        rate = avg_rate if day_rate is None else 0.5 * avg_rate + 0.5 * day_rate

    base["paceRatePerHour"] = round(rate * 100.0, 2)
    if rate <= 1e-9:
        base.update(_result("lasts", "Lasts until reset" + suffix, paceProjectedUsed=round(used, 4)))
        return base

    remaining_h = remaining_s / 3600.0
    runout_s = ((1.0 - used) / rate) * 3600.0
    projected = min(1.0, used + rate * remaining_h)
    base["paceProjectedUsed"] = round(projected, 4)
    if runout_s < remaining_s:
        severity = "critical" if (runout_s < 3600 or runout_s < remaining_s * 0.5) else "warning"
        base.update(_result("runsOut", f"Runs out in {format_duration(runout_s)}" + suffix, severity,
                            paceRunOutSeconds=int(runout_s), paceProjectedUsed=1.0))
    else:
        base.update(_result("lasts", "Lasts until reset" + suffix))
    return base


def apply_pace(
    cache_dir: Path,
    agent_id: str,
    groups: list[dict[str, Any]],
    now: float | None = None,
    sample_age_s: float | None = None,
) -> None:
    """Record samples for every bucket in ``groups`` and attach pace fields in place."""
    if not groups:
        return
    now = time.time() if now is None else now
    store = load_samples(cache_dir)
    changed = False
    for group in groups:
        for bucket in group.get("buckets") or []:
            used = bucket_used_fraction(bucket)
            key = f"{agent_id}|{group.get('name', '')}|{bucket.get('id', '')}"
            samples = store.get(key, [])
            if used is not None:
                reset_epoch = parse_reset_epoch(bucket.get("resetTime") or bucket.get("resetsAt"))
                samples = record_sample(samples, now, used, reset_epoch)
                store[key] = samples
                changed = True
            bucket.update(compute_pace(bucket, samples, now, sample_age_s))
    if changed:
        save_samples(cache_dir, store)
