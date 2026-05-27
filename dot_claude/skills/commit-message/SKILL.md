---
name: commit-message
description: Generate a concise, meaningful commit message from staged or unstaged Git changes and optionally create the commit after user confirmation. Use when the user asks for a commit message, asks to commit current changes, or wants a message that follows the repository's existing history style. Never add co-authored-by lines unless the user explicitly requests them.
---

# Commit Message Generator

Generate a concise, meaningful commit message based on the current staged changes.

## Steps

1. Run `git diff --cached --name-status` and `git diff --name-status` simultaneously to get the list of staged and unstaged files
2. Determine the commit target:
   - If there are staged files: use those as the commit target (ignore unstaged)
   - If there are no staged files but there are unstaged files: treat all unstaged files as the commit target (they will be staged with `git add` before committing)
   - If neither exists: inform the user there is nothing to commit and stop
3. Run `git diff --cached` (or `git diff` if using unstaged) to inspect the actual diff of the target files
4. Analyze the changes to understand:
   - What was changed (files, functions, logic)
   - Why it was likely changed (bug fix, feature, refactor, etc.)
5. Run `git log --oneline -20` to study the existing commit history and identify patterns:
   - Prefix style (e.g., `feat:`, `feat(scope):`, `[Feature]`, no prefix)
   - Language (English, Japanese, mixed)
   - Capitalization and punctuation conventions
   - Scope usage and format
6. Generate a commit message that **follows the existing commit history style as the top priority**
   - If the history has a consistent style, match it exactly
   - If no clear pattern exists, fall back to Conventional Commits format:
     - `feat:` for new features
     - `fix:` for bug fixes
     - `refactor:` for code restructuring without behavior change
     - `chore:` for maintenance tasks (deps, config, tooling)
     - `docs:` for documentation changes
     - `test:` for test additions or changes
     - `style:` for formatting changes
     - `perf:` for performance improvements
7. Keep the subject line under 72 characters
8. Write in imperative mood ("Add feature" not "Added feature")
9. If `$ARGUMENTS` is provided, treat it as additional context or a hint for the commit message

## Output

Present the generated commit message in a code block, then ask the user:

> このメッセージでコミットしますか？ [y/Edit/n]

- If the user replies `y` or `yes`: run `git commit -m "..."` immediately (if unstaged changes were the target, first run `git add <file1> <file2> ...` with each target file listed explicitly — never use `git add -A` or `git add .`— then commit)
- If the user replies with an edited message or asks to change it: use the updated message and commit
- If the user replies `n` or `cancel`: abort without committing

**IMPORTANT**: Do NOT add `Co-Authored-By` or any Claude attribution to the commit message. The commit author must be the user only.

## Example

For changes that add a new login button:
```
feat(auth): add login button to header
```

For a bug fix in payment processing:
```
fix(payment): handle nil response from payment gateway
```
