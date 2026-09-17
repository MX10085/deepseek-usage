#!/usr/bin/env python3
"""Return Codex subscription and OpenAI API usage as one JSON document."""

from __future__ import annotations

import argparse
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


def read_recent_events(path: Path) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    latest_tokens = None
    latest_context = None
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
                        latest_tokens = payload
    except OSError:
        return None, None
    return latest_tokens, latest_context


def local_codex_status(codex_home: Path) -> dict[str, Any] | None:
    for path in session_files(codex_home)[:20]:
        token_event, context = read_recent_events(path)
        if not token_event:
            continue
        info = token_event.get("info") or {}
        total = info.get("total_token_usage") or {}
        limits = token_event.get("rate_limits") or {}
        context = context or {}
        window = int(info.get("model_context_window") or 0)
        last = info.get("last_token_usage") or {}
        context_used = int(last.get("input_tokens") or 0)
        return {
            "sessionFile": str(path), "model": context.get("model") or "",
            "effort": context.get("effort") or "", "cwd": context.get("cwd") or "",
            "planType": limits.get("plan_type") or "",
            "context": {"used": context_used, "limit": window,
                        "usedPercent": round(context_used * 100 / window, 1) if window else 0},
            "tokens": {"input": int(total.get("input_tokens") or 0),
                       "cachedInput": int(total.get("cached_input_tokens") or 0),
                       "output": int(total.get("output_tokens") or 0),
                       "reasoning": int(total.get("reasoning_output_tokens") or 0),
                       "total": int(total.get("total_tokens") or 0)},
            "primary": limits.get("primary"), "secondary": limits.get("secondary"),
            "credits": limits.get("credits"), "modifiedAt": int(path.stat().st_mtime),
        }
    return None


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
