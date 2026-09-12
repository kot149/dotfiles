#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "json5",
# ]
# ///
"""Merge managed VSCode/Cursor settings into existing settings.json files.

The spec groups keys under managed/desired x {common, os, app, os.app} so
user-local settings survive. Used by `mise run apply-vscode-settings`.

Usage: merge-vscode-settings.py SPEC OS_NAME TARGET...
"""

import json
from pathlib import Path
import sys

import json5

OS_NAME = sys.argv[2]
APP_NAMES = ("code", "cursor")


def load_json_with_comments(path: Path):
    if not path.exists():
        return {}

    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return {}

    return json5.loads(raw)


def group_names(app_name: str):
    return ("common", OS_NAME, app_name, f"{OS_NAME}.{app_name}")


def select_managed_keys(spec, app_name: str):
    grouped_items = spec.get("managed", {})
    if not isinstance(grouped_items, dict):
        raise SystemExit(f"{spec_path} field 'managed' must be a JSON object")

    keys = []
    for name in group_names(app_name):
        items = grouped_items.get(name, [])
        if not isinstance(items, list):
            raise SystemExit(f"{spec_path} field 'managed.{name}' must be a JSON array")
        for item in items:
            if not isinstance(item, str):
                raise SystemExit(f"{spec_path} field 'managed.{name}' must contain strings")
            keys.append(item)
    return keys


def select_desired_settings(spec, app_name: str):
    grouped_items = spec.get("desired", {})
    if not isinstance(grouped_items, dict):
        raise SystemExit(f"{spec_path} field 'desired' must be a JSON object")

    merged = {}
    for name in group_names(app_name):
        items = grouped_items.get(name, {})
        if not isinstance(items, dict):
            raise SystemExit(f"{spec_path} field 'desired.{name}' must be a JSON object")
        merged.update(items)
    return merged


spec_path = Path(sys.argv[1])
spec = json.loads(spec_path.read_text(encoding="utf-8"))

for app_name, arg in zip(APP_NAMES, sys.argv[3:]):
    target = Path(arg)
    current = load_json_with_comments(target)

    if not isinstance(current, dict):
        raise SystemExit(f"{target} must contain a JSON object")

    managed_keys = set(select_managed_keys(spec, app_name))
    desired = select_desired_settings(spec, app_name)

    filtered = {
        key: value
        for key, value in current.items()
        if key not in managed_keys
    }
    filtered.update(desired)

    with target.open("w", encoding="utf-8") as f:
        json.dump(filtered, f, indent=2)
        f.write("\n")

    print(f"Merged managed settings into {target}")
