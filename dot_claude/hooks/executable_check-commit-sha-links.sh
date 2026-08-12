#!/usr/bin/env bash
# Keep commit SHAs auto-linkable in GitHub PR / issue / release bodies.
# GitHub only linkifies a bare lowercase hex SHA that is delimited by whitespace,
# so backtick-wrapped or punctuation-hugging SHAs silently lose their link.
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

FILE_FLAGS = ("--body-file", "-F", "--input")

def read_body_files(cmd):
    """Pull in bodies passed by path. Heredocs break shlex, so failures are ignored."""
    try:
        words = shlex.split(cmd, comments=False)
    except ValueError:
        return []

    texts = []
    for flag in FILE_FLAGS:
        for i, word in enumerate(words):
            path = None
            if word == flag and i + 1 < len(words):
                path = words[i + 1]
            elif word.startswith(flag + "="):
                path = word[len(flag) + 1 :]
            if not path or path == "-":
                continue
            path = os.path.join(cwd, os.path.expanduser(path))
            try:
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
# so a body that opens or closes on a SHA is not a violation.
LEADING_OK = " \t\n\"'"
TRAILING_OK = LEADING_OK + ".,;:!?)"

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
            issues.append((m.group(0), f"{prev_char!r} is glued to the front of it"))
        elif next_char not in TRAILING_OK:
            issues.append((m.group(0), f"{next_char!r} is glued to the end of it"))
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
delimited by whitespace. These will render as plain text:

$FINDINGS

Rewrite each one as a bare SHA surrounded by spaces, for example:

  Reverted in 1a2b3c4 because the migration was not idempotent.
  See 1a2b3c4 (hunk-pick) for the base-branch detection.

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
