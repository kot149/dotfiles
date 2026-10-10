#!/usr/bin/env bash
# Prefer cargo-binstall over cargo install, which builds from source.
# Only fires when cargo-binstall is actually available.
# Block by default; set FORCE_CARGO_INSTALL=1 to allow.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[[ -z "$COMMAND" ]] && exit 0
command -v cargo-binstall >/dev/null 2>&1 || exit 0

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

# A heredoc inside $( ) fails to parse on bash 3.2 (macOS /bin/bash), so the
# parser runs from a temporary file written by a top-level heredoc instead.
PARSE_TMP=$(mktemp)
trap 'rm -f "$PARSE_TMP"' EXIT
cat >"$PARSE_TMP" <<'PYEOF'
import os
import re
import sys

command = sys.argv[1].replace("\r\n", "\n")

# Flags that take a separate value, so the value itself is not a crate name.
VALUE_FLAGS = {
    "--path", "--git", "--branch", "--tag", "--rev", "--index", "--registry",
    "--version", "--profile", "--target", "--target-dir", "--root", "--bin",
    "--example", "--features", "--jobs", "--config", "--manifest-path",
    "--message-format", "--timings", "--color", "-j", "-Z", "-F",
}

# cargo install is the only reasonable route for these.
LOCAL_FLAGS = {"--path", "--git", "--list"}

for segment in re.split(r"(?:&&|\|\||[;|]|\n)", command):
    words = segment.split()
    idx = 0
    while idx < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[idx]):
        idx += 1
    if idx >= len(words):
        continue
    if os.path.basename(words[idx]) != "cargo":
        continue

    args = words[idx + 1:]
    # cargo +nightly install ...
    if args and args[0].startswith("+"):
        args = args[1:]
    if not args or args[0] != "install":
        continue

    args = args[1:]
    if any(arg.split("=", 1)[0] in LOCAL_FLAGS for arg in args):
        continue

    crates = []
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg.startswith("-"):
            if "=" not in arg and arg in VALUE_FLAGS:
                skip_next = True
            continue
        crates.append(arg)

    # Bootstrapping binstall itself has to go through cargo install.
    if crates == ["cargo-binstall"]:
        continue

    print(" ".join(crates) if crates else "")
    sys.exit(0)
PYEOF
TARGET=$("${PYTHON[@]}" "$PARSE_TMP" "$COMMAND") || exit 0
# A Windows-native Python translates \n to \r\n on stdout.
TARGET=${TARGET//$'\r'/}

[[ -z "$TARGET" ]] && exit 0

if [[ "${FORCE_CARGO_INSTALL:-}" == "1" ]] || echo "$COMMAND" | grep -q 'FORCE_CARGO_INSTALL=1'; then
    printf '[Cargo Warning] cargo install %s (FORCE_CARGO_INSTALL=1 set, allowing)\n' "$TARGET" >&2
    exit 0
fi

# printf instead of $(cat <<EOF): a heredoc inside $( ) fails to parse on
# bash 3.2 (macOS /bin/bash).
REASON=$(printf '[Use cargo-binstall instead of cargo install]

  Crate(s): %s

cargo install builds from source and can take minutes. cargo-binstall is
installed on this machine and fetches a prebuilt binary instead, falling back
to a source build only when no release artifact exists:

  cargo binstall %s

If a source build is required (a patched fork, a crate with no release
artifact, non-default features), re-run with FORCE_CARGO_INSTALL=1 prepended
to the command.
' "$TARGET" "$TARGET")

printf '%s\n' "$REASON" >&2

"${PYTHON[@]}" - "$REASON" <<'PYEOF'
import json, sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PYEOF
