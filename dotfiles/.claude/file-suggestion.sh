#!/usr/bin/env bash
# Custom @-mention file suggestions for Claude Code.
#
# The built-in picker indexes with `git ls-files --others --exclude-standard`, so
# gitignored AI notes and plans never show up. This adds them back without giving up
# .gitignore: pass 1 walks the tree normally, pass 2 re-walks only the note directories
# listed in UNIGNORE_DIRS with VCS ignores disabled.
#
# Disabling .gitignore for the whole tree is not viable. In a workspace holding several
# repos and their worktrees it yields ~1.2M paths in ~5.8s, past the 5s timeout Claude
# Code allows this command, so every query returns nothing. Respecting .gitignore keeps
# the same tree at ~38k paths in ~0.17s.
#
# Input : JSON on stdin, with the current @ query in `.query`.
# Output: newline-separated paths on stdout, best match first.
#
# Troubleshooting: `touch ~/.claude/file-suggestion.debug` to log each invocation
# to ~/.claude/file-suggestion.log. Remove the flag file to stop logging.

set -uo pipefail

readonly MAX_RESULTS=100
readonly DEBUG_FLAG="$HOME/.claude/file-suggestion.debug"
readonly DEBUG_LOG="$HOME/.claude/file-suggestion.log"

# Gitignored directories to surface anyway, looked up at the top two levels so a
# workspace of repos resolves both ./notes and ./<repo>/notes.
readonly UNIGNORE_DIRS=(
  notes note plans plan memo memos scratch drafts draft .ai
)

# Gitignored files to surface anyway, same two levels.
readonly UNIGNORE_FILES=(
  CLAUDE.local.md AGENTS.local.md
)

readonly EXCLUDES=(
  # VCS
  '.git' '.hg' '.svn' '.jj'
  # Dependencies
  'node_modules' 'bower_components' 'vendor' 'Pods'
  '.venv' 'venv' '.direnv' '.bundle'
  # Build output
  'dist' 'build' 'out' 'target' 'obj'
  '.next' '.nuxt' '.svelte-kit' '.angular' '.output'
  'DerivedData' '.gradle'
  # Caches
  '.cache' '.turbo' '.parcel-cache' '__pycache__'
  '.mypy_cache' '.pytest_cache' '.ruff_cache' '.tox'
  # Test and coverage artifacts
  'coverage' '.nyc_output' 'playwright-report' 'test-results'
  # Editor and OS
  '.idea' '.DS_Store'
  # Infra state
  '.terraform' '*.tfstate' '*.tfstate.backup'
  # Secrets. Only the uncommitted forms, so .env.example stays reachable.
  '.env' '.env.local' '.env.*.local'
)

debug() {
  [[ -e $DEBUG_FLAG ]] || return 0
  printf '%s\t%s\n' "$(date -Iseconds)" "$*" >>"$DEBUG_LOG"
}

stdin_json=$(cat)
query=$(printf '%s' "$stdin_json" | jq -r '.query // ""' 2>/dev/null) || query=""

list_tracked() {
  fd --hidden --follow "${EXCLUDES[@]/#/--exclude=}"
}

list_unignored() {
  local dir search_paths=()
  for dir in "${UNIGNORE_DIRS[@]}"; do
    local candidate
    for candidate in "$dir" */"$dir"; do
      [[ -d $candidate ]] && search_paths+=(--search-path "$candidate")
    done
  done
  if ((${#search_paths[@]} > 0)); then
    fd --hidden --follow --no-ignore-vcs "${EXCLUDES[@]/#/--exclude=}" "${search_paths[@]}"
  fi

  local file
  for dir in "${UNIGNORE_FILES[@]}"; do
    for file in "$dir" */"$dir"; do
      [[ -f $file ]] && printf '%s\n' "$file"
    done
  done
}

list_paths() {
  { list_tracked; list_unignored; } 2>/dev/null | awk '!seen[$0]++'
}

if [[ -z $query ]]; then
  results=$(list_paths | head -n "$MAX_RESULTS")
else
  results=$(list_paths | fzf --filter="$query" | head -n "$MAX_RESULTS")
fi

debug "cwd=$PWD query=[$query] results=$(printf '%s' "$results" | grep -c . || true)"

printf '%s\n' "$results"
exit 0
