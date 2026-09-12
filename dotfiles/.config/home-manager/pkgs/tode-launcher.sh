#!/bin/sh
# Stands in for the launcher tode rewrites into its runtime tree on every start
# (dist/runtime/release.js:writeLauncher), which fails on a read-only store.
# TODE_TERMINAL_BROWSER_BIN points at this script so that rewrite is skipped;
# the env below has to match what writeLauncher would have produced.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
export TERMINAL_BROWSER_DIST_ROOT="$ROOT"
export ELECTRON_RUN_AS_NODE=1

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export TERMINAL_BROWSER_APPDATA="${TODE_BROWSER_APPDATA:-$DATA_HOME/tode/browser/chromium}"
export XDG_DATA_HOME="${TODE_BROWSER_DATA:-$DATA_HOME/tode/browser/share}"
export XDG_STATE_HOME="${TODE_BROWSER_STATE:-$STATE_HOME/tode/browser/state}"
export XDG_CACHE_HOME="${TODE_BROWSER_CACHE:-$CACHE_HOME/tode/browser}"
# XDG_RUNTIME_DIR keeps the session's own value unless tode overrides it.
if [ -n "${TODE_BROWSER_RUN:-}" ]; then export XDG_RUNTIME_DIR="$TODE_BROWSER_RUN"; fi
mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$TERMINAL_BROWSER_APPDATA"

ELECTRON="$ROOT/electron/terminal-browser.app/Contents/MacOS/terminal-browser"
if [ ! -x "$ELECTRON" ]; then
  ELECTRON="$ROOT/electron/electron"
else
  export NATIVE_SCROLL_HELPER="${NATIVE_SCROLL_HELPER:-$ROOT/bin/native-scroll-helper}"
fi

exec "$ELECTRON" "$ROOT/cli/dist/main.js" "$@"
