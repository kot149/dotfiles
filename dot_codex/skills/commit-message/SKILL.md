---
name: commit-message
description: Generate a concise commit message from staged or unstaged Git changes and optionally create the commit after user confirmation. Use when the user asks for a commit message, asks to commit current changes, or wants a message following repository history. Never add co-authored-by lines unless the user explicitly requests them.
---

# Commit Message Generator

Generate a meaningful commit message based on the current target changes.

## Steps

1. Determine the commit target:
   - **If the commit target is clear from the current session** (files you edited or created this session): use those session-touched files as the target. Still run `git diff --cached --name-status` and `git diff --name-status` to detect two hazards, and handle them before committing:
     - The same file may have been modified by another session or by the user outside this session. If a target file has unexpected changes beyond what this session made, stop and confirm with the user before committing.
     - Files unrelated to this session may already be staged. Reset them out of the index (`git reset HEAD <file>`) so only session-touched files are committed. Do not include them silently.
   - **Otherwise**, inspect `git diff --cached --name-status` and `git diff --name-status`:
     - If staged files exist, use only staged files.
     - If no staged files exist but unstaged files exist, treat unstaged files as the target and stage only those explicit files before committing.
     - If neither exists, tell the user there is nothing to commit and stop.
2. Inspect the actual target diff with `git diff --cached` or `git diff` (limited to target paths).
3. Review recent history with `git log --oneline -20` and match its style as the top priority.
4. Generate a subject under 72 characters in imperative mood.
5. Treat any user-provided context as a hint, not as a substitute for reading the diff.

## Style Fallback

If history has no clear pattern, use Conventional Commits:

- `feat:` for new features
- `fix:` for bug fixes
- `refactor:` for behavior-preserving restructuring
- `chore:` for maintenance
- `docs:` for documentation
- `test:` for tests
- `style:` for formatting
- `perf:` for performance improvements

## Confirmation

Show the generated message in a code block, then ask:

`このメッセージでコミットしますか？ [y/Edit/n]`

If the user approves, run `git commit -m "..."`. If the target was unstaged, first run `git add` with each target path explicitly. Never use `git add -A` or `git add .`. Do not add `Co-Authored-By` or AI attribution.
