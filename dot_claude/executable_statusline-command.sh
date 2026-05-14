#!/usr/bin/env bash

input=$(cat)

# From CC hook data
cwd_raw=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
cwd=$(echo "$cwd_raw" | sed "s|^$HOME|~|")
model=$(echo "$input" | jq -r '.model.display_name // .model.id // ""')
ctx_pct=$(echo "$input" | jq -r '(.context_window.used_percentage // 0) + 0.5 | floor')

RATE_CACHE="$HOME/.claude/statusline-rate-cache.json"
MODE_CACHE="$HOME/.claude/statusline-mode-cache"

five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // "" | if . == "" then "" else (. + 0.5 | floor | tostring) end')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // ""')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // "" | if . == "" then "" else (. + 0.5 | floor | tostring) end')
seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // ""')

# API billing cost (field path: .cost.total_cost_usd)
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // ""')

# Detect API billing mode
# Priority: 1) ANTHROPIC_API_KEY env var, 2) .cost.total_cost_usd is a number, 3) rate_limits presence, 4) mode cache
_cost_is_num=$(echo "$input" | jq -r '(.cost.total_cost_usd | type) == "number"')
_has_sub_limits=$(echo "$input" | jq -r '(.rate_limits != null) and ((.rate_limits.five_hour.used_percentage | type) == "number")')

if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ "$_cost_is_num" = "true" ]; then
  is_api_mode="true"
  echo "api" > "$MODE_CACHE"
elif [ "$_has_sub_limits" = "true" ]; then
  is_api_mode="false"
  echo "subscription" > "$MODE_CACHE"
elif [ -f "$MODE_CACHE" ]; then
  _cached_mode=$(cat "$MODE_CACHE")
  [ "$_cached_mode" = "api" ] && is_api_mode="true" || is_api_mode="false"
else
  is_api_mode="false"
fi

# Update rate limit cache (subscription mode only)
if [ "$is_api_mode" = false ] && { [ -n "$five_pct" ] || [ -n "$seven_pct" ]; }; then
  jq -n \
    --arg fp "$five_pct" --arg fr "$five_reset" \
    --arg sp "$seven_pct" --arg sr "$seven_reset" \
    '{five_pct:$fp,five_reset:$fr,seven_pct:$sp,seven_reset:$sr}' > "$RATE_CACHE"
elif [ "$is_api_mode" = false ] && [ -f "$RATE_CACHE" ]; then
  five_pct=$(jq -r '.five_pct // ""' "$RATE_CACHE")
  five_reset=$(jq -r '.five_reset // ""' "$RATE_CACHE")
  seven_pct=$(jq -r '.seven_pct // ""' "$RATE_CACHE")
  seven_reset=$(jq -r '.seven_reset // ""' "$RATE_CACHE")
fi

now_epoch=$(date +%s)

# Format remaining seconds as Xh00m
fmt_hm() {
  local secs=${1:-0}
  [ "$secs" -lt 0 ] && secs=0
  local h=$(( secs / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  printf "%dh%02dm" "$h" "$m"
}

# Format remaining seconds as Xd00h00m
fmt_dhm() {
  local secs=${1:-0}
  [ "$secs" -lt 0 ] && secs=0
  local d=$(( secs / 86400 ))
  local h=$(( (secs % 86400) / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  printf "%dd%02dh%02dm" "$d" "$h" "$m"
}

# Git branch + status
git_info=""
if [ -n "$cwd_raw" ]; then
  if git_branch_raw=$(git -C "$cwd_raw" -c core.fsmonitor= symbolic-ref --short HEAD 2>/dev/null); then
    staged=$(git -C "$cwd_raw" -c core.fsmonitor= diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git -C "$cwd_raw" -c core.fsmonitor= diff --name-only --diff-filter=M 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -C "$cwd_raw" -c core.fsmonitor= ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    deleted=$(git -C "$cwd_raw" -c core.fsmonitor= diff --name-only --diff-filter=D 2>/dev/null | wc -l | tr -d ' ')
    git_info=" $git_branch_raw"
    parts=""
    upstream=$(git -C "$cwd_raw" -c core.fsmonitor= rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    if [ -n "$upstream" ]; then
      ahead_count=$(git -C "$cwd_raw" -c core.fsmonitor= rev-list --count "$upstream"..HEAD 2>/dev/null || echo 0)
      behind_count=$(git -C "$cwd_raw" -c core.fsmonitor= rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
      [ "$ahead_count" -gt 0 ] && [ "$behind_count" -gt 0 ] && parts="$parts  $behind_count $ahead_count"
      [ "$ahead_count" -gt 0 ] && [ "$behind_count" -eq 0 ] && parts="$parts  $ahead_count"
      [ "$behind_count" -gt 0 ] && [ "$ahead_count" -eq 0 ] && parts="$parts  $behind_count"
      [ "$ahead_count" -eq 0 ] && [ "$behind_count" -eq 0 ] && parts="$parts ✔"
    fi
    [ "$staged" -gt 0 ]    && parts="$parts +$staged"
    [ "$untracked" -gt 0 ] && parts="$parts  $untracked"
    [ "$modified" -gt 0 ]  && parts="$parts  $modified"
    [ "$deleted" -gt 0 ]   && parts="$parts 󰗨 $deleted"
    [ -n "$parts" ] && git_info="$git_info$parts "
  fi
fi

# 5h rate limit block remaining
five_str=""
if [ "$is_api_mode" = false ] && [ -n "$five_pct" ] && [ -n "$five_reset" ] && [ "$five_reset" != "null" ]; then
  remaining=$(( five_reset - now_epoch ))
  five_str="5h: ${five_pct}% (⏱ $(fmt_hm $remaining))"
fi

# 7d rate limit remaining
seven_str=""
if [ "$is_api_mode" = false ] && [ -n "$seven_pct" ] && [ -n "$seven_reset" ] && [ "$seven_reset" != "null" ]; then
  remaining=$(( seven_reset - now_epoch ))
  seven_str="7d: ${seven_pct}% (⏱ $(fmt_dhm $remaining))"
fi

# API billing cost display
cost_str=""
if [ "$is_api_mode" = true ]; then
  if [ -n "$total_cost" ]; then
    cost_str=$(printf "total: \$%.4f" "$total_cost")
  fi
fi

# Output: items separated by " | "
SEP="\033[0m\033[38;5;240m | \033[0m"

printf "\033[38;5;214m%s\033[0m" "$cwd"
if [ -n "$git_info" ]; then
  printf "$SEP"
  printf "\033[38;5;141m%s\033[0m" "$git_info"
fi
if [ -n "$model" ]; then
  printf "$SEP"
  printf "\033[38;5;67m%s\033[0m" "$model"
fi
printf "$SEP"
printf "\033[38;5;109mctx: %s%%\033[0m" "$ctx_pct"
if [ -n "$five_str" ]; then
  printf "$SEP"
  printf "\033[38;5;208m%s\033[0m" "$five_str"
fi
if [ -n "$seven_str" ]; then
  printf "$SEP"
  printf "\033[38;5;208m%s\033[0m" "$seven_str"
fi
if [ -n "$cost_str" ]; then
  printf "$SEP"
  printf "\033[38;5;208m%s\033[0m" "$cost_str"
fi
printf "\n"
