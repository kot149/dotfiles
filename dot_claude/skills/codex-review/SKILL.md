---
name: codex-review
description: Runs an adversarial code review with Codex CLI on uncommitted changes or current branch vs the default branch, fixes the identified issues, then re-reviews to verify. Use when the user asks to run codex review, wants an adversarial review of their changes, or asks to review and fix code with Codex.
---

# Codex Adversarial Review

Adversarial code review loop using Codex CLI: review → fix → validate → re-review.

Track iterations with TaskCreate (one task per pass) so progress is visible across the loop.

## Step 0: Prerequisites

```bash
command -v codex >/dev/null || { echo "codex CLI not installed"; exit 1; }
codex --version
```

If `codex` is missing or auth fails (the first review surfaces an auth error), stop and report to the user — do not silently fall back to a different reviewer.

## Step 1: Determine review scope

If the user did not specify a scope, detect it:

```bash
# Detect default branch (handles main / master / develop / trunk)
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

git status --short
git log --oneline "${DEFAULT_BRANCH}..HEAD" 2>/dev/null
```

Pick the scope:

- **Uncommitted changes only** → `--uncommitted`
- **Committed branch changes only** → `--base "$DEFAULT_BRANCH"`
- **Single commit of interest** → `--commit <SHA>`
- **Both uncommitted and branch commits** → ask the user which to review first; do not silently pick

## Step 2: Run adversarial review

The `[PROMPT]` argument is positional; `-` reads from stdin. The custom adversarial prompt is only useful with `--uncommitted` or `--commit` (see Notes for the `--base` constraint).

```bash
# Uncommitted (custom prompt via stdin):
codex review --uncommitted - <<'PROMPT'
You are an adversarial code reviewer. Ruthlessly critique these changes across:
- Bugs and logic errors (including edge cases)
- Security vulnerabilities
- Performance problems
- Code smells and maintainability issues
- Naming and readability
- Design flaws and inappropriate abstractions
- Missing error handling

For each issue: file path, line number, description, impact, suggested fix.
Miss nothing. Be uncompromising.
PROMPT

# Branch vs default branch (codex's built-in review prompt):
codex review --base "$DEFAULT_BRANCH"
```

**Reading the output reliably.** Codex often saves long output to a file and prints the path on stderr/stdout (e.g. `Review saved to /tmp/codex-review-XXXX.md`). Do not rely on `tail -N` — it can truncate issues.

1. Allocate a unique log file so concurrent runs don't clobber each other: `RUN_LOG=$(mktemp -t codex-run.XXXXXX.log)`
2. Capture the run's stdout+stderr: `codex review ... 2>&1 | tee "$RUN_LOG"`
3. Extract the saved-output path. Anchor on the literal "saved" line codex prints, then take the last `.md` path on it:
   ```bash
   SAVED=$(grep -iE 'saved (to|at)[: ]' "$RUN_LOG" | tail -1 | grep -oE '(/[^ ]+|[A-Za-z]:[\\/][^ ]+)\.md' | tail -1)
   ```
4. If `$SAVED` is empty, fall back to scanning the whole log for any `*.md` path (`grep -oE '/[^ ]+\.md' "$RUN_LOG" | tail -1`); if still empty, the review fit in the terminal — read `$RUN_LOG` directly.
5. Read the resolved file in full with the Read tool (use `offset`/`limit` if it exceeds the read window, working backwards from the end where the verdict lives).

Keep `$RUN_LOG` and the codex-saved `.md` around until the loop finishes — Step 5 references them. Surface both paths in your end-of-turn report so the user can re-open them; do not delete them yourself.

## Step 3: Triage and fix

If more than ~10 issues are reported, summarize them by severity to the user and confirm scope before mass-editing. For smaller batches, proceed.

Fix in this priority order:
1. Security vulnerabilities
2. Correctness bugs / logic errors
3. Missing error handling at trust boundaries
4. Performance problems with measured impact
5. Maintainability / naming / smells

For each issue: locate the exact line, understand the root cause, apply the fix with Edit. If an issue is a false positive or intentional, record the reason in your end-of-turn report — do not silently skip.

## Step 4: Validate fixes locally

Before re-running codex, verify nothing regressed. Run whichever of these the project supports (skip silently if absent):

```bash
# typecheck / lint / format
[ -f package.json ] && (jq -e '.scripts.typecheck' package.json >/dev/null && npm run typecheck; jq -e '.scripts.lint' package.json >/dev/null && npm run lint)
[ -f pyproject.toml ] && (command -v ruff >/dev/null && ruff check .; command -v mypy >/dev/null && mypy .)
[ -f Cargo.toml ] && cargo check && cargo clippy -- -D warnings

# tests (only if a fast suite exists; ask the user before running long suites)
```

Codex re-review (Step 5) does not execute code, so this step catches regressions codex cannot.

## Step 5: Re-review to verify

Re-run the same scope. Capture and read the output the same way as Step 2.

```bash
codex review --uncommitted - <<'PROMPT'
Verify all issues from the previous review have been fixed.
Report any remaining or newly introduced problems.
PROMPT
# or:
codex review --base "$DEFAULT_BRANCH"
```

- **Zero new issues** → report success, list fixed issues + any deliberate skips, link to the saved review file.
- **New/remaining issues** → return to Step 3. Hard cap at **3 total review passes (1 initial review + up to 2 re-reviews)**; if issues persist past that, summarize the remaining ones for the user instead of looping further.

## Notes

- `--base <BRANCH>` cannot be combined with a custom prompt (positional or `-` stdin). Verified: codex CLI rejects the combination at parse time with `error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`. In `--base` mode codex always uses its built-in review prompt; if you need a custom adversarial prompt against committed work, use `--commit <SHA>` per-commit instead.
- `--uncommitted` covers staged, unstaged, **and untracked** changes.
- Saved review output is typically 50–100 KB; the verdict is at the end of the file but earlier sections contain the per-issue details you need for fixing.
- Temp files created by this loop (`$RUN_LOG` and codex's saved `.md`) live in `$TMPDIR` / `/tmp` and are not auto-cleaned. Report their paths to the user at the end; let them decide whether to keep or delete.
