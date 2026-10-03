# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Check the agent-skill tree for the invariants chezmoi cannot enforce.

Reports every violation and exits 1 if there is any. Read-only: it never
writes to the repository or to $HOME.

Usage:
  uv run --script scripts/check_agent_skills.py
"""
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / ".chezmoitemplates" / "agents" / "skills"
STORES = {"agents": ROOT / "dot_agents" / "skills",
          "claude": ROOT / "dot_claude" / "skills"}
HOME_STORES = {"agents": Path.home() / ".agents" / "skills",
               "claude": Path.home() / ".claude" / "skills"}
DATA_FILE = ROOT / ".chezmoidata" / "agent-skills.toml"
WRAPPER_RE = re.compile(r'^\{\{ includeTemplate "(agents/skills/[^"]+)" \. -\}\}$')
NAME_RE = re.compile(r"^name:[ \t]*(.+?)[ \t]*$", re.MULTILINE)
# An unquoted YAML scalar ends at " #": the rest of the description is parsed
# as a comment and never reaches the agent.
YAML_COMMENT_RE = re.compile(r"^(name|description):[^\"'].* #")
REV_RE = re.compile(r"^[0-9a-f]{40}$")
VALID_AGENTS = {"claude", "agents"}
# Directories in a store that this repo deliberately does not define.
# "synced" is Claude Code's own first-party skill set, which it installs and
# updates itself; the other two are machine-local skills kept out of the repo.
UNMANAGED_OK = {"synced", "codex-review", "prompt-review"}


def wrappers(store: Path) -> list[Path]:
    return sorted(store.glob("**/*.md.tmpl"))


def skill_dirs(store: Path) -> list[Path]:
    return sorted(p for p in store.iterdir() if p.is_dir())


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def frontmatter_name(text: str) -> str | None:
    """Return the `name:` value from a leading `---` frontmatter block."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end < 0:
        return None
    match = NAME_RE.search(text[3:end])
    return match.group(1) if match else None


def check_wrappers() -> tuple[list[str], dict[Path, str]]:
    """Invariants 1 and 2: wrapper shape, and the target template exists."""
    problems: list[str] = []
    targets: dict[Path, str] = {}
    for store in STORES.values():
        for wrapper in wrappers(store):
            body = wrapper.read_text(encoding="utf-8").rstrip("\n")
            match = WRAPPER_RE.match(body)
            if "\n" in body or match is None:
                problems.append(
                    f"{rel(wrapper)}: not a single "
                    f'`{{{{ includeTemplate "agents/skills/..." . -}}}}` line'
                )
                continue
            target = match.group(1)
            targets[wrapper] = target
            if not (ROOT / ".chezmoitemplates" / target).is_file():
                problems.append(f"{rel(wrapper)}: target {target} does not exist")
    return problems, targets


def check_store_parity() -> list[str]:
    """Invariant 3: a wrapper is byte-identical in both stores."""
    problems = []
    listings = {
        name: {w.relative_to(store): w for w in wrappers(store)}
        for name, store in STORES.items()
    }
    for key in sorted(set(listings["agents"]) | set(listings["claude"]), key=str):
        paths = {name: listing.get(key) for name, listing in listings.items()}
        missing = [name for name, path in paths.items() if path is None]
        if missing:
            present = next(p for p in paths.values() if p is not None)
            problems.append(f"{rel(present)}: missing from the {', '.join(missing)} store")
            continue
        if paths["agents"].read_bytes() != paths["claude"].read_bytes():
            problems.append(f"{key}: wrappers differ between the two stores")
    return problems


def check_orphan_templates(targets: dict[Path, str]) -> list[str]:
    """Invariant 4: every body outside `_shared/` is pulled in by some wrapper."""
    referenced = {ROOT / ".chezmoitemplates" / t for t in targets.values()}
    problems = []
    for body in sorted(TEMPLATES.glob("**/*.md")):
        if "_shared" in body.relative_to(TEMPLATES).parts:
            continue
        if body not in referenced:
            problems.append(f"{rel(body)}: no wrapper refers to it")
    return problems


def check_frontmatter(targets: dict[Path, str]) -> list[str]:
    """Invariant 5: the body's `name:` matches the skill directory name, and
    neither frontmatter line is silently truncated by a YAML comment."""
    problems = []
    for store in STORES.values():
        for directory in skill_dirs(store):
            wrapper = directory / "SKILL.md.tmpl"
            plain = directory / "SKILL.md"
            if wrapper.is_file():
                target = targets.get(wrapper)
                if target is None:
                    continue
                source = ROOT / ".chezmoitemplates" / target
            elif plain.is_file():
                source = plain
            else:
                problems.append(f"{rel(directory)}: has neither SKILL.md.tmpl nor SKILL.md")
                continue
            text = source.read_text(encoding="utf-8")
            for line in text.split("\n---", 1)[0].splitlines():
                if YAML_COMMENT_RE.match(line):
                    problems.append(
                        f"{rel(source)}: `{line.split(':', 1)[0]}:` is cut short by a"
                        " YAML comment; quote the value or drop the ` #`"
                    )
            name = frontmatter_name(text)
            if name is None:
                problems.append(f"{rel(source)}: no `name:` in the frontmatter")
            elif name != directory.name:
                problems.append(
                    f"{rel(source)}: name is {name!r}, directory is {directory.name!r}"
                )
    return problems


def check_openai_yaml() -> list[str]:
    """Invariant 6: shared-store skills carry Codex's interface metadata."""
    return [
        f"{rel(directory)}: missing agents/openai.yaml"
        for directory in skill_dirs(STORES["agents"])
        if not (directory / "agents" / "openai.yaml").is_file()
    ]


def check_agent_skills(entries: list[dict]) -> list[str]:
    """Invariants 7, 8 and 9 over the `[[agent_skills]]` entries."""
    problems = []
    revs: dict[str, set[str]] = defaultdict(set)
    for entry in entries:
        repo = entry.get("repo", "<no repo>")
        for agent in entry.get("agents", []):
            if agent not in VALID_AGENTS:
                problems.append(f"{repo}: unknown agent {agent!r}")
        rev = entry.get("rev", "")
        if not REV_RE.match(rev):
            problems.append(f"{repo}: rev {rev!r} is not a 40-character SHA")
        revs[repo].add(rev)
    for repo, pinned in sorted(revs.items()):
        if len(pinned) > 1:
            problems.append(f"{repo}: pinned at several revs ({', '.join(sorted(pinned))})")
    return problems


def check_unmanaged(entries: list[dict]) -> list[str]:
    """Invariant 10: no skill directory in $HOME that this repo does not define."""
    problems = []
    for agent, home_store in HOME_STORES.items():
        if not home_store.is_dir():
            print(f"SKIP: {home_store} does not exist", file=sys.stderr)
            continue
        expected = {d.name for d in skill_dirs(STORES[agent])} | UNMANAGED_OK
        for entry in entries:
            if agent in entry.get("agents", []):
                expected.update(entry.get("names", []))
        for child in sorted(home_store.iterdir()):
            if not (child.is_dir() or child.is_symlink()):
                continue
            if child.name not in expected:
                problems.append(f"{child}: not managed by this repository")
    return problems


def main() -> int:
    entries = tomllib.loads(DATA_FILE.read_text(encoding="utf-8"))["agent_skills"]
    wrapper_problems, targets = check_wrappers()
    sections = [
        ("wrapper shape and target", wrapper_problems),
        ("store parity", check_store_parity()),
        ("orphan templates", check_orphan_templates(targets)),
        ("frontmatter", check_frontmatter(targets)),
        ("agents/openai.yaml", check_openai_yaml()),
        ("agent_skills entries", check_agent_skills(entries)),
        ("unmanaged directories", check_unmanaged(entries)),
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
    skills = sum(len(skill_dirs(store)) for store in STORES.values())
    print(f"OK: {skills} skills, {len(targets)} wrappers, {len(entries)} third-party entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
