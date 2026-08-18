---
name: fix-issue
description: Implement a solution for a GitHub issue using gh, branch conventions, focused code changes, and verification. Use when the user asks to fix issue #N, implement a GitHub issue, or start work from an issue number or URL.
---

# Fix Issue

Use `gh` for GitHub operations. Treat the user-provided issue number or URL as the target.

## Workflow

1. Verify the current directory is a Git repository with a GitHub remote and that `gh` is authenticated.
2. Fetch issue details with `gh issue view <issue> --json title,body,labels,assignees`.
3. Understand expected behavior, constraints, and acceptance criteria.
4. Inspect existing branches with `git branch -a` and infer branch naming conventions.
5. Create a branch name that includes the issue number. If no convention exists, use `fix/issue-<number>-short-description` for bugs and `feature/issue-<number>-short-description` for features.
6. Update the default branch, then create the work branch:
   - `git switch <default-branch>`
   - `git pull origin <default-branch>`
   - `git switch -c <branch-name>`
7. Implement the solution following project conventions. Keep changes scoped to the issue.
8. Run relevant tests, linters, and type checks.
9. Leave changes uncommitted unless the user explicitly asks to commit.

## Guardrails

- Ask for clarification if the issue is ambiguous.
- Discuss before adding dependencies or making significant architectural changes.
- Stop and report clearly if the issue does not exist, `gh` is unavailable, the default branch cannot be updated, or conflicts block progress.
