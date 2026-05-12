# Fix Issue

Implement a solution for GitHub issue `#$ARGUMENTS`. Follow these steps in order:

## Prerequisites
- Verify the current directory is a Git repository with a remote GitHub origin
- Ensure `gh` CLI is available and authenticated

## Step 1: Fetch Issue Details
```bash
gh issue view $ARGUMENTS --json title,body,labels,assignees
```

Understand the problem description, expected behavior, and any technical constraints.

## Step 2: Determine Branch Name
Examine existing branches to identify the naming convention:
```bash
git branch -a
```

Create a branch name that includes the issue number and follows the existing convention. If no pattern is found, use:
- `fix/issue-$ARGUMENTS-short-description` for bug fixes
- `feature/issue-$ARGUMENTS-short-description` for new features

Determine the type based on issue labels and content.

## Step 3: Create Branch
```bash
git switch main
git pull origin main
git switch -c [branch-name]
```

## Step 4: Implement the Solution
- Analyze relevant files and components
- Implement changes following existing code conventions
- Address all aspects of the issue

## Step 5: Verify
- Run existing tests
- Check for linting and type errors
- Confirm the solution works as expected

## Notes
- Do not commit changes — leave that to the user
- Ask for clarification if the issue is unclear
- Discuss with the user before adding dependencies or making significant architectural changes
- Use the TaskCreate tool to track progress

## Error Handling
- Stop and inform the user if the issue number doesn't exist
- Help resolve merge conflicts if they arise when pulling main
