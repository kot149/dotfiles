# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Check .chezmoidata/agent-hooks.toml against the hook files in the repository.

Reports every violation and exits 1 if there is any. Read-only.

Usage:
  uv run --script scripts/check_agent_hooks.py
"""

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / ".chezmoidata" / "agent-hooks.toml"
BODIES = ROOT / ".chezmoitemplates" / "agents"
HOOK_DIRS = {"claude": ROOT / "dot_claude" / "hooks", "codex": ROOT / "dot_codex" / "hooks"}
RUNNERS = {"bash", "uv-script", "bun", "command"}
ENTRY_KEYS = {"name", "file", "runner", "args", "command", *HOOK_DIRS}
TABLE_KEYS = {"event", "matcher", "timeout", "statusMessage", "asyncRewake"}
# Sourced by the hooks, not registered.
NOT_REGISTERED = {"python-runner.sh"}


def target_name(source: Path) -> str:
    """The file name chezmoi gives a source file in a hooks directory."""
    name = source.name.removeprefix("executable_")
    return name.removesuffix(".tmpl")


def hook_files(agent: str) -> dict[str, Path]:
    """Target name -> source file for the top-level files in dot_<agent>/hooks/."""
    return {target_name(p): p for p in sorted(HOOK_DIRS[agent].iterdir()) if p.is_file()}


def agents_of(entry: dict) -> list[str]:
    return [agent for agent in HOOK_DIRS if agent in entry]


def check_entries(entries: list[dict]) -> list[str]:
    """Entry shape: name, keys, runner, file / command, per-agent tables."""
    problems = []
    seen: set[str] = set()
    for index, entry in enumerate(entries):
        name = entry.get("name") or f"<entry {index + 1}>"
        if "name" not in entry:
            problems.append(f"{name}: no name")
        elif name in seen:
            problems.append(f"{name}: duplicate name")
        seen.add(name)
        for key in sorted(set(entry) - ENTRY_KEYS):
            problems.append(f"{name}: unknown key {key!r}")
        runner = entry.get("runner")
        if runner not in RUNNERS:
            problems.append(f"{name}: unknown runner {runner!r}")
        if (runner == "command") != ("command" in entry):
            problems.append(f'{name}: `command` is required with runner = "command" and not allowed otherwise')
        if (runner == "command") == ("file" in entry):
            problems.append(f'{name}: `file` is required unless runner = "command" and not allowed with it')
        if not agents_of(entry):
            problems.append(f"{name}: no claude or codex table")
        for agent in agents_of(entry):
            table = entry[agent]
            if "event" not in table:
                problems.append(f"{name}: {agent} table has no event")
            for key in sorted(set(table) - TABLE_KEYS):
                problems.append(f"{name}: unknown key {key!r} in the {agent} table")
    return problems


def check_wrappers(entries: list[dict]) -> list[str]:
    """Each registered file exists, and a shared hook is an include of its body."""
    problems = []
    files = {agent: hook_files(agent) for agent in HOOK_DIRS}
    for entry in entries:
        if "file" not in entry:
            continue
        name, file = entry.get("name", "<no name>"), entry["file"]
        agents = agents_of(entry)
        if len(agents) > 1 and not (BODIES / file).is_file():
            problems.append(f"{name}: shared body .chezmoitemplates/agents/{file} does not exist")
        for agent in agents:
            source = files[agent].get(file)
            if source is None:
                problems.append(f"{name}: {HOOK_DIRS[agent].relative_to(ROOT)}/ has no {file}")
                continue
            if len(agents) > 1:
                expected = f'{{{{ include ".chezmoitemplates/agents/{file}" -}}}}'
                if source.read_text(encoding="utf-8").rstrip("\n") != expected:
                    problems.append(f"{source.relative_to(ROOT)}: not the single line `{expected}`")
    return problems


def check_unregistered(entries: list[dict]) -> list[str]:
    """Every file in a hooks directory is registered for that agent."""
    problems = []
    for agent in HOOK_DIRS:
        registered = {e["file"] for e in entries if "file" in e and agent in e}
        for target, source in hook_files(agent).items():
            if target not in registered | NOT_REGISTERED:
                problems.append(f"{source.relative_to(ROOT)}: not registered in {DATA_FILE.name} for {agent}")
    return problems


def main() -> int:
    entries = tomllib.loads(DATA_FILE.read_text(encoding="utf-8"))["agent_hooks"]
    sections = [
        ("entries", check_entries(entries)),
        ("wrappers", check_wrappers(entries)),
        ("unregistered files", check_unregistered(entries)),
    ]
    failed = False
    for title, problems in sections:
        if not problems:
            continue
        failed = True
        print(f"\n{title}:")
        for problem in problems:
            print(f"  {problem}")
    if failed:
        return 1
    wrappers = sum(len(hook_files(agent)) for agent in HOOK_DIRS)
    print(f"OK: {len(entries)} hooks, {wrappers} hook files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
