#!/usr/bin/env bash
# Rewrite `git -C <path> <args>` into `(cd <path> && git <args>)` so the
# permission rules for plain `git <args>` apply, then hand the result to rtk.
# Wildcard rules like `git -C * status*` would also approve `-c`/`--exec-path`
# inserted after the path, so they are deliberately not in the allow list.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

run_rtk() {
    command -v rtk >/dev/null 2>&1 || return 0
    rtk hook claude
}

if [[ -z "$COMMAND" || "$COMMAND" != *"git"*"-C"* ]]; then
    printf '%s' "$INPUT" | run_rtk
    exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

REWRITTEN=$("${PYTHON[@]}" - "$COMMAND" <<'PYEOF'
import re
import sys

command = sys.argv[1]

# Substitutions and heredocs hide operators from the scanner below.
if "`" in command or "$(" in command or "<<" in command:
    sys.exit(0)

OPS = ("&&", "||", "|&", ";", "|", "&", "\n", "(", ")")

# Split at top-level operators, recording whether each segment has an
# unquoted redirect (a redirect target would resolve under the new cwd).
parts = []
buf, redirect, quote, i = "", False, None, 0
while i < len(command):
    c = command[i]
    if quote:
        buf += c
        if c == "\\" and quote == '"' and i + 1 < len(command):
            buf += command[i + 1]
            i += 1
        elif c == quote:
            quote = None
        i += 1
        continue
    if c == "\\" and i + 1 < len(command):
        buf += command[i:i + 2]
        i += 2
        continue
    if c in "'\"":
        quote = c
        buf += c
        i += 1
        continue
    op = next((o for o in OPS if command.startswith(o, i)), None)
    if op:
        parts.append((buf, redirect, False))
        parts.append((op, False, True))
        buf, redirect = "", False
        i += len(op)
        continue
    if c in "<>":
        redirect = True
    buf += c
    i += 1
if quote:
    sys.exit(0)
parts.append((buf, redirect, False))

PATH = r"""'[^']+'|"[^"\\]+"|[^\s'"\\<>-][^\s'"\\<>]*"""
PATTERN = re.compile(r"^(\s*)git\s+-C\s+(" + PATH + r")\s+(?!-C\b)(\S.*?)(\s*)$", re.S)

out, changed = "", False
for text, has_redirect, is_op in parts:
    m = None if is_op or has_redirect else PATTERN.match(text)
    if not m:
        out += text
        continue
    lead, path, rest, trail = m.groups()
    if not lead and out.endswith("("):
        lead = " "
    out += f"{lead}(cd {path} && git {rest}){trail}"
    changed = True

if changed:
    print(out, end="")
PYEOF
) || REWRITTEN=""

if [[ -z "$REWRITTEN" ]]; then
    printf '%s' "$INPUT" | run_rtk
    exit 0
fi

NEW_INPUT=$(echo "$INPUT" | jq --arg c "$REWRITTEN" '.tool_input.command = $c')
RTK_OUT=$(printf '%s' "$NEW_INPUT" | run_rtk)

if [[ -n "$RTK_OUT" ]]; then
    printf '%s\n' "$RTK_OUT"
else
    # No permissionDecision: Claude Code evaluates the rules against the rewrite.
    echo "$NEW_INPUT" | jq -c '{hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecisionReason: "git -C rewritten to cd",
        updatedInput: .tool_input
    }}'
fi
