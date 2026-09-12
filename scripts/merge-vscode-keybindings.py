#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "json5",
# ]
# ///
"""Merge managed VSCode/Cursor keybindings into existing keybindings.json files.

Entries matching a managed rule are removed before the desired entries are
appended, so user-local bindings survive. Used by `mise run
apply-vscode-keybindings`.

Usage: merge-vscode-keybindings.py SPEC OS_NAME TARGET...
"""

import json
from pathlib import Path
import sys

import json5

OS_NAME = sys.argv[2]


def load_json_with_comments(path: Path):
    if not path.exists():
        return []

    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return []

    return json5.loads(raw)


def matches_rule(item, rule):
    if not isinstance(item, dict):
        return False

    if "key" in rule and item.get("key") != rule["key"]:
        return False

    if "keys" in rule and item.get("key") not in rule["keys"]:
        return False

    if "command" in rule and item.get("command") != rule["command"]:
        return False

    if "commands" in rule and item.get("command") not in rule["commands"]:
        return False

    if "args" in rule and item.get("args") != rule["args"]:
        return False

    when = str(item.get("when", ""))

    if "when_contains" in rule and not all(text in when for text in rule["when_contains"]):
        return False

    if "when_not_contains" in rule and any(text in when for text in rule["when_not_contains"]):
        return False

    return True


def select_grouped_items(spec, field_name):
    grouped_items = spec.get(field_name, {})
    if not isinstance(grouped_items, dict):
        raise SystemExit(f"{spec_path} field '{field_name}' must be a JSON object")

    selected = []
    for group_name in ("common", OS_NAME):
        items = grouped_items.get(group_name, [])
        if not isinstance(items, list):
            raise SystemExit(f"{spec_path} field '{field_name}.{group_name}' must be a JSON array")
        selected.extend(items)
    return selected


spec_path = Path(sys.argv[1])
spec = json.loads(spec_path.read_text(encoding="utf-8"))
managed_rules = select_grouped_items(spec, "managed")
desired = select_grouped_items(spec, "desired")

for arg in sys.argv[3:]:
    target = Path(arg)
    current = load_json_with_comments(target)

    if not isinstance(current, list):
        raise SystemExit(f"{target} must contain a JSON array")

    filtered = [
        item
        for item in current
        if not any(matches_rule(item, rule) for rule in managed_rules)
    ]

    merged = filtered + desired

    with target.open("w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2)
        f.write("\n")

    print(f"Merged managed keybindings into {target}")
