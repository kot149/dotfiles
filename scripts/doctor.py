# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Report drift this repo cannot catch on apply: ignore entries with no source
file, run_onchange scripts that stopped hashing their Nix sources, missing
tools, Codex hooks with no trust entry or possibly stale trust, and
unmanaged skill directories.

Prints one OK / WARN / FAIL line per finding and exits 1 if any line is FAIL.
Read-only: it never writes to the repository or to $HOME.

Usage:
  uv run --script scripts/doctor.py
  uv run --script scripts/doctor.py --no-home
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
# Unprefixed root entries that are repo-only. chezmoi already skips source
# entries starting with ".", so those need no listing here.
REPO_ONLY = {"README.md", "AGENTS.md", "scripts", "tests", "justfile", "ruff.toml"}
# (run_onchange script, glob its hash comments must range over)
HASH_GLOBS = [
    (
        "run_onchange_after_00_home-manager.sh.tmpl",
        'glob (joinPath .chezmoi.sourceDir "private_dot_config/home-manager/**")',
    ),
    ("run_onchange_after_nix-darwin.sh.tmpl", 'glob (joinPath .chezmoi.sourceDir "private_dot_config/nix-darwin/**")'),
]
TOOLS = ["uv", "bun", "rtk", "just", "jq", "chezmoi"]
GIT_BASH_DEFAULT = "C:/Program Files/Git/bin/bash.exe"
CHUNK = 200

failed = False


def report(level: str, check: str, detail: str) -> None:
    global failed
    failed = failed or level == "FAIL"
    print(f"{level} {check}: {detail}")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kwargs)


def target_path(*args: str) -> list[str] | None:
    proc = run(["chezmoi", "target-path", *args], cwd=ROOT)
    if proc.returncode != 0:
        report("FAIL", "ignore", f"chezmoi target-path failed: {proc.stderr.strip()}")
        return None
    return [line for line in proc.stdout.splitlines() if line]


def source_targets() -> set[str] | None:
    """Targets of every source file, as POSIX paths relative to chezmoi's destDir."""
    files = run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT, check=True
    ).stdout.splitlines()
    sources = [
        f
        for f in files
        if not f.split("/")[0].startswith(".") and f.split("/")[0] not in REPO_ONLY and (ROOT / f).exists()
    ]
    dest = target_path()
    if dest is None:
        return None
    dest_dir = Path(dest[0])
    targets: set[str] = set()
    for i in range(0, len(sources), CHUNK):
        lines = target_path(*sources[i : i + CHUNK])
        if lines is None:
            return None
        for line in lines:
            try:
                targets.add(Path(line).relative_to(dest_dir).as_posix())
            except ValueError:
                report("FAIL", "ignore", f"{line} is outside {dest_dir}")
    return targets


def glob_regex(pattern: str) -> re.Pattern[str]:
    """Approximate chezmoi's doublestar matching: ** spans directories, * and ? stay in one."""
    out = ""
    i = 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile(out)


def check_ignore() -> None:
    targets = source_targets()
    if targets is None:
        return
    parents = {p.as_posix() for t in targets for p in PurePosixPath(t).parents}
    stale = 0
    lines = (ROOT / ".chezmoiignore.tmpl").read_text(encoding="utf-8").splitlines()
    for lineno, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(("#", "{{")):
            continue
        entry = line.removeprefix("./").rstrip("/")
        if "*" in entry or "?" in entry:
            regex = glob_regex(entry)
            if any(regex.fullmatch(t) for t in targets | parents):
                continue
        elif entry in targets or entry in parents or (ROOT / entry).exists():
            continue
        stale += 1
        report("FAIL", "ignore", f"{entry} (.chezmoiignore.tmpl:{lineno}) has no source file")
    if not stale:
        report("OK", "ignore", f"every entry has a source ({len(targets)} targets)")


def check_hash() -> None:
    for script, pattern in HASH_GLOBS:
        text = (ROOT / ".chezmoiscripts" / script).read_text(encoding="utf-8")
        if pattern in text:
            report("OK", "hash", f"{script} hashes every file under its glob")
        else:
            report("FAIL", "hash", f"{script} has no `{pattern}`")


def check_tools(no_home: bool) -> None:
    for tool in TOOLS:
        if no_home and tool == "rtk":
            continue
        if shutil.which(tool):
            report("OK", "tool", tool)
        else:
            report("FAIL", "tool", f"{tool} not on PATH")
    if sys.platform == "win32":
        bash = git_bash_path()
        if bash.exists():
            report("OK", "tool", str(bash))
        else:
            report("FAIL", "tool", f"{bash} not found")


def git_bash_path() -> Path:
    """Expected Git Bash location: .chezmoidata default, ~/.config/chezmoi/chezmoi.toml [data] wins."""
    default = GIT_BASH_DEFAULT
    try:
        data = tomllib.loads((ROOT / ".chezmoidata" / "git.toml").read_text(encoding="utf-8"))
        if data.get("git_bash_path"):
            default = data["git_bash_path"]
    except (OSError, tomllib.TOMLDecodeError):
        pass
    try:
        override = (
            tomllib.loads((Path.home() / ".config" / "chezmoi" / "chezmoi.toml").read_text(encoding="utf-8"))
            .get("data", {})
            .get("git_bash_path")
        )
        if override:
            return Path(override)
    except (OSError, tomllib.TOMLDecodeError):
        pass
    return Path(default)


def snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def check_codex() -> None:
    codex = Path.home() / ".codex"
    hooks_path = codex / "hooks.json"
    config_path = codex / "config.toml"
    if not hooks_path.exists():
        report("OK", "codex", "no ~/.codex/hooks.json")
        return
    try:
        hooks = json.loads(hooks_path.read_text(encoding="utf-8")).get("hooks") or {}
    except json.JSONDecodeError as e:
        report("FAIL", "codex", f"{hooks_path} does not parse: {e}")
        return
    try:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        config = {}
    except tomllib.TOMLDecodeError as e:
        report("FAIL", "codex", f"{config_path} does not parse: {e}")
        return
    # Keys are "<hooks.json path>:<event>:<group>:<index>"; the path may hold a drive colon.
    state = {}
    for key, value in config.get("hooks", {}).get("state", {}).items():
        path, *rest = key.rsplit(":", 3)
        if os.path.normcase(os.path.normpath(path)) == os.path.normcase(os.path.normpath(hooks_path)):
            state[":".join(rest)] = value
    expected = [
        f"{snake(event)}:{g}:{i}"
        for event, groups in hooks.items()
        for g, group in enumerate(groups)
        for i, _ in enumerate(group.get("hooks", []))
    ]
    missing = [k for k in expected if k not in state]
    disabled = [k for k in expected if k in state and not state[k].get("enabled", True)]
    hint = 'launch codex once and accept "Hooks need review"'
    if missing:
        report(
            "WARN",
            "codex",
            f"{len(missing)} of {len(expected)} hooks have no trust entry ({', '.join(missing)}); {hint}",
        )
    if disabled:
        report("WARN", "codex", f"disabled hooks: {', '.join(disabled)}")
    # Codex hashes only the command for this OS, so a newer hooks.json may
    # still be trusted (e.g. after a commandWindows-only edit).
    stale = config_path.exists() and hooks_path.stat().st_mtime > config_path.stat().st_mtime
    if stale:
        report("WARN", "codex", "hooks.json is newer than config.toml; Codex may ask to re-trust hooks on next launch")
    if not missing and not disabled and not stale:
        report("OK", "codex", f"{len(expected)} hooks have a trust entry")


def check_skills() -> None:
    proc = run(
        ["uv", "run", "--no-python-downloads", "--script", str(ROOT / "scripts" / "check_agent_skills.py"), "--home"]
    )
    if proc.returncode == 0:
        report("OK", "skills", "no unmanaged skill directories")
        return
    # Problems are printed to stdout as indented lines under a section title.
    problems = [line.strip() for line in proc.stdout.splitlines() if line.startswith("  ")]
    unmanaged = [p for p in problems if p.endswith("not managed by this repository")]
    if unmanaged:
        report("WARN", "skills", f"{len(unmanaged)} unmanaged skill directories (run just skills-drift)")
    for problem in problems:
        if problem not in unmanaged:
            report("FAIL", "skills", problem)
    if not problems:
        detail = (proc.stdout + proc.stderr).strip()
        report("FAIL", "skills", f"check_agent_skills.py --home exited {proc.returncode}: {detail}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--no-home",
        action="store_true",
        help="skip the checks that look at this machine's $HOME: Codex trust, skill drift, and the rtk tool; for CI",
    )
    args = parser.parse_args()
    check_ignore()
    check_hash()
    check_tools(args.no_home)
    if not args.no_home:
        check_codex()
        check_skills()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
