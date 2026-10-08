# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the Bash permission hooks in .chezmoitemplates/agents/.

  uv run --no-python-downloads --script tests/hooks.py

Each hook runs as a subprocess with the same stdin JSON the agents send, so a
passing run means the installed hook behaves the same way.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / ".chezmoitemplates" / "agents"

PUSH = "check-force-push.sh"
GH_API = "check-github-api-write.sh"

PUSH_ASK = ("ask", "Git push requires confirmation")
FORCE_ASK = ("ask", "Force push")
GH_ASK = ("ask", "GitHub API write requires confirmation")

# (hook, command, expected): None means no decision, else (decision, reason substring).
CASES: list[tuple[str, str, None | tuple[str, str]]] = [
    (PUSH, "git push origin main", PUSH_ASK),
    (PUSH, "git push --force origin main", FORCE_ASK),
    (PUSH, "git push -f", FORCE_ASK),
    (PUSH, "git push origin +main", FORCE_ASK),
    (PUSH, "git push --force-with-lease", FORCE_ASK),
    (PUSH, "git push -u origin HEAD", PUSH_ASK),
    (PUSH, "git -C /tmp/x push", PUSH_ASK),
    (PUSH, "FOO=1 git push", PUSH_ASK),
    (PUSH, "git status && git push", PUSH_ASK),
    (PUSH, "(git push --force)", FORCE_ASK),
    (PUSH, "(cd repo && git push)", PUSH_ASK),
    (PUSH, "git publish", PUSH_ASK),
    (PUSH, "git stash push", None),
    (PUSH, "git log", None),
    (PUSH, 'echo "git push"', None),
    (PUSH, "out=$(git push)", PUSH_ASK),
    (PUSH, 'echo "$(git push --force)"', FORCE_ASK),
    (PUSH, "echo `git push`", PUSH_ASK),
    (PUSH, "(git stash push)", None),
    (PUSH, "out=$(git log)", None),
    (GH_API, "gh api repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -X POST repos/o/r/issues/1/comments -f body=x", GH_ASK),
    (
        GH_API,
        'gh api -H "Accept: application/vnd.github+json" -X POST repos/o/r/issues/1/comments -f body=x',
        GH_ASK,
    ),
    (GH_API, "gh api --jq .id repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -XPOST repos/o/r/pulls/1/merge", GH_ASK),
    (GH_API, "gh api -fbody=x repos/o/r/issues/1/comments", GH_ASK),
    (GH_API, "gh api -X PATCH repos/o/r/issues/comments/123 -f body=x", GH_ASK),
    (GH_API, "gh api -X DELETE repos/o/r/issues/comments/123", GH_ASK),
    (
        GH_API,
        "gh api graphql -f query='mutation { addComment(input:{}) { clientMutationId } }'",
        GH_ASK,
    ),
    (GH_API, "gh api repos/o/r/pulls", None),
    (GH_API, "gh api --paginate repos/o/r/pulls", None),
    (GH_API, "gh api repos/o/r/issues/comments/123", None),
    (GH_API, "gh api --method GET repos/o/r/pulls/1/comments", None),
    (GH_API, "gh pr view 1", None),
    (GH_API, "(gh api -X POST repos/o/r/pulls -f title=x)", GH_ASK),
    (GH_API, "x=$(gh api -X POST repos/o/r/issues/1/comments -f body=x)", GH_ASK),
    (GH_API, "gh api -iX POST repos/o/r/issues/1/comments -f body=x", GH_ASK),
    (GH_API, "gh api -iXPOST repos/o/r/pulls/1/merge", GH_ASK),
    (GH_API, "gh api https://api.github.com/repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api https://ghe.example.com/api/v3/repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -i repos/o/r/pulls", None),
    (GH_API, "x=$(gh api repos/o/r/pulls)", None),
    (GH_API, "gh api https://api.github.com/repos/o/r/pulls", None),
]

failures: list[str] = []
checks = 0


def check(label: str, ok: bool, detail: str) -> None:
    global checks
    checks += 1
    if not ok:
        failures.append(f"{label}\n      {detail}")


def run(hook: str, command: str) -> tuple[int, None | tuple[str, str]]:
    """Return the hook's exit status and its decision (None when silent)."""
    result = subprocess.run(
        ["bash", str(HOOKS / hook)],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if not result.stdout.strip():
        return result.returncode, None
    d = json.loads(result.stdout)["hookSpecificOutput"]
    return result.returncode, (d["permissionDecision"], d["permissionDecisionReason"])


for hook, command, expected in CASES:
    label = f"{hook}: {command}"
    status, actual = run(hook, command)
    if status != 0:
        check(label, False, f"exit status {status}")
        continue
    if expected is None:
        ok = actual is None
    else:
        ok = actual is not None and actual[0] == expected[0] and expected[1] in actual[1]
    check(label, ok, f"expected: {expected!r}\n      actual:   {actual!r}")

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
