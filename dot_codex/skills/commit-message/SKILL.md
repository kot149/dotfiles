---
name: commit-message
description: Generate a concise commit message from staged or unstaged Git changes and optionally create the commit after user confirmation. Use when the user asks for a commit message, asks to commit current changes, or wants a message following repository history. Never add co-authored-by lines unless the user explicitly requests them.
---

# Commit Message Generator

Generate a meaningful commit message based on the current target changes.

## Steps

1. Inspect staged and unstaged files with `git diff --cached --name-status` and `git diff --name-status`.
2. Determine the commit target:
   - If staged files exist, use only staged files.
   - If no staged files exist but unstaged files exist, treat unstaged files as the target and stage only those explicit files before committing.
   - If neither exists, tell the user there is nothing to commit and stop.
3. Inspect the actual target diff with `git diff --cached` or `git diff`.
4. Review recent history with `git log --oneline -20` and match its style as the top priority.
5. Generate a subject under 72 characters in imperative mood.
6. Treat any user-provided context as a hint, not as a substitute for reading the diff.

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
