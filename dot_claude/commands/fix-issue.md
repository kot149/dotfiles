# Fix Issue

You are tasked with implementing a solution for a GitHub issue. Follow these steps in order:

## Prerequisites
- Verify that the current directory is a Git repository
- Ensure `gh` CLI tool is available and authenticated
- Confirm the repository has a remote GitHub origin

## Step 1: Fetch Issue Details
Use the `gh` command to retrieve the issue details for issue number `#$ARGUMENTS`:
```bash
gh issue view $ARGUMENTS --json title,body,labels,assignees
```

Analyze the issue content to understand:
- The problem description
- Expected behavior
- Steps to reproduce (if applicable)
- Any technical requirements or constraints

## Step 2: Analyze Existing Branch Naming Convention
Before creating a new branch, examine existing branches to understand the naming convention:
```bash
git branch -a
```

Look for patterns such as:
- `feature/issue-123-description`
- `fix/123-short-description`
- `issue-123`
- `bugfix/issue-123`

If only `main` branch exists or no clear pattern is found, use a default naming convention.

## Step 3: Create Appropriate Branch Name
Based on the issue content and existing naming patterns, create a descriptive branch name that:
- Includes the issue number
- Follows the existing convention if found
- Is concise but descriptive
- Uses kebab-case formatting

Naming priority:
1. If existing pattern is found, follow it (e.g., `feature/issue-$ARGUMENTS-description`)
2. If no pattern exists, use default format: `fix/issue-$ARGUMENTS-short-description` for bug fixes or `feature/issue-$ARGUMENTS-short-description` for new features
3. Determine if it's a bug fix or feature based on issue labels and content

## Step 4: Create and Switch to New Branch
```bash
git checkout main
git pull origin main
git checkout -b [generated-branch-name]
```

## Step 5: Implement the Solution
- Analyze the codebase to understand the relevant files and components
- Implement the necessary changes to resolve the issue
- Follow existing code conventions and patterns
- Ensure the solution addresses all aspects mentioned in the issue

## Step 6: Verify the Implementation
- Run any existing tests to ensure nothing is broken
- Test the specific functionality mentioned in the issue
- Check for linting and type errors if applicable
- Verify the solution works as expected

## Important Notes
- Always start from the latest `main` branch
- Do not commit changes automatically - leave that decision to the user
- If the issue is unclear or requires clarification, ask the user before proceeding
- If the implementation requires additional dependencies or significant architectural changes, discuss with the user first
- Use the TodoWrite tool to track your progress through the implementation steps

## Error Handling
- If the issue number doesn't exist, inform the user and stop
- If the repository is not connected to GitHub, guide the user to set up the remote
- If there are merge conflicts when pulling main, help resolve them before proceeding