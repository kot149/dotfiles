#!/usr/bin/env bash
# Ask for confirmation before pushing to a remote.
# Known limitations: a push inside a string passed to another shell (bash -c '...')
# and a push after a background & in the same line are not seen.

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

SPLIT = r"(?:&&|\|\||[;|]|\n)"
HEREDOC = re.compile(r"<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def split_unquoted(text):
    """Split at ; & | ( ) and newlines outside quotes and comments, skipping heredoc bodies.

    A quoted multi-line argument stays in one segment.
    """
    parts, buf, quote, comment, heredocs, i = [], "", None, False, [], 0
    while i < len(text):
        c = text[i]
        if quote:
            buf += c
            if c == "\\" and quote == '"' and i + 1 < len(text):
                buf += text[i + 1]
                i += 1
            elif c == quote:
                quote = None
        elif comment and c != "\n":
            buf += c
        elif c == "\\" and i + 1 < len(text):
            # A backslash-newline continues the line.
            buf += " " if text[i + 1] == "\n" else text[i : i + 2]
            i += 1
        elif c in "'\"":
            quote = c
            buf += c
        elif c == "#" and (not buf or buf[-1] in " \t"):
            comment = True
            buf += c
        elif text.startswith("<<", i) and not text.startswith("<<<", i) and not buf.endswith("<"):
            match = HEREDOC.match(text, i)
            if match:
                heredocs.append(match.group(2))
                buf += match.group(0)
                i = match.end()
                continue
            buf += c
        elif c in ";|()\n" or (c == "&" and not buf.endswith((">", "<")) and not text.startswith(">", i + 1)):
            parts.append(buf)
            buf = ""
            if c == "\n":
                comment = False
                while heredocs and i < len(text):
                    end = text.find("\n", i + 1)
                    end = len(text) if end == -1 else end
                    if text[i + 1 : end].lstrip("\t") == heredocs[0]:
                        heredocs.pop(0)
                    i = end
        else:
            buf += c
        i += 1
    parts.append(buf)
    return parts


def segments(command):
    """Yield each command segment, plus the contents of every $( ) and backtick substitution in it.

    The plain line split runs too, so a quote, comment or heredoc read differently
    from bash can only add matches, never hide one.
    """
    for segment in split_unquoted(command) + re.split(SPLIT, command):
        yield segment
        for match in re.finditer(r"\$\(([^()]*)\)|`([^`]*)`", segment):
            yield match.group(1) if match.group(1) is not None else match.group(2)


def is_help(args):
    """--help or -h before a -- terminator only prints usage.

    It does not count right after an option without =, which may take it as its value,
    nor after a redirection, control operator or comment, where it is not passed to the command.
    """
    previous = ""
    for arg in args:
        if arg == "--" or re.search(r"[<>&|;]|^#", arg):
            return False
        if arg in ("--help", "-h") and not (previous.startswith("-") and "=" not in previous):
            return True
        previous = arg
    return False


# Push aliases defined in dot_gitconfig.tmpl.
ALIASES = {"publish": ["push", "--set-upstream"]}

pushes = []

for segment in segments(command):
    try:
        words = shlex.split(segment)
    except ValueError:
        continue

    # Strip ( { $( glued to the front of words and ) } to the back: (git push) -> git push.
    words = [w for w in (w.lstrip("({").removeprefix("$(").rstrip(")}") for w in words) if w]
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

    if args[cursor] in ALIASES:
        args = args[:cursor] + ALIASES[args[cursor]] + args[cursor + 1 :]
    if args[cursor] != "push":
        continue

    push_args = args[cursor + 1 :]
    if is_help(push_args):
        continue
    force = any(
        arg == "-f"
        or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:])
        or arg.startswith("--force")
        # A +refspec is a force push.
        or (len(arg) > 1 and arg.startswith("+"))
        for arg in push_args
    )
    pushes.append(("force" if force else "normal", "git push " + " ".join(push_args)))

if pushes:
    # The first line is "force" when any push in the command forces.
    print("force" if any(kind == "force" for kind, _ in pushes) else "normal")
    print("\n".join(dict.fromkeys(text for _, text in pushes)))
PYEOF
DETECTED=$("${PYTHON[@]}" "$PARSE_TMP" "$COMMAND") || exit 0
# A Windows-native Python translates \n to \r\n on stdout.
DETECTED=${DETECTED//$'\r'/}

[[ -z "$DETECTED" ]] && exit 0

PUSH_KIND=${DETECTED%%$'\n'*}
TARGET=$(printf '%s\n' "${DETECTED#*$'\n'}" | sed 's/^/  /')
if [[ "$PUSH_KIND" == "force" ]]; then
    # printf instead of $(cat <<EOF): a heredoc inside $( ) fails to parse on
    # bash 3.2 (macOS /bin/bash).
    REASON=$(printf '[Force push requires confirmation]

%s

Force-pushing can discard commits on the remote branch. Confirm this operation
explicitly if you intend to rewrite the remote history.
' "$TARGET")
else
    REASON=$(printf '[Git push requires confirmation]

%s

This command publishes commits to a remote repository. Confirm the operation
explicitly if you intend to update the remote branch.
' "$TARGET")
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
