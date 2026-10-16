#!/usr/bin/env bash
# Ask before writing GitHub comments, issues or pull requests through gh api,
# gh pr or gh issue.
# Known limitations: a call inside a string passed to another shell (bash -c '...')
# and a call after a background & in the same line are not seen.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

# A heredoc inside $( ) fails to parse on bash 3.2 (macOS /bin/bash), so the
# parser runs from a temporary file written by a top-level heredoc instead.
PARSE_TMP=$(mktemp)
trap 'rm -f "$PARSE_TMP"' EXIT
cat >"$PARSE_TMP" <<'PYEOF'
import os
import re
import shlex
import sys

command = sys.argv[1].replace("\r\n", "\n")


def option_value(args, index, names):
    arg = args[index]
    if arg in names and index + 1 < len(args):
        return args[index + 1], 1
    for name in names:
        prefix = name + "="
        if arg.startswith(prefix):
            return arg[len(prefix) :], 0
    return None, 0


def api_path(endpoint):
    """Endpoint path without query, host, or the GHES api/v3/ (api/ for graphql) prefix."""
    path = endpoint.split("?", 1)[0]
    path = re.sub(r"^https?://[^/]+/", "", path).strip("/")
    return re.sub(r"^api/(?:v3/)?", "", path)


def is_target_endpoint(endpoint):
    path = api_path(endpoint).split("/")
    if len(path) < 4 or path[0] != "repos":
        return False
    if path[3] == "pulls":
        return True
    if path[3] == "issues" and len(path) >= 5 and path[4] == "comments":
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


# Options that take a value which must not be mistaken for the endpoint.
VALUE_FLAGS = ("-H", "--header", "--jq", "-q", "-t", "--template", "--hostname", "-p", "--preview", "--cache")

# Short options whose value may be attached or follow, also at the end of a cluster like -iX.
SHORT_VALUE_FLAGS = "XfFHqtp"

SPLIT = r"(?:&&|\|\||[;|]|\n)"

# gh subcommands that post comments or create / modify pull requests and issues.
WRITE_SUBCOMMANDS = {
    "pr": {"create", "comment", "edit", "review", "ready", "merge", "close", "reopen"},
    "issue": {"create", "comment", "edit", "close", "reopen", "delete"},
}


def segments(command):
    """Yield each command segment, plus the contents of every $( ) and backtick substitution in it."""
    for segment in re.split(SPLIT, command):
        yield segment
        for match in re.finditer(r"\$\(([^()]*)\)|`([^`]*)`", segment):
            yield match.group(1) if match.group(1) is not None else match.group(2)


targets = []

for segment in segments(command):
    try:
        words = shlex.split(segment)
    except ValueError:
        continue

    # Strip ( { $( glued to the front of words and ) } to the back: (gh api) -> gh api.
    words = [w for w in (w.lstrip("({").removeprefix("$(").rstrip(")}") for w in words) if w]

    for gh_index, word in enumerate(words):
        if os.path.basename(word) != "gh" or gh_index + 1 >= len(words):
            continue
        group = words[gh_index + 1]
        if group in WRITE_SUBCOMMANDS:
            if gh_index + 2 < len(words) and words[gh_index + 2] in WRITE_SUBCOMMANDS[group]:
                targets.append(f"gh {group} {words[gh_index + 2]}")
            continue
        if group != "api":
            continue

        args = words[gh_index + 2 :]
        method = None
        has_body = False
        values = []
        endpoint = None
        index = 0
        while index < len(args):
            arg = args[index]
            if re.fullmatch(r"-[A-Za-z].+", arg):
                letters = arg[1:]
                pos = next((i for i, c in enumerate(letters) if c in SHORT_VALUE_FLAGS), None)
                if pos is None:
                    index += 1
                    continue
                flag, value, consumed = letters[pos], letters[pos + 1 :], 0
                if not value and index + 1 < len(args):
                    value, consumed = args[index + 1], 1
                if flag == "X":
                    method = value.upper()
                elif flag in "fF":
                    has_body = True
                    values.append(value)
                index += consumed + 1
                continue

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

            value, consumed = option_value(args, index, VALUE_FLAGS)
            if value is not None:
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

        if api_path(endpoint) == "graphql":
            if is_graphql_write(values):
                targets.append(f"gh api {method} {endpoint}")
        elif is_target_endpoint(endpoint):
            targets.append(f"gh api {method} {endpoint}")

print("\n".join(dict.fromkeys(targets)))
PYEOF
TARGET=$("${PYTHON[@]}" "$PARSE_TMP" "$COMMAND") || exit 0
# A Windows-native Python translates \n to \r\n on stdout.
TARGET=${TARGET//$'\r'/}

[[ -z "$TARGET" ]] && exit 0

COMMANDS=$(printf '%s\n' "$TARGET" | sed 's/^/  /')

# printf instead of $(cat <<EOF): a heredoc inside $( ) fails to parse on
# bash 3.2 (macOS /bin/bash).
REASON=$(printf '[GitHub write requires confirmation]

%s

These commands can create or modify a pull request or issue, or post GitHub comments.
Confirm the operation explicitly if you intend to publish this change.
' "$COMMANDS")

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
