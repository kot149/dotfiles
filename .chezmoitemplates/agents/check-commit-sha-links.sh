#!/usr/bin/env bash
# Keep commit SHAs auto-linkable in GitHub PR / issue / release bodies.
# GitHub only linkifies a bare lowercase hex SHA delimited by whitespace or ASCII
# punctuation, so a backtick-wrapped SHA, or one hugging a full-width character
# such as （）, silently loses its link.
# Block by default; set FORCE_SHA=1 to allow.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

[[ -z "$COMMAND" ]] && exit 0
[[ -z "$CWD" ]] && CWD=$(pwd)

FINDINGS=$(python3 - "$COMMAND" "$CWD" <<'PYEOF'
import os
import re
import shlex
import subprocess
import sys

command, cwd = sys.argv[1], sys.argv[2]

GH_SUBCOMMAND = re.compile(
    r"\bgh\s+(?:pr|issue|release)\s+"
    r"(?:create|edit|comment|review|reply|update)\b"
)
GH_API = re.compile(r"\bgh\s+api\b")
GH_API_WRITE = re.compile(
    r"(?:-X|--method)\s+(?:POST|PATCH|PUT|post|patch|put)\b"
    r"|(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)"
)

def is_target(cmd):
    if GH_SUBCOMMAND.search(cmd):
        return True
    return bool(GH_API.search(cmd) and GH_API_WRITE.search(cmd))

if not is_target(command):
    sys.exit(0)

MAX_BODY_BYTES = 1 << 20

SHELL_SPLIT = re.compile(r"""[\s"'`()$;|&<>=,]+""")

def path_candidates(cmd):
    """Every word that could name a body file.

    Any word is a candidate, not just the one after a body flag: a body is just
    as often piped in (`jq ... file.md | gh api --input -`), and there the path
    only appears upstream of the pipe. shlex keeps a quoted path with spaces in
    one piece; splitting the raw string on shell metacharacters additionally
    reaches a path buried in a command substitution (`-f body="$(cat reply.md)"`),
    which shlex hands back as one opaque word. Heredocs break shlex, so failures
    are ignored.
    """
    try:
        words = shlex.split(cmd, comments=False)
    except ValueError:
        words = []
    candidates = [
        word.split("=", 1)[1] if word.startswith("-") and "=" in word else word
        for word in words
    ]
    return candidates + SHELL_SPLIT.split(cmd)

def read_body_files(cmd):
    texts, seen = [], set()
    for candidate in path_candidates(cmd):
        path = os.path.join(cwd, os.path.expanduser(candidate))
        if path in seen:
            continue
        seen.add(path)
        try:
            if not os.path.isfile(path) or os.path.getsize(path) > MAX_BODY_BYTES:
                continue
            with open(path, encoding="utf-8", errors="replace") as f:
                texts.append(f.read())
        except OSError:
            continue
    return texts

FENCE = re.compile(r"^\s*(?:```|~~~)")

def strip_fenced_blocks(text):
    """Blank out fenced code blocks; a SHA shown inside one is intentional."""
    out, in_fence = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return "\n".join(out)

SHA = re.compile(r"(?<![0-9a-zA-Z_-])[0-9a-f]{7,40}(?![0-9a-zA-Z_-])")
CODE_SPAN = re.compile(r"`([^`\n]+)`")
URL = re.compile(r"\b(?:https?|git|ssh)://\S+")
# Quotes count as boundaries because the raw command string is scanned as-is,
# so a body that opens or closes on a SHA is not a violation. ASCII parens are
# fine on both sides; their full-width counterparts are not.
LEADING_OK = " \t\n\"'("
TRAILING_OK = " \t\n\"'.,;:!?)"

FULLWIDTH_PARENS = {"（": "(", "）": ")"}

def glued_reason(char, side):
    reason = f"{char!r} is glued to the {side} of it"
    ascii_alt = FULLWIDTH_PARENS.get(char)
    if ascii_alt:
        reason += f" (use the ASCII {ascii_alt!r} instead)"
    return reason

def blank(pattern, text):
    return pattern.sub(lambda m: " " * len(m.group(0)), text)

_commit_cache = {}

def is_commit(sha):
    """GitHub only linkifies a SHA that resolves in the repo, so ask git the same thing."""
    if sha not in _commit_cache:
        _commit_cache[sha] = subprocess.run(
            ["git", "-C", cwd, "cat-file", "-e", sha + "^{commit}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
    return _commit_cache[sha]

def find_issues(text):
    issues = []

    for m in CODE_SPAN.finditer(text):
        inner = m.group(1).strip()
        if SHA.fullmatch(inner) and is_commit(inner):
            issues.append((inner, "backticks turn it into a code span"))

    # A SHA inside a URL is already a link, and one inside a code span is deliberate.
    scannable = blank(URL, blank(CODE_SPAN, strip_fenced_blocks(text)))
    for m in SHA.finditer(scannable):
        if not is_commit(m.group(0)):
            continue
        start, end = m.span()
        prev_char = scannable[start - 1] if start else "\n"
        next_char = scannable[end] if end < len(scannable) else "\n"
        # [sha](url) is an explicit link, so leave it alone.
        if prev_char == "[" and scannable[end : end + 2] == "](":
            continue
        if prev_char not in LEADING_OK:
            issues.append((m.group(0), glued_reason(prev_char, "front")))
        elif next_char not in TRAILING_OK:
            issues.append((m.group(0), glued_reason(next_char, "end")))
    return issues

texts = [command] + read_body_files(command)

seen, lines = set(), []
for text in texts:
    for sha, why in find_issues(text):
        if sha in seen:
            continue
        seen.add(sha)
        lines.append(f"  {sha}  ->  {why}")

if lines:
    print("\n".join(lines))
PYEOF
) || exit 0

[[ -z "$FINDINGS" ]] && exit 0

# Allow if FORCE_SHA=1 is set in env or prepended to the command
if [[ "${FORCE_SHA:-}" == "1" ]] || echo "$COMMAND" | grep -q 'FORCE_SHA=1'; then
    printf '[SHA Warning] Non-linkable commit SHA formatting (FORCE_SHA=1 set, allowing)\n%s\n' \
        "$FINDINGS" >&2
    exit 0
fi

REASON=$(cat <<EOF
[Commit SHA is not auto-linkable]

GitHub only turns a commit SHA into a link when it is written bare and
delimited by whitespace or ASCII punctuation. Full-width characters such as
（）「」、。 break the link. These will render as plain text:

$FINDINGS

Rewrite each one as a bare SHA delimited by spaces or ASCII punctuation,
for example:

  Reverted in 1a2b3c4 because the migration was not idempotent.
  See 1a2b3c4 (hunk-pick) for the base-branch detection.
  ベースブランチ判定は 1a2b3c4 (hunk-pick) を参照。

If the match is a false positive (a hash that is not a commit SHA, or a
deliberate literal), re-run with FORCE_SHA=1 prepended to the command.
EOF
)

printf '%s\n' "$REASON" >&2

python3 - "$REASON" <<'PYEOF'
import json, sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PYEOF
