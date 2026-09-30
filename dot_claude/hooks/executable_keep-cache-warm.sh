#!/usr/bin/env bash
# Keep the 1h prompt cache warm while the session sits idle.
#
# Stop (asyncRewake): wait KEEPALIVE_DELAY seconds in the background. If the
# transcript has not grown in the meantime, exit 2 so Claude is woken with a
# tiny prompt, which re-reads and refreshes the cache. Pings stop after
# KEEPALIVE_MAX consecutive ones without user input.
# UserPromptSubmit (`reset` argument): clear the ping counter.

DELAY=${KEEPALIVE_DELAY:-3000}
MAX=${KEEPALIVE_MAX:-3}

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
[[ -z "$SESSION" ]] && exit 0

STATE_DIR="${TMPDIR:-/tmp}/claude-keepalive"
COUNT_FILE="$STATE_DIR/$SESSION"

if [[ "$1" == "reset" ]]; then
    rm -f "$COUNT_FILE"
    exit 0
fi

[[ -f "$TRANSCRIPT" ]] || exit 0
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
(( COUNT >= MAX )) && exit 0

SIZE=$(wc -c < "$TRANSCRIPT")
sleep "$DELAY"
[[ "$(wc -c < "$TRANSCRIPT")" == "$SIZE" ]] || exit 0

mkdir -p "$STATE_DIR"
echo $((COUNT + 1)) > "$COUNT_FILE"
echo 'Prompt cache keep-alive ping. Reply with just "ok" and do nothing else.' >&2
exit 2
