# Create Pull Request

You are tasked with creating a pull request for the current branch's changes on GitHub. Follow these steps in order.

Additional context provided by the user (e.g. related issue numbers, labels, or reviewers): $ARGUMENTS

## Prerequisites
- Verify that the current directory is a Git repository
- Ensure `gh` CLI tool is available and authenticated
- Confirm the repository has a remote GitHub origin
- Ensure the current branch is not `main` or the default branch

## Step 1: Check Current Branch Status
Verify the current branch and its status:
```bash
git status
git branch --show-current
```

If on `main` or default branch, inform the user that they should create a feature branch first with `git switch -c <branch-name>`.

## Step 2: Analyze Changes
Review all changes that will be included in the pull request:
```bash
git diff main...HEAD
git log main..HEAD --oneline
```

Understand:
- What files have been modified
- The scope and nature of changes
- All commits that will be included in the PR

## Step 3: Ensure Branch is Up to Date
Check if the current branch tracks a remote branch and push if needed:
```bash
git remote -v
git push -u origin $(git branch --show-current)
```

## Step 4: Generate PR Title and Description
Based on the commit history and changes:
- Create a concise, descriptive PR title
- Generate a comprehensive PR description including:
  - Summary of changes (1-3 bullet points)
  - Test plan or verification steps
  - Any breaking changes or migration notes
  - Related issue numbers if provided in $ARGUMENTS or inferable from branch/commit context

## Step 5: Create the Pull Request
Use the `gh` CLI to create the pull request. Format the body using a HEREDOC for proper formatting:
```bash
gh pr create --title "Title" --body "$(cat <<'EOF'
## Summary
- Change 1
- Change 2

## Test plan
- [ ] Test step 1
- [ ] Test step 2
EOF
)"
```

If reviewer or label information is provided in $ARGUMENTS, include the appropriate flags (e.g. `--reviewer <username>`, `--label <label>`).

## Step 6: Return PR URL
After successful creation, provide the PR URL to the user so they can view and share it.

## Important Notes
- Always analyze the full commit history from the divergence point, not just the latest commit
- Include all relevant commits in the PR summary
- Follow the existing PR template if one exists in the repository
- Generate meaningful test plans based on the changes made

## Error Handling
- If not on a feature branch, guide the user to create one first
- If there are no changes to create a PR for, inform the user
- If the remote branch doesn't exist, push it first with `-u` flag
- If `gh` is not authenticated, guide the user through authentication
