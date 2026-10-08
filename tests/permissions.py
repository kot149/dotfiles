# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the Bash allow / deny rules rendered from .chezmoidata/agent-permissions.toml.

  uv run --no-python-downloads --script tests/permissions.py

Renders the Claude Code settings template and matches commands against its
Bash(...) rules, treating `*` as any run of characters (spaces and newlines
included). Approximates Claude Code's matcher; it does not model its prefix rules.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / ".chezmoitemplates" / "claude" / "settings.json.tmpl"


def bash_patterns(rules: list[str]) -> list[re.Pattern[str]]:
    patterns = []
    for rule in rules:
        if not (rule.startswith("Bash(") and rule.endswith(")")):
            continue
        pattern = rule[len("Bash(") : -1]
        regex = "^" + ".*".join(re.escape(part) for part in pattern.split("*")) + "$"
        patterns.append(re.compile(regex, re.DOTALL))
    return patterns


rendered = subprocess.run(
    ["chezmoi", "--source", str(ROOT), "execute-template", "-f", str(TEMPLATE)],
    capture_output=True,
    text=True,
    encoding="utf-8",
    check=True,
)
permissions = json.loads(rendered.stdout)["permissions"]
ALLOW = bash_patterns(permissions["allow"])
DENY = bash_patterns(permissions["deny"])


def denied(cmd: str) -> bool:
    return any(p.match(cmd) for p in DENY)


def allowed(cmd: str) -> bool:
    return any(p.match(cmd) for p in ALLOW) and not denied(cmd)


# Commands that must prompt: they run arbitrary code, write, or hit a non-GET endpoint.
NOT_ALLOWED = [
    "npx some-pkg --version",
    "bash -c 'rm -rf x' --help",
    "gh api repos/o/r -X DELETE",
    "gh api repos/o/r/git/refs/heads/main -X PATCH -F force=true",
    "gh api repos/o/r/pulls",
    "gh api --method GET repos/o/r -X DELETE",
    "gh api -X GET repos/o/r -XPOST -f a=b",
    "chezmoi git -- push --force origin catalog",
    "direnv exec . env",
    "chezmoi state reset",
    'psql -c \\d -c "drop table x"',
    "gradle tasks publish",
    "tmux list-sessions \\; run-shell 'touch /tmp/x'",
    "rtk pnpm exec some-bin",
    "rtk docker run alpine",
    "rtk prisma migrate reset",
    "deno task anything",
    "ldd ./untrusted",
]

# Read-only commands that must stay prompt-free.
ALLOWED = [
    "git log --oneline -5",
    "git diff",
    "rg pattern src",
    "gh api rate_limit",
    "gh api graphql -f query='query { viewer { login } }'",
    "chezmoi git -- log --oneline",
    "chezmoi git -- status",
    "ls -la",
    "jq --version",
    "git --version",
    "tmux list-panes -a",
    "rtk docker ps",
    "deno task test",
]

checks = 0
failures: list[str] = []

for group, cases, expected in (("not_allowed", NOT_ALLOWED, False), ("allowed", ALLOWED, True)):
    for cmd in cases:
        checks += 1
        if allowed(cmd) is not expected:
            failures.append(f"{group}: {cmd}")

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
