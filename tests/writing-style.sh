#!/usr/bin/env bash
# Codex apply_patch cases for check-writing-style.js: removed prose is ignored, added prose is checked.
set -u
hook=.chezmoitemplates/agents/check-writing-style.js
fail=0
run() { printf '%s' "$1" | bun run "$hook" 2>/dev/null; }
# A fresh session id each run: a denied payload arms a one-shot pass for an identical retry.
sid() { printf 'ws-%s-%s%s' "$1" "$RANDOM" "$RANDOM"; }
patch() { printf '{"session_id":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n%s\\n*** End Patch"}}' "$(sid "$1")" "$2"; }
denied() { [[ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision')" == deny && "$1" == *倒す* ]]; }
out=$(run "$(patch allow '*** Update File: a.md\n@@\n-判断は安全側に倒す。\n+この薬はよく効く。')")
[[ -z "$out" ]] || { echo "  x removed line was linted: $out"; fail=1; }
out=$(run "$(patch deny '*** Update File: a.md\n@@\n+判断は安全側に倒す。')")
denied "$out" || { echo "  x added line not denied: $out"; fail=1; }
out=$(run "$(patch move '*** Update File: a.json\n*** Move to: b.md\n@@\n+判断は安全側に倒す。')")
denied "$out" || { echo "  x added line in a moved file not denied: $out"; fail=1; }
(( fail == 0 )) || exit 1
echo "3/3 passed"
