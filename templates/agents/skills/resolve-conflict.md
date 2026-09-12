---
name: resolve-conflict
description: Resolves the current Git conflict. Use when the user asks to "resolve the conflict", "resolve conflicts", "/resolve-conflict", or similar. Auto-detects whether a rebase or merge is in progress, or follows the explicit argument if given. Uses the current upstream/default branch if no base is specified.
argument-hint: "[--rebase|--merge] [--base <branch>]"
---

# resolve-conflict

Resolves an in-progress rebase/merge conflict, or starts a rebase/merge against a given base branch and resolves the resulting conflicts.

## Arguments

- `--rebase` / `--merge`: explicitly picks the method. If omitted, detect an in-progress rebase/merge via `git status` and follow it. If neither is in progress, default to rebase
- `--base <branch>`: the base branch. If omitted, use the upstream (`git rev-parse --abbrev-ref --symbolic-full-name @{u}`), or the repo's default branch (`origin/HEAD`) if there is no upstream

## Steps

1. Check `git status` for an in-progress rebase/merge and the list of conflicted files
2. If none is in progress, start one against the resolved base branch with `git rebase <base>` or `git merge <base>`
3. For each conflicted file, read it and resolve the conflict based on the intent of both sides. Ask the user when it's ambiguous
4. Stage resolved files explicitly with `git add <FILE>` (never `git add -A` / `git add .`)
5. Finish with `git rebase --continue` (rebase) or `git commit` (merge). For a rebase spanning multiple commits, repeat steps 3-5 until it completes
6. Confirm the working tree is clean via `git status` and report the result. Pushing, if needed, is left to the user

## Notes

- Never invent changes whose intent is unclear; always confirm with the user
- Only run `--abort` (`git rebase --abort` / `git merge --abort`) when the user explicitly asks for it
- This skill never pushes
