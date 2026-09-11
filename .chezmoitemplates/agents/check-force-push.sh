#!/usr/bin/env bash
# Ask for confirmation before pushing to a remote.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0

if python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON=python3
elif python -c 'import sys' >/dev/null 2>&1; then
    PYTHON=python
else
    exit 0
fi

DETECTED=$("$PYTHON" - "$COMMAND" <<'PYEOF'
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
    try:
        push_index = args.index("push")
    except ValueError:
        continue

    push_args = args[push_index + 1 :]
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

"$PYTHON" - "$REASON" <<'PYEOF'
import json, sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PYEOF
