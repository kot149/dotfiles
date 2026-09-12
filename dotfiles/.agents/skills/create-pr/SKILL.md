---
name: create-pr
description: Create a GitHub pull request for the current branch using GitHub CLI. Use when the user asks to create, draft, open, or prepare a PR from local branch changes, optionally with labels, reviewers, related issues, or extra PR context.
---

# Create Pull Request

Use `gh` for GitHub operations.

## Prerequisites

- Verify the current directory is a Git repository.
- Ensure `gh` is available and authenticated.
- Confirm the repository has a GitHub remote.
- Ensure the current branch is not `main`, `master`, or the default branch.

## Workflow

1. Check branch status with `git status`, `git branch --show-current`, and default branch information.
2. Analyze changes from the divergence point. Prefer `git diff <default>...HEAD` and `git log <default>..HEAD --oneline`.
3. Check remotes with `git remote -v`.
4. Push the branch if needed with `git push -u origin <branch>`.
5. Check for an existing PR for the branch before creating a duplicate.
6. Generate a PR title and body from all included commits and changes.
7. Use an existing PR template if the repository provides one.
8. Create the PR with `gh pr create`. Include labels, reviewers, draft mode, or issue references when the user requested them.
9. Return the PR URL.

## PR Body

Include:

- Summary of changes in 1-3 bullets
- Test plan or verification steps
- Breaking changes or migration notes, if any
- Related issues, if provided or inferable

## Error Handling

If the branch is the default branch, there are no commits to include, `gh` is unauthenticated, or the remote is not GitHub, stop and report the blocker with the next concrete command or action.
