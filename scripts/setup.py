#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit"]
# ///
"""Update machine settings while preserving other TOML values and comments."""
from pathlib import Path
import argparse
import os

import tomlkit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrate", action="store_true", help="Import missing machine values without prompting")
    parser.add_argument("--chezmoi-config", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "chezmoi/chezmoi.toml")
    args = parser.parse_args()
    target = Path(__file__).resolve().parent.parent / "mise.local.toml"
    doc = tomlkit.parse(target.read_text(encoding="utf-8-sig")) if target.exists() else tomlkit.document()
    if "vars" not in doc:
        doc["vars"] = tomlkit.table()
    values = doc["vars"]
    prompts = [
        ("git_user_name", "Git user.name (author for commits)", "kot149"),
        ("git_user_email", "Git user.email", "131101078+kot149@users.noreply.github.com"),
        ("git_signing_key", "SSH signing public key (empty = default)", ""),
        ("git_allowed_signers", "Allowed signers file (empty = default)", ""),
        ("git_editor", "Git core.editor", "code --wait"),
        ("git_commit_gpgsign", "Git commit.gpgsign (true/false)", "true"),
        ("git_safe_directories", "Git safe directories (comma-separated, empty = none)", ""),
        ("linux_gui", "Linux GUI: true=desktop false=headless (empty = auto)", ""),
    ]
    if args.chezmoi_config.exists():
        legacy = tomlkit.parse(args.chezmoi_config.read_text(encoding="utf-8-sig")).get("data", {})
        for key, _, _ in prompts:
            old_key = "linuxGui" if key == "linux_gui" else key
            if key in values or old_key not in legacy:
                continue
            value = legacy[old_key]
            if isinstance(value, bool):
                value = str(value).lower()
            elif key == "git_safe_directories":
                if any("," in directory for directory in value):
                    raise ValueError("git_safe_directories cannot contain commas")
                value = ",".join(value)
            values[key] = value
    if args.migrate:
        if values:
            target.write_text(tomlkit.dumps(doc), encoding="utf-8")
            print(f"Imported machine settings into {target}")
        return
    print(f"Machine-specific settings -> {target}")
    for key, label, default in prompts:
        current = values.get(key, default)
        answer = input(f"{label} [{current}]: ")
        values[key] = answer if answer else current
    target.write_text(tomlkit.dumps(doc), encoding="utf-8")
    print(f"Wrote {target}")


if __name__ == "__main__":
    main()
