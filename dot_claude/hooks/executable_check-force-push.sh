#!/usr/bin/env bash
# Ask for confirmation before force-pushing to a remote.

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

TARGET=$("$PYTHON" - "$COMMAND" <<'PYEOF'
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
    if any(
        arg == "-f"
        or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:])
        or arg.startswith("--force")
        for arg in push_args
    ):
        print("git push " + " ".join(push_args))
        sys.exit(0)
PYEOF
) || exit 0

[[ -z "$TARGET" ]] && exit 0

REASON=$(cat <<EOF
[Force push requires confirmation]

  Command: $TARGET

Force-pushing can discard commits on the remote branch. Confirm this operation
explicitly if you intend to rewrite the remote history.
EOF
)

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
