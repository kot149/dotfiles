#!/usr/bin/env bash
# Ask for confirmation before pushing to a remote.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

DETECTED=$("${PYTHON[@]}" - "$COMMAND" <<'PYEOF'
import os
import re
import shlex
import sys

command = sys.argv[1]

for segment in re.split(r'(?:&&|\|\||[;|]|\n)', command):
    try:
        words = shlex.split(segment)
    except ValueError:
        continue

    if not words:
        continue

    index = 0
    while index < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[index]):
        index += 1

    try:
        git_index = next(index for index in range(index, len(words)) if os.path.basename(words[index]) == "git")
    except StopIteration:
        continue

    args = words[git_index + 1 :]

    # Skip git's own options to reach the subcommand; -C/-c and friends take a value.
    value_options = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
    cursor = 0
    while cursor < len(args):
        arg = args[cursor]
        if not arg.startswith("-"):
            break
        if arg in value_options:
            cursor += 2
        else:
            cursor += 1
    else:
        continue

    if args[cursor] != "push":
        continue

    push_args = args[cursor + 1 :]
    force = any(
        arg == "-f"
        or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:])
        or arg.startswith("--force")
        for arg in push_args
    )
    kind = "force" if force else "normal"
    print(kind + "\tgit push " + " ".join(push_args))
    sys.exit(0)
PYEOF
) || exit 0

[[ -z "$DETECTED" ]] && exit 0

IFS=$'\t' read -r PUSH_KIND TARGET <<< "$DETECTED"
if [[ "$PUSH_KIND" == "force" ]]; then
    REASON=$(cat <<EOF
[Force push requires confirmation]

  Command: $TARGET

Force-pushing can discard commits on the remote branch. Confirm this operation
explicitly if you intend to rewrite the remote history.
EOF
    )
else
    REASON=$(cat <<EOF
[Git push requires confirmation]

  Command: $TARGET

This command publishes commits to a remote repository. Confirm the operation
explicitly if you intend to update the remote branch.
EOF
    )
fi

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
