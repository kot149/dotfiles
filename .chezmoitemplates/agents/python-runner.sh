# Resolve the Python used to run the inline parsers, as a PYTHON array.
# Callers keep their own `-` argument, so every branch reads the script from stdin:
#   "${PYTHON[@]}" - "$ARG" <<'PYEOF'
#
# uv comes first for portability: Windows has no /usr/bin/python3, and a bare
# python3 there may be absent or a Store stub. --script runs a standalone stdin
# script, so uv never looks for a surrounding project and never triggers an
# implicit sync. UV_PYTHON_DOWNLOADS=never keeps a missing interpreter from
# turning into a multi-minute download inside a hook that runs on every command.
# --python-preference only-system would do the same but costs ~0.2s per launch,
# which is more than the parser itself.
#
# Sourcing this exits the calling hook when no interpreter is available, which
# lets the hook pass the command through instead of blocking it.

# shellcheck disable=SC2034 # PYTHON is used by the sourcing hook
if command -v uv >/dev/null 2>&1 &&
    env UV_PYTHON_DOWNLOADS=never uv run --script - </dev/null >/dev/null 2>&1; then
    PYTHON=(env UV_PYTHON_DOWNLOADS=never uv run --script)
elif python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON=(python3)
elif python -c 'import sys' >/dev/null 2>&1; then
    PYTHON=(python)
else
    exit 0
fi
