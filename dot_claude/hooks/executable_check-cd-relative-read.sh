#!/usr/bin/env bash
# Block `cd <dir> && <read command> <relative path>` in favour of absolute paths.
# Since 2.1.257 the auto mode classifier refuses to resolve a read target that sits
# behind an in-command cd when the repository has Read() deny rules, so every such
# command escalates to a manual approval prompt. Parallel subagents all emit this
# shape, which buries the session in prompts.
# Block by default; set FORCE_CD_RELATIVE=1 to allow.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0
# Heredoc bodies are data, not shell words, and are not worth parsing here.
[[ "$COMMAND" == *"<<"* ]] && exit 0

TARGET=$(python3 - "$COMMAND" <<'PYEOF'
import os
import re
import shlex
import sys

command = sys.argv[1]

# Commands whose path arguments the permission engine matches against Read() rules.
READ_CMDS = {
    "cat", "bat", "head", "tail", "nl", "less", "more", "wc", "file", "stat",
    "grep", "egrep", "fgrep", "rg", "ag", "ack",
    "sed", "awk", "cut", "sort", "uniq", "diff",
    "ls", "tree", "find", "fd", "du", "jq", "yq",
}

# Their leading positional is a pattern or a script, never a path.
PATTERN_FIRST = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "sed", "awk", "fd"}

ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
RELATIVE_PATH = re.compile(r"/|\.[A-Za-z0-9_]+$")
SEPARATORS = {"&&", "||", "|", ";", "&", "(", ")"}
REDIRECTS = {">", ">>", "<", "<<", "2>", "&>"}


def segments_of(command):
    """Split into command segments, tokenizing first so quoted `|` stays intact."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    segment = []
    for token in lexer:
        if token in SEPARATORS:
            yield segment
            segment = []
        else:
            segment.append(token)
    yield segment


def strip_prefixes(words):
    while words and (ENV_ASSIGN.match(words[0]) or os.path.basename(words[0]) == "rtk"):
        words = words[1:]
    return words


def looks_relative(word):
    if word.startswith(("-", "/", "~", "$")):
        return False
    return bool(RELATIVE_PATH.search(word))


def positionals_of(words):
    """Arguments that name a path: no flags, no redirection targets."""
    result = []
    skip_next = False
    for word in words:
        if skip_next:
            skip_next = False
            continue
        if word in REDIRECTS or word.startswith((">", "<")):
            skip_next = True
            continue
        if word.startswith("-"):
            continue
        result.append(word)
    return result


try:
    all_segments = list(segments_of(command))
except ValueError:
    sys.exit(0)

seen_cd = False

for words in all_segments:
    words = strip_prefixes(words)
    if not words:
        continue

    name = os.path.basename(words[0])

    if name in ("cd", "pushd"):
        args = [w for w in words[1:] if not w.startswith("-")]
        # `cd` with no argument or `cd -` goes somewhere this hook cannot reason about.
        if args and args[0] != "-":
            seen_cd = True
        continue

    if not seen_cd or name not in READ_CMDS:
        continue

    positionals = positionals_of(words[1:])
    if name in PATTERN_FIRST:
        positionals = positionals[1:]

    offenders = [w for w in positionals if looks_relative(w)]
    if offenders:
        print(f"{name}\t{' '.join(offenders)}")
        sys.exit(0)
PYEOF
) || exit 0

[[ -z "$TARGET" ]] && exit 0

CMD_NAME=${TARGET%%$'\t'*}
CMD_PATHS=${TARGET#*$'\t'}

if [[ "${FORCE_CD_RELATIVE:-}" == "1" ]] || echo "$COMMAND" | grep -q 'FORCE_CD_RELATIVE=1'; then
    printf '[Path Warning] %s reads %s after a cd (FORCE_CD_RELATIVE=1 set, allowing)\n' "$CMD_NAME" "$CMD_PATHS" >&2
    exit 0
fi

REASON=$(cat <<EOF
[Use an absolute path instead of cd]

  Command: $CMD_NAME
  Relative path(s): $CMD_PATHS

The auto mode classifier will not resolve a read target that sits behind an
in-command cd while the repository has Read() deny rules, so this command
escalates to a manual approval prompt. Drop the cd and spell the path out:

  $CMD_NAME <absolute path>

Only reads and searches are affected. Commands that genuinely need the working
directory (git, test runners, package managers) may keep their cd. If this
command also needs it, re-run with FORCE_CD_RELATIVE=1 prepended.
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
