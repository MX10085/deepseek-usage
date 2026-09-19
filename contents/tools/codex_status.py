#!/usr/bin/env python3
"""Return Codex subscription and OpenAI API usage as one JSON document."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def empty_result() -> dict[str, Any]:
    return {"status": "unavailable", "source": "none", "updatedAt": int(time.time()),
            "subscription": None, "api": None, "error": ""}


def session_files(codex_home: Path) -> list[Path]:
    root = codex_home / "sessions"
    if not root.is_dir():
        return []
    files = list(root.rglob("*.jsonl"))
    files.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return files


def timestamp_epoch(value: Any, fallback: int) -> int:
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str) and value:
        try:
            return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
        except ValueError:
            pass
    return fallback


def read_recent_events(path: Path) -> tuple[
        tuple[int, dict[str, Any]] | None,
        dict[str, Any] | None,
        dict[str, tuple[int, dict[str, Any]]]]:
    latest_tokens = None
    latest_context = None
    latest_limits: dict[str, tuple[int, dict[str, Any]]] = {}
    modified = int(path.stat().st_mtime)
    try:
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                if '"type":"token_count"' not in line and '"type":"turn_context"' not in line:
                    continue
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if item.get("type") == "turn_context":
                    latest_context = item.get("payload") or latest_context
                elif item.get("type") == "event_msg":
                    payload = item.get("payload") or {}
                    if payload.get("type") == "token_count":
                        observed = timestamp_epoch(item.get("timestamp"), modified)
                        latest_tokens = (observed, payload)
                        limits = payload.get("rate_limits") or {}
                        for name in ("primary", "secondary"):
                            value = limits.get(name)
                            if isinstance(value, dict) and value:
                                previous = latest_limits.get(name)
                                merged = dict(previous[1]) if previous else {}
                                merged.update(value)
                                latest_limits[name] = (observed, merged)
    except OSError:
        return None, None, {}
    return latest_tokens, latest_context, latest_limits


def limit_cache_path(codex_home: Path) -> Path:
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    digest = hashlib.sha256(str(codex_home.resolve()).encode()).hexdigest()[:12]
    return cache_root / "ai-usage-monitor" / ("codex-limits-" + digest + ".json")


def load_limit_cache(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_limit_cache(path: Path, value: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        temporary.replace(path)
    except OSError:
        pass


def normalize_limit(name: str, observed_limit: tuple[int, dict[str, Any]] | None,
                    cached: dict[str, Any], now: int) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    cached_limit = cached.get(name) if isinstance(cached.get(name), dict) else {}
    if observed_limit:
        observed, raw = observed_limit
        value = dict(raw)
    elif cached_limit:
        observed = int(cached_limit.get("observed_at") or 0)
        value = dict(cached_limit.get("value") or {})
    else:
        return None, {}

    cached_value = cached_limit.get("value") if isinstance(cached_limit.get("value"), dict) else {}
    for field in ("used_percent", "window_minutes", "resets_at"):
        if value.get(field) is None and cached_value.get(field) is not None:
            value[field] = cached_value[field]

    window_minutes = int(value.get("window_minutes") or 0)
    reset_at = int(value.get("resets_at") or 0)
    estimated_reset = False
    projected_usage = False

    if reset_at <= 0 and window_minutes > 0:
        reset_at = observed + window_minutes * 60
        estimated_reset = True

    if reset_at > 0 and window_minutes > 0 and reset_at <= now:
        window_seconds = window_minutes * 60
        reset_at += ((now - reset_at) // window_seconds + 1) * window_seconds
        # The newest quota sample belongs to an expired window. Show the new
        # window immediately and let the next Codex event replace the estimate.
        if observed < reset_at - window_seconds:
            value["used_percent"] = 0.0
            projected_usage = True
        estimated_reset = True

    if reset_at > 0:
        value["resets_at"] = reset_at
    value["estimated_reset"] = estimated_reset
    value["projected_usage"] = projected_usage
    cache_entry = {"observed_at": observed, "value": {
        key: value[key] for key in ("used_percent", "window_minutes", "resets_at") if value.get(key) is not None
    }}
    return value, cache_entry


def local_codex_status(codex_home: Path) -> dict[str, Any] | None:
    latest: tuple[int, dict[str, Any], dict[str, Any], Path] | None = None
    latest_limits: dict[str, tuple[int, dict[str, Any]]] = {}
    for path in session_files(codex_home)[:30]:
        token_event, context, file_limits = read_recent_events(path)
        if token_event and (latest is None or token_event[0] > latest[0]):
            latest = (token_event[0], token_event[1], context or {}, path)
        for name, candidate in file_limits.items():
            if name not in latest_limits:
                latest_limits[name] = candidate
            elif candidate[0] > latest_limits[name][0]:
                merged = dict(latest_limits[name][1])
                merged.update(candidate[1])
                latest_limits[name] = (candidate[0], merged)
            else:
                merged = dict(candidate[1])
                merged.update(latest_limits[name][1])
                latest_limits[name] = (latest_limits[name][0], merged)
    if latest is None:
        return None

    observed, token_event, context, path = latest
    info = token_event.get("info") or {}
    total = info.get("total_token_usage") or {}
    limits = token_event.get("rate_limits") or {}
    window = int(info.get("model_context_window") or 0)
    last = info.get("last_token_usage") or {}
    context_used = int(last.get("input_tokens") or 0)

    cache_path = limit_cache_path(codex_home)
    cache = load_limit_cache(cache_path)
    now = int(time.time())
    primary, primary_cache = normalize_limit("primary", latest_limits.get("primary"), cache, now)
    secondary, secondary_cache = normalize_limit("secondary", latest_limits.get("secondary"), cache, now)
    plan_type = limits.get("plan_type") or cache.get("planType") or ""
    next_cache = {"primary": primary_cache, "secondary": secondary_cache,
                  "planType": plan_type, "updated_at": now}
    save_limit_cache(cache_path, next_cache)

    return {
        "sessionFile": str(path), "model": context.get("model") or "",
        "effort": context.get("effort") or "", "cwd": context.get("cwd") or "",
        "planType": plan_type,
        "context": {"used": context_used, "limit": window,
                    "usedPercent": round(context_used * 100 / window, 1) if window else 0},
        "tokens": {"input": int(total.get("input_tokens") or 0),
                   "cachedInput": int(total.get("cached_input_tokens") or 0),
                   "output": int(total.get("output_tokens") or 0),
                   "reasoning": int(total.get("reasoning_output_tokens") or 0),
                   "total": int(total.get("total_tokens") or 0)},
        "primary": primary, "secondary": secondary,
        "credits": limits.get("credits"), "modifiedAt": observed,
    }


def api_get(path: str, key: str, params: dict[str, Any]) -> dict[str, Any]:
    query = urllib.parse.urlencode(params, doseq=True)
    request = urllib.request.Request("https://api.openai.com/v1" + path + "?" + query,
        headers={"Authorization": "Bearer " + key, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def sum_usage(page: dict[str, Any]) -> dict[str, int]:
    totals = {"input": 0, "cachedInput": 0, "output": 0, "requests": 0}
    for bucket in page.get("data") or []:
        for row in bucket.get("results") or []:
            totals["input"] += int(row.get("input_tokens") or 0)
            totals["cachedInput"] += int(row.get("input_cached_tokens") or 0)
            totals["output"] += int(row.get("output_tokens") or 0)
            totals["requests"] += int(row.get("num_model_requests") or 0)
    return totals


def sum_costs(page: dict[str, Any]) -> tuple[float, str]:
    value, currency = 0.0, "usd"
    for bucket in page.get("data") or []:
        for row in bucket.get("results") or []:
            amount = row.get("amount") or {}
            value += float(amount.get("value") or 0)
            currency = amount.get("currency") or currency
    return round(value, 6), currency


def openai_api_status(key: str) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    day_start = int(now.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
    month_start = int(now.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp())
    common = {"bucket_width": "1d", "limit": 31}
    usage_day = api_get("/organization/usage/completions", key, {**common, "start_time": day_start})
    usage_month = api_get("/organization/usage/completions", key, {**common, "start_time": month_start})
    cost_day = api_get("/organization/costs", key, {**common, "start_time": day_start})
    cost_month = api_get("/organization/costs", key, {**common, "start_time": month_start})
    day_cost, currency = sum_costs(cost_day)
    month_cost, month_currency = sum_costs(cost_month)
    return {"today": {"tokens": sum_usage(usage_day), "cost": day_cost},
            "month": {"tokens": sum_usage(usage_month), "cost": month_cost},
            "currency": month_currency or currency}


def load_key(key_file: str) -> str:
    env_key = os.environ.get("OPENAI_ADMIN_KEY", "").strip()
    if env_key:
        return env_key
    if key_file:
        try:
            return Path(key_file).expanduser().read_text(encoding="utf-8").strip()
        except OSError:
            return ""
    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("auto", "subscription", "api", "both"), default="auto")
    parser.add_argument("--codex-home", default=os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    parser.add_argument("--api-key-file", default="")
    args = parser.parse_args()
    result = empty_result()
    try:
        if args.mode in ("auto", "subscription", "both"):
            result["subscription"] = local_codex_status(Path(args.codex_home).expanduser())
        key = load_key(args.api_key_file)
        if args.mode in ("api", "both") or (args.mode == "auto" and key):
            if key:
                result["api"] = openai_api_status(key)
            elif args.mode == "api":
                result["error"] = "未配置 OpenAI Admin API Key"
        if result["subscription"] and result["api"]:
            result["source"] = "both"
        elif result["api"]:
            result["source"] = "api"
        elif result["subscription"]:
            result["source"] = "subscription"
        result["status"] = "ok" if result["source"] != "none" else "unavailable"
    except urllib.error.HTTPError as exc:
        result["status"], result["error"] = "error", "OpenAI API HTTP " + str(exc.code)
    except (urllib.error.URLError, TimeoutError) as exc:
        result["status"] = "error"
        result["error"] = "OpenAI API 连接失败：" + str(exc.reason if hasattr(exc, "reason") else exc)
    except Exception as exc:
        result["status"], result["error"] = "error", str(exc)
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
