#!/usr/bin/env bash
# check-writing-style.js cases: Codex apply_patch parsing, JSON writes, and gh bodies fed on stdin.
set -u
hook=.chezmoitemplates/agents/check-writing-style.js
fail=0
total=0
run() { printf '%s' "$1" | bun run "$hook" 2>/dev/null; }
# A fresh session id each run: a denied payload arms a one-shot pass for an identical retry.
sid() { printf 'ws-%s-%s%s' "$1" "$RANDOM" "$RANDOM"; }
patch() { printf '{"session_id":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n%s\\n*** End Patch"}}' "$(sid "$1")" "$2"; }
tool() { jq -nc --arg s "$(sid "$1")" --arg t "$2" --argjson i "$3" --arg cwd "$dir" '{session_id:$s,tool_name:$t,tool_input:$i,cwd:$cwd}'; }
bash_call() { tool "$1" Bash "$(jq -nc --arg c "$2" '{command:$c}')"; }
denied() { [[ "$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision')" == deny && "$1" == *倒す* ]]; }
expect_deny() { total=$((total + 1)); local out; out=$(run "$2"); denied "$out" || { echo "  x $1 not denied: $out"; fail=1; }; }
expect_pass() { total=$((total + 1)); local out; out=$(run "$2"); [[ -z "$out" ]] || { echo "  x $1 was flagged: $out"; fail=1; }; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
printf '{"a":"判断は安全側に倒す。"}' > "$dir/ja.json"
printf '{"a":"この薬はよく効く。"}' > "$dir/ok.json"

expect_pass "removed patch line" "$(patch allow '*** Update File: a.md\n@@\n-判断は安全側に倒す。\n+この薬はよく効く。')"
expect_deny "added patch line" "$(patch deny '*** Update File: a.md\n@@\n+判断は安全側に倒す。')"
expect_deny "added line in a moved file" "$(patch move '*** Update File: a.json\n*** Move to: b.md\n@@\n+判断は安全側に倒す。')"
expect_deny "added JSON patch line" "$(patch json '*** Add File: c.json\n+{\"a\": \"判断は安全側に倒す。\"}')"

expect_deny "JSON Write" "$(tool jw Write '{"file_path":"/x/ja.json","content":"{\"4397\":\"判断は安全側に倒す。\"}"}')"
expect_deny "JSON Edit fragment" "$(tool je Edit '{"file_path":"/x/ja.json","old_string":"x","new_string":"  \"b\": \"判断は安全側に倒す。\","}')"
expect_pass "JSON Write without Japanese" "$(tool jp Write '{"file_path":"/x/package.json","content":"{\"name\":\"to fall back\"}"}')"

# The shape that once posted unchecked: jq builds the body from a staged file and pipes it to gh.
session='S='"$dir"'
gh api repos/o/r/pulls/1/comments > $S/cur.json
for id in $(jq -r ".[].id" $S/cur.json); do
  jq -n --slurpfile cur $S/cur.json --slurpfile ja $S/NAME --arg id "$id" \
    '"'"'{query:"mutation", variables:{body:$ja[0].a}}'"'"' \
  | gh api graphql --input - --jq .data || echo "FAIL $id"
done'
expect_deny "jq --slurpfile piped to --input -" "$(bash_call slurp "${session//NAME/ja.json}")"
expect_pass "jq --slurpfile with a clean body" "$(bash_call slurpok "${session//NAME/ok.json}")"
expect_deny "jq input file piped to --input -" "$(bash_call jqin "jq '{body:.a}' $dir/ja.json | gh api repos/o/r/issues/1/comments --input -")"
expect_deny "redirect into --input -" "$(bash_call redir "gh api repos/o/r/issues/1/comments --input - < $dir/ja.json")"
expect_deny "cat piped to -F body=@-" "$(bash_call cat "cat $dir/ja.json | gh api repos/o/r/issues/1/comments -F body=@-")"

(( fail == 0 )) || exit 1
echo "$total/$total passed"
