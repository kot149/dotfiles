#!/usr/bin/env bash
# Warn when using a package manager different from the one detected in the project.
# Block by default; set FORCE_PM=1 to allow.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

[[ -z "$COMMAND" ]] && exit 0
[[ -z "$CWD" ]] && CWD=$(pwd)

detect_used_pm() {
    local cmd="$1"
    python3 - "$cmd" <<'PYEOF'
import sys, re, os

cmd = sys.argv[1]
segments = re.split(r'(?:&&|\|\||[;|]|\n)', cmd)

for seg in segments:
    seg = seg.strip()
    if not seg:
        continue
    words = seg.split()
    if not words:
        continue

    # Skip leading VAR=val assignments
    idx = 0
    while idx < len(words) and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', words[idx]):
        idx += 1
    if idx >= len(words):
        continue

    bin_name = os.path.basename(words[idx])

    next_word = words[idx + 1] if idx + 1 < len(words) else ''

    if bin_name in ('npm', 'npx'):
        print('npm'); sys.exit(0)
    elif bin_name == 'yarn':
        # yarn dlx はランナー、それ以外はPM操作
        print('yarn'); sys.exit(0)
    elif bin_name in ('pnpm', 'pnpx'):
        print('pnpm'); sys.exit(0)
    elif bin_name in ('pip', 'pip3') or re.match(r'pip3?\.\d+$', bin_name):
        print('pip'); sys.exit(0)
    elif bin_name == 'poetry':
        print('poetry'); sys.exit(0)
    elif bin_name == 'pipenv':
        print('pipenv'); sys.exit(0)
    elif bin_name == 'pdm':
        print('pdm'); sys.exit(0)
    elif bin_name == 'conda':
        print('conda'); sys.exit(0)
    elif bin_name in ('bun', 'bunx'):
        if bin_name == 'bunx' or next_word in ('install', 'add', 'remove', 'update', 'pm', 'x'):
            print('bun'); sys.exit(0)
    elif bin_name in ('uv', 'uvx'):
        if bin_name == 'uvx' or next_word in ('add', 'remove', 'sync', 'pip', 'lock'):
            print('uv'); sys.exit(0)
PYEOF
}

find_project_pm() {
    local dir="$1"
    local used="$2"

    # Only look for lock files in the same language family as the used PM,
    # otherwise a JS lock file in a parent dir can mask a Python project (or vice versa).
    local family=""
    case "$used" in
        npm|yarn|pnpm|bun) family="js" ;;
        pip|poetry|pipenv|pdm|uv|conda) family="py" ;;
    esac

    while true; do
        if [[ "$family" == "js" ]]; then
            [[ -f "$dir/yarn.lock" ]]         && echo "yarn"   && return 0
            [[ -f "$dir/pnpm-lock.yaml" ]]    && echo "pnpm"   && return 0
            [[ -f "$dir/bun.lockb" ]]         && echo "bun"    && return 0
            [[ -f "$dir/bun.lock" ]]          && echo "bun"    && return 0
            [[ -f "$dir/package-lock.json" ]] && echo "npm"    && return 0
        fi

        if [[ "$family" == "py" ]]; then
            [[ -f "$dir/uv.lock" ]]      && echo "uv"      && return 0
            [[ -f "$dir/poetry.lock" ]]  && echo "poetry"  && return 0
            [[ -f "$dir/Pipfile.lock" ]] && echo "pipenv"  && return 0
            [[ -f "$dir/pdm.lock" ]]     && echo "pdm"     && return 0
        fi

        # Stop at git root to avoid leaking into parent repos
        [[ -d "$dir/.git" ]] && break

        local parent
        parent=$(dirname "$dir")
        [[ "$parent" == "$dir" ]] && break
        dir="$parent"
    done

    return 1
}

USED_PM=$(detect_used_pm "$COMMAND") || exit 0
[[ -z "$USED_PM" ]] && exit 0
PROJECT_PM=$(find_project_pm "$CWD" "$USED_PM") || exit 0
[[ "$USED_PM" == "$PROJECT_PM" ]] && exit 0

# Allow if FORCE_PM=1 is set in env or prepended to the command
if [[ "${FORCE_PM:-}" == "1" ]] || echo "$COMMAND" | grep -q 'FORCE_PM=1'; then
    printf '[PM Warning] Using %s but project uses %s (FORCE_PM=1 set, allowing)\n' \
        "$USED_PM" "$PROJECT_PM" >&2
    exit 0
fi

cat <<EOF >&2
[Package Manager Mismatch]

  Detected PM: $USED_PM
  Project PM:  $PROJECT_PM  (detected from lock file)
  Project:     $CWD

Please use $PROJECT_PM instead.
To force execution, set FORCE_PM=1:

  FORCE_PM=1 $COMMAND
EOF
exit 2
