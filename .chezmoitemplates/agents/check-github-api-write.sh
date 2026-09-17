#!/usr/bin/env bash
# Ask before writing GitHub comments or pull requests through gh api.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

TARGET=$("${PYTHON[@]}" - "$COMMAND" <<'PYEOF'
import os
import re
import shlex
import sys


def option_value(args, index, names):
    arg = args[index]
    if arg in names and index + 1 < len(args):
        return args[index + 1], 1
    for name in names:
        prefix = name + "="
        if arg.startswith(prefix):
            return arg[len(prefix) :], 0
    return None, 0


def is_target_endpoint(endpoint):
    path = endpoint.split("?", 1)[0].strip("/").split("/")
    if len(path) < 4 or path[0] != "repos":
        return False
    if path[3] == "pulls":
        return True
    return path[3] == "issues" and len(path) >= 6 and path[5] == "comments"


def is_graphql_write(values):
    query = " ".join(values)
    return bool(
        re.search(r"\bmutation\b", query, re.IGNORECASE)
        or re.search(
            r"\b(?:addComment|addPullRequestReview|addPullRequestReviewComment|createPullRequest|updateIssueComment|updatePullRequest)\b",
            query,
        )
    )


for segment in re.split(r"(?:&&|\|\||[;|]|\n)", command := sys.argv[1]):
    try:
        words = shlex.split(segment)
    except ValueError:
        continue

    for gh_index, word in enumerate(words):
        if os.path.basename(word) != "gh" or gh_index + 1 >= len(words) or words[gh_index + 1] != "api":
            continue

        args = words[gh_index + 2 :]
        method = None
        has_body = False
        values = []
        endpoint = None
        index = 0
        while index < len(args):
            arg = args[index]
            value, consumed = option_value(args, index, ("-X", "--method"))
            if value is not None:
                method = value.upper()
                index += consumed + 1
                continue

            value, consumed = option_value(
                args,
                index,
                ("-f", "-F", "--field", "--raw-field", "--input"),
            )
            if value is not None:
                has_body = True
                values.append(value)
                index += consumed + 1
                continue

            if arg.startswith("-"):
                index += 1
                continue
            if endpoint is None:
                endpoint = arg
            index += 1

        method = method or ("POST" if has_body else "GET")
        if method in {"GET", "HEAD"} or endpoint is None:
            continue

        if endpoint.rstrip("/").split("?", 1)[0].strip("/") == "graphql":
            if is_graphql_write(values):
                print(f"gh api {method} {endpoint}")
                sys.exit(0)
        elif is_target_endpoint(endpoint):
            print(f"gh api {method} {endpoint}")
            sys.exit(0)
PYEOF
) || exit 0

[[ -z "$TARGET" ]] && exit 0

REASON=$(cat <<EOF
[GitHub API write requires confirmation]

  Command: $TARGET

This command can create or modify a pull request or post a GitHub comment.
Confirm the operation explicitly if you intend to publish this change.
EOF
)

printf '%s\n' "$REASON" >&2

"${PYTHON[@]}" - "$REASON" <<'PYEOF'
import json, sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PYEOF
