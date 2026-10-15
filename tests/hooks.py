# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the Bash permission hooks in .chezmoitemplates/agents/ and Claude
Code's git -C rewrite and Japanese reply Stop hooks.

  uv run --no-python-downloads --script tests/hooks.py

Each hook runs as a subprocess with the same stdin JSON the agents send, so a
passing run means the installed hook behaves the same way.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / ".chezmoitemplates" / "agents"

# Resolved through PATH: on Windows a bare "bash" can start System32's WSL launcher.
BASH = shutil.which("bash")
if BASH is None:
    sys.exit("bash not found on PATH")

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

# (command, expected updatedInput.command): None means the hook leaves it as is.
REWRITE_CASES: list[tuple[str, None | str]] = [
    ("git -C /tmp status", "(cd /tmp && git status)"),
    ('git -C "/path with space" log -1', '(cd "/path with space" && git log -1)'),
    ("git -C '/q' diff", "(cd '/q' && git diff)"),
    ("git -C repo status && git -C other log", "(cd repo && git status) && (cd other && git log)"),
    ("cd x; git -C y status", "cd x; (cd y && git status)"),
    ("(git -C repo status)", "( (cd repo && git status))"),
    ("git -C a -C b status", None),
    ("git -C repo log > out.txt", None),
    ("git -C repo log | head", "(cd repo && git log) | head"),
    ("git -C $(pwd) status", None),
    ('git -C repo commit -m "a && b"', '(cd repo && git commit -m "a && b")'),
    ("git status", None),
    ("git -C -x status", None),
    ("echo 'git -C x status'", None),
    ("git -C repo log 2>&1", None),
    ('git -C repo log "a > b"', '(cd repo && git log "a > b")'),
    ("git -C repo log && echo hi > out", "(cd repo && git log) && echo hi > out"),
    ("git -C repo status || git -C r2 status", "(cd repo && git status) || (cd r2 && git status)"),
    ("git -C repo status |& cat", "(cd repo && git status) |& cat"),
    ("git -C repo status &", "(cd repo && git status) &"),
    ("git -C repo status\ngit -C b log", "(cd repo && git status)\n(cd b && git log)"),
    ("git -C=repo status", None),
    ("git -Crepo status", None),
    ("git -C repo log <<EOF", None),
    ("git -C 'unterminated status", None),
]

ENGLISH_REPLY = (
    "I've updated the section in the README. Checking the file after the update, "
    "the TODO line is gone and the new steps are there."
)

# (user prompt, last reply, expected block): the Stop hook should block English prose only.
JAPANESE_REPLY_CASES: list[tuple[str, str, bool]] = [
    ("READMEを更新して", ENGLISH_REPLY, True),
    ("READMEを更新して", "I've updated the 「使い方」 section. " + ENGLISH_REPLY, True),
    ("READMEを更新して", "I've updated the 『はじめに』 section. " + ENGLISH_REPLY, True),
    ("READMEを更新して", "「使い方」の節を更新しました。TODOの行は消えています。", False),
    ("READMEを更新して", "更新しました。\n\n```\n" + ENGLISH_REPLY + "\n```", False),
    ("READMEを更新して", "Done.", False),
    ("英訳して", ENGLISH_REPLY, False),
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
        [BASH, str(HOOKS / hook)],
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


def rewrite(hook_dir: Path, command: str) -> tuple[int, str, None | str]:
    """Return the rewrite hook's exit status, stderr and updatedInput command (None when silent)."""
    result = subprocess.run(
        [BASH, str(hook_dir / "rewrite-git-c.sh")],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**os.environ, "PATH": f"{hook_dir}{os.pathsep}{os.environ['PATH']}"},
    )
    if not result.stdout.strip():
        return result.returncode, result.stderr, None
    updated = json.loads(result.stdout)["hookSpecificOutput"]["updatedInput"]["command"]
    return result.returncode, result.stderr, updated


# Lay the hook out as installed, next to python-runner.sh, with an rtk stub
# first on PATH so a real rtk does not rewrite the command further.
with tempfile.TemporaryDirectory() as tmp:
    hook_dir = Path(tmp)
    shutil.copy(ROOT / "dot_claude" / "hooks" / "executable_rewrite-git-c.sh", hook_dir / "rewrite-git-c.sh")
    shutil.copy(HOOKS / "python-runner.sh", hook_dir / "python-runner.sh")
    stub = hook_dir / "rtk"
    stub.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    stub.chmod(0o755)

    for command, expected in REWRITE_CASES:
        label = f"rewrite-git-c: {command}"
        status, stderr, actual = rewrite(hook_dir, command)
        # A failing python step falls through silently, so stderr must stay empty too.
        if status != 0 or stderr:
            check(label, False, f"exit status {status}, stderr: {stderr.strip()!r}")
            continue
        check(label, actual == expected, f"expected: {expected!r}\n      actual:   {actual!r}")


def japanese_reply(hook_dir: Path, prompt: str, reply: str) -> tuple[int, str, bool]:
    """Return the Stop hook's exit status, stderr and whether it blocked."""
    transcript = hook_dir / "transcript.jsonl"
    transcript.write_text(
        json.dumps({"type": "user", "message": {"role": "user", "content": prompt}}) + "\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [BASH, str(hook_dir / "check-japanese-reply.sh")],
        input=json.dumps({"transcript_path": str(transcript), "last_assistant_message": reply}),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    blocked = bool(result.stdout.strip()) and json.loads(result.stdout).get("decision") == "block"
    return result.returncode, result.stderr, blocked


with tempfile.TemporaryDirectory() as tmp:
    hook_dir = Path(tmp)
    shutil.copy(ROOT / "dot_claude" / "hooks" / "executable_check-japanese-reply.sh", hook_dir / "check-japanese-reply.sh")
    shutil.copy(HOOKS / "python-runner.sh", hook_dir / "python-runner.sh")

    for prompt, reply, expected in JAPANESE_REPLY_CASES:
        label = f"check-japanese-reply: {prompt} / {reply[:40]!r}"
        status, stderr, actual = japanese_reply(hook_dir, prompt, reply)
        if status != 0 or stderr:
            check(label, False, f"exit status {status}, stderr: {stderr.strip()!r}")
            continue
        check(label, actual == expected, f"expected block: {expected}\n      actual:   {actual}")

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
