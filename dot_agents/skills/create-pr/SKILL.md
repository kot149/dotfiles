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

1. Check branch status with `git status`, `git branch --show-current`, and default branch information. If the current branch is the default branch, tell the user to create a feature branch first with `git switch -c <branch-name>` and stop.
2. Analyze changes from the divergence point. Prefer `git diff <default>...HEAD` and `git log <default>..HEAD --oneline`.
3. Check remotes with `git remote -v`.
4. If the branch has no remote counterpart, tell the user the exact command and the target (`git push -u origin <branch>` to `<remote>`), and ask before running it. Pushing is the first thing in this workflow that other people can see.
5. Check for an existing PR for the branch before creating a duplicate.
6. Generate a PR title and body from all included commits and changes.
7. Use an existing PR template if the repository provides one.
8. Create the PR with `gh pr create`, passing the body through a HEREDOC so the formatting survives:

   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   - <change 1>
   - <change 2>

   ## Test plan
   - [ ] <step 1>
   EOF
   )"
   ```

   Include labels, reviewers, draft mode, or issue references when the user requested them.
9. Return the PR URL.

## PR Body

Include:

- Summary of changes in 1-3 bullets
- Test plan or verification steps
- Breaking changes or migration notes, if any
- Related issues, if provided or inferable

## Error Handling

If the branch is the default branch, there are no commits to include, `gh` is unauthenticated, or the remote is not GitHub, stop and report the blocker with the next concrete command or action.

If the user declines the push, stop and report that a PR cannot be created without a remote branch.
