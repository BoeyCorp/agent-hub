#!/usr/bin/env python3
"""Shared per-token model prices for every agent's cost estimates.

Price lookup order for a model:

1. OpenRouter ``/api/v1/models`` (fetched at most once a day, cached)
2. LiteLLM ``model_prices_and_context_window.json`` (same refresh, cached)
3. ``pricing.json`` next to this script (bundled fallback, works offline)

Costs are API-equivalent estimates: what the same tokens would cost on the
pay-per-token API. Subscription plans do not bill this way.

A model that matches no price list costs 0.0 and is reported in
``info()["unknownModels"]`` instead of being priced at a guessed rate.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

OPENROUTER_URL = "https://openrouter.ai/api/v1/models"
LITELLM_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
LITELLM_PROVIDERS = {"anthropic", "openai", "gemini", "vertex_ai-language-models"}
BUNDLED_FILE = Path(__file__).resolve().with_name("pricing.json")
CACHE_FILE = "model_prices.json"
REFRESH_FLAG = "model_prices.refresh"
MAX_AGE_S = 24 * 3600
RETRY_AFTER_S = 30 * 60
FETCH_TIMEOUT_S = 20

# Rates are USD per token: (input, output, cache read, cache write)
Rates = tuple[float, float, float, float]
FREE: Rates = (0.0, 0.0, 0.0, 0.0)
FREE_MODELS = {"synthetic"}

_tables: dict[str, Any] | None = None
_unknown: set[str] = set()


def default_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "agent-hub"


def normalize(name: str) -> str:
    """Reduce a model name or price-list id to one comparable key.

    ``Claude Opus 5.5 (Medium)``, ``claude-opus-5-5``, ``anthropic/claude-opus-5.5``
    and ``claude-opus-5-5-20261001[1m]`` all become ``claude-opus-5-5``.
    """
    n = (name or "").strip().lower()
    n = n.rsplit("/", 1)[-1]
    n = n.split(":", 1)[0]
    n = re.sub(r"\[[^\]]*\]|\([^)]*\)|<|>", " ", n)
    n = re.sub(r"[\s._]+", "-", n)
    n = re.sub(r"-(\d{8}|latest)$", "", n.strip("-"))
    return re.sub(r"-+", "-", n).strip("-")


def _rate(value: Any) -> float | None:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    return f if f >= 0 else None


def _complete(inp: float, out: float, cread: float | None, cwrite: float | None) -> Rates:
    # When a list omits cache prices, use the usual ratios: read 10%, write 125% of input.
    return (inp, out, inp * 0.1 if cread is None else cread, inp * 1.25 if cwrite is None else cwrite)


def parse_openrouter(payload: dict[str, Any]) -> dict[str, Rates]:
    out: dict[str, Rates] = {}
    for m in payload.get("data") or []:
        mid = str(m.get("id") or "")
        if not mid or ":" in mid:
            continue
        p = m.get("pricing") or {}
        inp, outp = _rate(p.get("prompt")), _rate(p.get("completion"))
        if inp is None or outp is None or (inp == 0 and outp == 0):
            continue
        key = normalize(mid)
        # Keep the first-party listing when several vendors list the same model
        if key in out and mid.split("/")[0] not in ("anthropic", "openai", "google"):
            continue
        out[key] = _complete(inp, outp, _rate(p.get("input_cache_read")), _rate(p.get("input_cache_write")))
    return out


def parse_litellm(payload: dict[str, Any]) -> dict[str, Rates]:
    out: dict[str, Rates] = {}
    for k, v in payload.items():
        if not isinstance(v, dict) or "/" in k or v.get("litellm_provider") not in LITELLM_PROVIDERS:
            continue
        inp, outp = _rate(v.get("input_cost_per_token")), _rate(v.get("output_cost_per_token"))
        if inp is None or outp is None or (inp == 0 and outp == 0):
            continue
        out.setdefault(normalize(k), _complete(
            inp, outp,
            _rate(v.get("cache_read_input_token_cost")),
            _rate(v.get("cache_creation_input_token_cost")),
        ))
    return out


def load_bundled(path: Path = BUNDLED_FILE) -> dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return {"updated": "", "aliases": {}, "models": {}}
    models: dict[str, Rates] = {}
    for k, v in (data.get("models") or {}).items():
        try:
            per_m = 1e-6
            models[normalize(k)] = _complete(
                float(v["input"]) * per_m,
                float(v["output"]) * per_m,
                None if v.get("cacheRead") is None else float(v["cacheRead"]) * per_m,
                None if v.get("cacheWrite") is None else float(v["cacheWrite"]) * per_m,
            )
        except Exception:
            continue
    aliases = {normalize(k): normalize(v) for k, v in (data.get("aliases") or {}).items()}
    return {"updated": str(data.get("updated") or ""), "aliases": aliases, "models": models}


def load_cached(cache_dir: Path) -> dict[str, Any]:
    try:
        with open(Path(cache_dir) / CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def _tables_for(cache_dir: Path | None = None) -> dict[str, Any]:
    global _tables
    if _tables is not None and cache_dir is None:
        return _tables
    cached = load_cached(cache_dir or default_cache_dir())
    bundled = load_bundled()
    sources = []
    for name, label in (("openrouter", "OpenRouter"), ("litellm", "LiteLLM")):
        table = {k: tuple(v) for k, v in (cached.get(name) or {}).items() if isinstance(v, list) and len(v) == 4}
        if table:
            sources.append((label, table))
    sources.append(("Bundled", bundled["models"]))
    tables = {
        "sources": sources,
        "aliases": bundled["aliases"],
        "fetchedAt": str(cached.get("fetchedAt") or ""),
        "bundledUpdated": bundled["updated"],
    }
    if cache_dir is None:
        _tables = tables
    return tables


def reset() -> None:
    """Forget loaded tables and unknown models (tests, long-running callers)."""
    global _tables
    _tables = None
    _unknown.clear()


def _match(key: str, table: dict[str, Rates]) -> Rates | None:
    if key in table:
        return table[key]
    # Longest price id that the local name extends: gpt-6-luna-high -> gpt-6-luna
    best = ""
    for k in table:
        if len(k) > len(best) and key.startswith(k + "-"):
            best = k
    return table[best] if best else None


def lookup(model: str, tables: dict[str, Any] | None = None) -> tuple[Rates, str] | None:
    """Rates and source label for ``model``, or None when no list knows it."""
    key = normalize(model)
    if key in FREE_MODELS:
        return FREE, "Free"
    t = tables or _tables_for()
    key = t["aliases"].get(key, key)
    for label, table in t["sources"]:
        r = _match(key, table)
        if r is not None:
            return r, label
    return None


def cost(model: str, input_tokens: int, output_tokens: int, cache_read: int = 0, cache_write: int = 0) -> float:
    found = lookup(model)
    if found is None:
        if model and (input_tokens or output_tokens or cache_read or cache_write):
            _unknown.add(str(model))
        return 0.0
    r_in, r_out, r_read, r_write = found[0]
    return input_tokens * r_in + output_tokens * r_out + cache_read * r_read + cache_write * r_write


def version(cache_dir: Path | None = None) -> str:
    """Short hash of the active price tables; changes when any price changes."""
    t = _tables_for(cache_dir)
    h = hashlib.sha1()
    for label, table in t["sources"]:
        h.update(label.encode())
        h.update(json.dumps(sorted(table.items())).encode())
    h.update(json.dumps(sorted(t["aliases"].items())).encode())
    return h.hexdigest()[:12]


def info() -> dict[str, Any]:
    """What the UI shows next to costs: price source, date, unknown models."""
    t = _tables_for()
    primary = t["sources"][0][0]
    date = t["fetchedAt"] if primary != "Bundled" else t["bundledUpdated"]
    return {
        "basis": "API-equivalent",
        "source": primary,
        "sources": [label for label, _ in t["sources"]],
        "updatedAt": date,
        "version": version(),
        "unknownModels": sorted(_unknown),
    }


def _fetch_json(url: str) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": "agent-hub-omarchy/1.0"})
    with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT_S) as resp:
        return json.loads(resp.read().decode("utf-8"))


def refresh(cache_dir: Path) -> dict[str, Any]:
    """Fetch both price lists and store them. Keeps the previous list if a fetch fails."""
    cache_dir = Path(cache_dir)
    previous = load_cached(cache_dir)
    result: dict[str, Any] = {"fetchedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "errors": {}}
    for name, url, parse in (("openrouter", OPENROUTER_URL, parse_openrouter), ("litellm", LITELLM_URL, parse_litellm)):
        try:
            table = parse(_fetch_json(url))
            if not table:
                raise ValueError("empty price list")
            result[name] = {k: list(v) for k, v in table.items()}
        except Exception as e:
            result["errors"][name] = str(e)[:200]
            if previous.get(name):
                result[name] = previous[name]
    if len(result["errors"]) == 2:
        # Nothing new: keep the old file (and its age) so the next scan retries after RETRY_AFTER_S
        result["fetchedAt"] = previous.get("fetchedAt", "")
        return result
    cache_dir.mkdir(parents=True, exist_ok=True)
    tmp = cache_dir / (CACHE_FILE + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(result, f)
    tmp.replace(cache_dir / CACHE_FILE)
    return result


def needs_refresh(cache_dir: Path, now: float | None = None) -> bool:
    now = time.time() if now is None else now
    cache_dir = Path(cache_dir)
    try:
        if now - (cache_dir / REFRESH_FLAG).stat().st_mtime < RETRY_AFTER_S:
            return False
    except OSError:
        pass
    try:
        return now - (cache_dir / CACHE_FILE).stat().st_mtime > MAX_AGE_S
    except OSError:
        return True


def ensure_fresh(cache_dir: Path | None = None) -> None:
    """Start a detached daily refresh when the cached prices are old. Never blocks."""
    cache_dir = Path(cache_dir or default_cache_dir())
    if not needs_refresh(cache_dir):
        return
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / REFRESH_FLAG).touch()
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--refresh", str(cache_dir)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Agent Hub model prices")
    parser.add_argument("--refresh", nargs="?", const="", metavar="CACHE_DIR", help="Fetch current prices now")
    parser.add_argument("--model", action="append", default=[], help="Show the rates used for a model")
    args = parser.parse_args()

    if args.refresh is not None:
        res = refresh(Path(args.refresh) if args.refresh else default_cache_dir())
        print(json.dumps({
            "fetchedAt": res.get("fetchedAt"),
            "openrouter": len(res.get("openrouter") or {}),
            "litellm": len(res.get("litellm") or {}),
            "errors": res.get("errors"),
        }, indent=2))
    for m in args.model:
        found = lookup(m)
        if found is None:
            print(f"{m}: unknown")
        else:
            r, src = found
            print(f"{m}: {src} in ${r[0] * 1e6:g} out ${r[1] * 1e6:g} cache-read ${r[2] * 1e6:g} cache-write ${r[3] * 1e6:g} per 1M")
    if args.refresh is None and not args.model:
        print(json.dumps(info(), indent=2))


if __name__ == "__main__":
    main()
