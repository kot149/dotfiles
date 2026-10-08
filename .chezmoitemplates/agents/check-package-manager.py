# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Warn when using a package manager different from the one detected in the project,
or when running a bare python outside the project's runner (uv run など).
Block by default; set FORCE_PM=1 to allow.

Launched as `uv run --no-python-downloads --script`, so it runs the same way on
every OS (Windows has no /usr/bin/python3 and a bare python3 there may be absent
or a Store stub). --script reads a standalone script, so uv never looks for a
surrounding project and never triggers an implicit sync; --no-python-downloads
keeps a missing interpreter from turning into a multi-minute download inside a
hook that runs on every command.
"""

import json
import os
import re
import sys

SEGMENT_RE = re.compile(r"&&|\|\||[;|]|\r?\n")
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
EXT_RE = re.compile(r"\.(exe|cmd|bat|ps1)$", re.IGNORECASE)

JS_LOCKS = [
    ("yarn.lock", "yarn"),
    ("pnpm-lock.yaml", "pnpm"),
    ("bun.lockb", "bun"),
    ("bun.lock", "bun"),
    ("package-lock.json", "npm"),
]
PY_LOCKS = [
    ("uv.lock", "uv"),
    ("poetry.lock", "poetry"),
    ("Pipfile.lock", "pipenv"),
    ("pdm.lock", "pdm"),
]


def detect_used_pm(command):
    for segment in SEGMENT_RE.split(command):
        words = segment.split()
        if not words:
            continue

        # Skip leading VAR=val assignments
        idx = 0
        while idx < len(words) and ASSIGNMENT_RE.match(words[idx]):
            idx += 1
        if idx >= len(words):
            continue

        word = words[idx]
        bin_name = EXT_RE.sub("", re.split(r"[\\/]", word)[-1])
        next_word = words[idx + 1] if idx + 1 < len(words) else ""

        if bin_name in ("npm", "npx"):
            return "npm"
        if bin_name == "yarn":
            return "yarn"
        if bin_name in ("pnpm", "pnpx"):
            return "pnpm"
        if re.fullmatch(r"pip3?(\.\d+)?", bin_name):
            return "pip"
        if bin_name in ("poetry", "pipenv", "pdm", "conda"):
            return bin_name
        if re.fullmatch(r"python3?(\.\d+)?", bin_name):
            # パス付き (./.venv/bin/python) は意図した解釈器なので対象外
            if not re.search(r"[\\/]", word):
                return "python"
        elif bin_name in ("bun", "bunx"):
            if bin_name == "bunx" or next_word in (
                "install", "add", "remove", "update", "pm", "x",
            ):
                return "bun"
        elif bin_name in ("uv", "uvx"):
            if bin_name == "uvx" or next_word in ("add", "remove", "sync", "pip", "lock"):
                return "uv"

    return ""


def find_project_pm(directory, used):
    # Only look for lock files in the same language family as the used PM,
    # otherwise a JS lock file in a parent dir can mask a Python project (or vice versa).
    if used in ("npm", "yarn", "pnpm", "bun"):
        locks = JS_LOCKS
    elif used in ("pip", "poetry", "pipenv", "pdm", "uv", "conda", "python"):
        locks = PY_LOCKS
    else:
        return ""

    directory = os.path.abspath(directory)
    while True:
        for name, pm in locks:
            if os.path.isfile(os.path.join(directory, name)):
                return pm

        # Stop at git root to avoid leaking into parent repos
        if os.path.isdir(os.path.join(directory, ".git")):
            return ""

        parent = os.path.dirname(directory)
        if not parent or parent == directory:
            return ""
        directory = parent


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (ValueError, OSError):
        return

    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command.strip():
        return
    cwd = payload.get("cwd") or os.getcwd()

    used_pm = detect_used_pm(command)
    if not used_pm:
        return

    # An already-activated virtualenv means a bare python is the project's python
    if used_pm == "python":
        if os.environ.get("VIRTUAL_ENV") or os.environ.get("CONDA_PREFIX"):
            return
        if "activate" in command:
            return

    project_pm = find_project_pm(cwd, used_pm)
    if not project_pm or project_pm == used_pm:
        return

    # Allow if FORCE_PM=1 is set in env or prepended to the command
    if os.environ.get("FORCE_PM") == "1" or "FORCE_PM=1" in command:
        print(
            f"[PM Warning] Using {used_pm} but project uses {project_pm} (FORCE_PM=1 set, allowing)",
            file=sys.stderr,
        )
        return

    if used_pm == "python":
        reason = f"""[Python Outside Project Environment]

  Detected:   bare python (global interpreter)
  Project PM: {project_pm}  (detected from lock file)
  Project:    {cwd}

Please run it through the project environment: {project_pm} run python ...
To force execution, set FORCE_PM=1:

  FORCE_PM=1 {command}"""
    else:
        reason = f"""[Package Manager Mismatch]

  Detected PM: {used_pm}
  Project PM:  {project_pm}  (detected from lock file)
  Project:     {cwd}

Please use {project_pm} instead.
To force execution, set FORCE_PM=1:

  FORCE_PM=1 {command}"""

    print(reason, file=sys.stderr)

    # Deny via hook JSON output; a non-zero exit status is not a block signal in Codex.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


if __name__ == "__main__":
    main()
