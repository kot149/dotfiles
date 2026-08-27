#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
AUTH_DIR = Path(os.environ.get("CLI_PROXY_API_AUTH_DIR", Path.home() / ".cli-proxy-api"))
CACHE_FILE = Path(os.environ.get("CODEX_WEEKLY_CACHE", Path.home() / ".claude" / "codex-weekly-limit.json"))
# Window name aliases and the plausible range of limit_window_seconds used as a fallback probe.
WINDOW_SPECS = (
    ("five", ("primary_window", "primaryWindow", "five_hour", "fiveHour"), (3600, 36000)),
    ("weekly", ("secondary_window", "secondaryWindow", "weekly", "weekly_window", "weeklyWindow"), (500000, 700000)),
)
USAGE_URLS = (
    "https://chatgpt.com/backend-api/wham/usage",
    "https://chatgpt.com/backend-api/codex/usage",
)
CACHE_TTL = 300
DEBUG = os.environ.get("CODEX_WEEKLY_DEBUG") == "1"


def debug(message):
    if DEBUG:
        print(message, file=sys.stderr)


def read_auth():
    configured = os.environ.get("CLI_PROXY_API_AUTH_FILE")
    if configured:
        paths = [Path(configured)]
    else:
        paths = [CODEX_HOME / "auth.json"] + sorted(AUTH_DIR.glob("codex-*.json"))
    candidates = []
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if data.get("disabled") is True:
            continue
        nested = data.get("tokens") or data.get("token_data") or {}
        access_token = nested.get("access_token") or data.get("access_token")
        account_id = nested.get("account_id") or data.get("account_id")
        if access_token and account_id:
            candidate = (str(nested.get("last_refresh") or data.get("last_refresh", "")), access_token, account_id)
            if path == CODEX_HOME / "auth.json":
                return candidate[1:]
            candidates.append(candidate)
    if not candidates:
        debug("no usable Codex auth file")
        return None
    _, access_token, account_id = max(candidates, key=lambda item: item[0])
    return access_token, account_id


def read_cached():
    try:
        data = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        updated = float(data.get("updated_at", 0))
    except (OSError, ValueError, TypeError):
        return {}, 0
    found = {}
    for name, _, _ in WINDOW_SPECS:
        percent = as_number(data.get(f"{name}_percent"))
        if percent is not None:
            found[name] = (percent, as_number(data.get(f"{name}_reset")))
    return found, updated


def as_number(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            pass
    return None


def window_values(window):
    if not isinstance(window, dict):
        return None
    percent = window.get("used_percent")
    if percent is None:
        percent = window.get("usedPercent")
    percent = as_number(percent)
    if percent is None:
        return None
    reset = window.get("reset_at")
    if reset is None:
        reset = window.get("resetAt")
    return max(0, min(100, percent)), as_number(reset)


def extract_windows(data):
    rate_limit = (
        data.get("rate_limit")
        or data.get("rateLimits")
        or data.get("rate_limits")
        or data.get("rateLimit")
        or {}
    )
    if not isinstance(rate_limit, dict):
        return {}

    windows = [value for value in rate_limit.values() if isinstance(value, dict)]
    found = {}
    for name, keys, (low, high) in WINDOW_SPECS:
        values = None
        for key in keys:
            values = window_values(rate_limit.get(key))
            if values is not None:
                break
        if values is None:
            for window in windows:
                seconds = window.get("limit_window_seconds")
                if seconds is None:
                    seconds = window.get("limitWindowSeconds")
                seconds = as_number(seconds)
                if seconds is not None and low <= seconds <= high:
                    values = window_values(window)
                    if values is not None:
                        break
        if values is not None:
            found[name] = values

    if not found:
        for item in data.get("additional_rate_limits") or data.get("additionalRateLimits") or []:
            if isinstance(item, dict):
                found = extract_windows(item)
                if found:
                    break

    if not found:
        debug(f"no usable window; rate={','.join(sorted(rate_limit))}")
    return found


def fetch_windows():
    auth = read_auth()
    if auth is None:
        return {}
    access_token, account_id = auth
    for usage_url in USAGE_URLS:
        for delay in (0, 0.25, 0.5, 1):
            if delay:
                time.sleep(delay)
            try:
                request = Request(
                    usage_url,
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {access_token}",
                        "ChatGPT-Account-Id": account_id,
                        "User-Agent": "CodexBar",
                    },
                )
                with urlopen(request, timeout=5) as response:
                    data = json.load(response)
                found = extract_windows(data)
                if found:
                    return found
                debug(f"{usage_url}: top={','.join(sorted(data))}")
                break
            except HTTPError as error:
                debug(f"{usage_url}: HTTP {error.code}")
                if error.code != 403:
                    break
            except Exception as error:
                debug(f"{usage_url}: {type(error).__name__}")
                break
    return {}


def as_payload(windows):
    payload = {}
    for name, (percent, reset) in windows.items():
        payload[f"{name}_percent"] = round(percent)
        if reset is not None:
            payload[f"{name}_reset"] = round(reset)
    return payload


def write_cached(windows):
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{CACHE_FILE.name}.", dir=CACHE_FILE.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(dict(as_payload(windows), updated_at=time.time()), stream)
            stream.write("\n")
        os.replace(temp_name, CACHE_FILE)
    except OSError:
        try:
            os.unlink(temp_name)
        except OSError:
            pass


def main():
    cached, updated = read_cached()
    if cached and time.time() - updated < CACHE_TTL:
        print(json.dumps(as_payload(cached)))
        return
    try:
        windows = fetch_windows()
    except Exception:
        windows = {}
    if windows:
        write_cached(windows)
        print(json.dumps(as_payload(windows)))
    elif cached:
        print(json.dumps(as_payload(cached)))


if __name__ == "__main__":
    main()
