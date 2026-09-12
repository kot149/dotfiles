#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "tomlkit",
# ]
# ///
"""Merge managed Codex settings (spec) into the user's config.toml.

Top-level scalar keys are overwritten; TOML tables are merged one level deep
so user-local sections survive. Used by `mise run apply-codex-config`.
"""

from pathlib import Path
import sys

from tomlkit import dumps, parse
from tomlkit.items import Table


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


spec_path = Path(sys.argv[1])
config_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

spec_doc = parse(spec_path.read_text())
config_doc = parse(config_path.read_text())

for key, value in spec_doc.items():
    if not isinstance(value, Table):
        config_doc[key] = value
        continue
    dest = config_doc.get(key)
    if dest is None:
        config_doc[key] = value
        continue
    if not isinstance(dest, Table):
        fail(f"existing {key} value is not a TOML table")
    for sub_key, sub_value in value.items():
        dest[sub_key] = sub_value

output_path.write_text(dumps(config_doc))
