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
# Claude Code runs this on every keystroke, so the path list is cached per $PWD and
# served from the cache while a background fd run refreshes it. New files show up from
# the next query after the refresh. The first query in a directory waits for fd.
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
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-file-suggestion"
# Seconds a cached list is served before a background refresh starts. Keeps fast
# typing from running fd on every keystroke.
readonly REFRESH_INTERVAL=5
# A refresh lock older than this many minutes belongs to a killed run.
readonly STALE_LOCK_MINUTES=1

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

escape_glob() {
  local s=${1//\\/\\\\}
  s=${s//\*/\\*}
  s=${s//\?/\\?}
  s=${s//\[/\\[}
  s=${s//\{/\\{}
  printf '%s' "$s"
}

# Pass 1 excludes the paths pass 2 lists, anchored to the search root, so no path is
# printed twice and the output needs no dedup pass.
list_paths() {
  local name path unignored_dirs=() unignored_files=()
  for name in "${UNIGNORE_DIRS[@]}"; do
    for path in "$name" */"$name"; do
      [[ -d $path ]] && unignored_dirs+=("$path")
    done
  done
  for name in "${UNIGNORE_FILES[@]}"; do
    for path in "$name" */"$name"; do
      [[ -f $path ]] && unignored_files+=("$path")
    done
  done

  local excludes=("${EXCLUDES[@]/#/--exclude=}") pass1_excludes
  pass1_excludes=("${excludes[@]}")
  for path in "${unignored_dirs[@]}" "${unignored_files[@]}"; do
    pass1_excludes+=("--exclude=/$(escape_glob "$path")")
  done

  fd --hidden --follow "${pass1_excludes[@]}"
  if ((${#unignored_dirs[@]} > 0)); then
    printf '%s/\n' "${unignored_dirs[@]}"
    fd --hidden --follow --no-ignore-vcs "${excludes[@]}" "${unignored_dirs[@]/#/--search-path=}"
  fi
  if ((${#unignored_files[@]} > 0)); then
    printf '%s\n' "${unignored_files[@]}"
  fi
}

# Rewrites the cache atomically. Returns 1 when another run holds the lock. Run it in
# a subshell: the EXIT trap releases the lock, so lock and tmp are not local.
refresh_cache() {
  lock=$cache_file.lock
  if ! mkdir "$lock" 2>/dev/null; then
    [[ -n $(find "$lock" -maxdepth 0 -mmin +"$STALE_LOCK_MINUTES" 2>/dev/null) ]] || return 1
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 1
  fi
  tmp=$(mktemp "$cache_file.XXXXXX") || { rmdir "$lock"; return 1; }
  trap 'rm -f "$tmp"; rmdir "$lock" 2>/dev/null' EXIT
  trap 'exit 1' HUP INT TERM
  # fd exits non-zero on unreadable directories, so its status is not checked.
  list_paths 2>/dev/null >"$tmp"
  mv -f "$tmp" "$cache_file" && date +%s >"$cache_file.time"
}

# A path query (~/x, /x, ./x, ../x) lists the entries of its directory part, hidden
# and ignored ones included, and fuzzy-matches the last component.
if [[ $query == \~/* || $query == /* || $query == ./* || $query == ../* ]]; then
  dir_part=${query%/*}/
  base_part=${query##*/}
  results=$(
    fd --hidden --no-ignore --max-depth 1 --base-directory "${dir_part/#\~\//$HOME/}" 2>/dev/null |
      fzf --filter="$base_part" |
      head -n "$MAX_RESULTS" |
      while IFS= read -r entry; do printf '%s%s\n' "$dir_part" "$entry"; done
  )
  debug "cwd=$PWD cache=path query=[$query] results=$(printf '%s' "$results" | grep -c . || true)"
  printf '%s\n' "$results"
  exit 0
fi

[[ -d $CACHE_DIR ]] || mkdir -p "$CACHE_DIR"
cache_key=$(printf '%s' "$PWD" | cksum)
cache_file="$CACHE_DIR/${cache_key%% *}"

if [[ -f $cache_file ]]; then
  cache=hit
  refreshed_at=0
  [[ -f $cache_file.time ]] && read -r refreshed_at <"$cache_file.time"
  if (($(date +%s) - refreshed_at >= REFRESH_INTERVAL)); then
    (refresh_cache) </dev/null >/dev/null 2>&1 &
    disown
  fi
  list() { cat "$cache_file"; }
elif (refresh_cache); then
  cache=miss
  list() { cat "$cache_file"; }
else
  cache=bypass
  list() { list_paths 2>/dev/null; }
fi

if [[ -z $query ]]; then
  results=$(list | head -n "$MAX_RESULTS")
else
  results=$(list | fzf --filter="$query" | head -n "$MAX_RESULTS")
fi

debug "cwd=$PWD cache=$cache query=[$query] results=$(printf '%s' "$results" | grep -c . || true)"

printf '%s\n' "$results"
exit 0
