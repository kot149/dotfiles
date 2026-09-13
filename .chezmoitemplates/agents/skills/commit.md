---
name: commit
description: Generate a concise, meaningful commit message from staged or unstaged Git changes and optionally create the commit after user confirmation. MUST be invoked for ANY request to create a git commit, including short or implicit ones like "commit", "commit it", "commit this", "コミット", "コミットして", "コミットお願い", "let's commit", or any similar phrasing in English or Japanese. Also use when the user asks for a commit message or wants a message that follows the repository's existing history style. Do NOT call `git commit` directly without first running this skill. Never add co-authored-by lines unless the user explicitly requests them.
---

# Commit Message Generator

Generate a concise, meaningful commit message based on the current staged changes.

## Steps

1. Determine the commit target:
   - **If the commit target is clear from the current session** (files you edited or created this session): use those session-touched files as the target. Files not touched this session are excluded — never stage or commit them silently. If such unrelated files are already staged, unstage them with `git reset HEAD <file>`; if they are unstaged, leave them alone and mention they were left out of the commit.
   - **Otherwise**, run `git diff --cached --name-status` and `git diff --name-status` simultaneously to get the list of staged and unstaged files, then:
     - If there are staged files: use those as the commit target (ignore unstaged)
     - If there are no staged files but there are unstaged files: treat all unstaged files as the commit target (they will be staged with `git add` before committing)
     - If neither exists: present the following to the user in Japanese and stop:

       ```
       コミット対象の変更がありません。
       ```
   - A target file may contain pre-existing changes beyond what this session made (modified by the user or another session before this session). That is fine — the commit includes the full working-tree diff of the target files. Always inspect the full `git diff` output for the target files (step 2) and write the message to cover the combined changes, not just the session delta.
2. Run `git diff --cached` (or `git diff` if using unstaged) on the target files to inspect the actual diff
3. Analyze the changes to understand:
   - What was changed (files, functions, logic)
   - Why it was likely changed (bug fix, feature, refactor, etc.)
4. Run `git log --oneline -20` to study the existing commit history and identify patterns:
   - Prefix style (e.g., `feat:`, `feat(scope):`, `[Feature]`, no prefix)
   - Language (English, Japanese, mixed)
   - Capitalization and punctuation conventions
   - Scope usage and format
5. Generate a commit message that **follows the existing commit history style as the top priority**
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
6. Keep the subject line under 72 characters
7. Write in imperative mood ("Add feature" not "Added feature")
8. If `$ARGUMENTS` is provided, treat it as additional context or a hint for the commit message

## Output

Generate **3 candidate commit messages** that vary in angle (e.g. different scope, emphasis on what vs. why, terse vs. descriptive) but all follow the repository's style. Then ask the user to choose via a selection UI tool (such as the `AskUserQuestion` tool):

- `question`: `どのコミットメッセージを使いますか？`
- `header`: `Commit msg` (short label)
- `multiSelect`: `false`
- `options`: one entry per candidate. Put the full commit message in `label` (keep under 72 chars so it fits) and a one-line rationale in `description` (e.g. "強調: 〜", "スコープ: 〜"). Recommend the strongest candidate by listing it first and appending ` (Recommended)` to its `label`.

Handling the user's answer:

- If the user picks one of the candidates: run `git commit -m "<selected label, minus the trailing ' (Recommended)' if present>"` immediately. If unstaged changes were the target, first run `git add <file1> <file2> ...` with each target file listed explicitly — never use `git add -A` or `git add .` — then commit. After committing, present the following to the user in Japanese (fill in the hash and subject):

  ```
  コミットを作成しました: <sha> <subject>
  ```

- If the user picks `Other` and supplies a custom message: use that text verbatim as the commit message and commit. After committing, present the `コミットを作成しました: <sha> <subject>` notice above to the user in Japanese.
- If the user cancels / picks nothing: abort without committing and present the following to the user in Japanese:

  ```
  キャンセルしました。コミットは作成していません。
  ```

On agents without a selection UI tool, present the same 3 candidates as a numbered list in plain text in Japanese, mark the recommended one, and let the user reply with a number or a message of their own. Do not commit before the user has chosen. Example (present the following to the user in Japanese):

```
コミットメッセージの候補は以下の通りです:
1. <candidate 1> (推奨)
   <rationale, e.g. 強調: 〜 / スコープ: 〜>
2. <candidate 2>
   <rationale>
3. <candidate 3>
   <rationale>

番号で選ぶか、独自のメッセージを入力してください。キャンセルする場合はその旨を伝えてください。
```

**IMPORTANT**: Do NOT add `Co-Authored-By` or any agent attribution to the commit message. The commit author must be the user only.

## Example

For changes that add a new login button:
```
feat(auth): add login button to header
```

For a bug fix in payment processing:
```
fix(payment): handle nil response from payment gateway
```
