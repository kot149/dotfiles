---
name: resolve-conflict
description: Resolves the current Git conflict. Use when the user asks to "resolve the conflict", "resolve conflicts", "/resolve-conflict", 「コンフリクトを解決して」「競合を直して」「リベースの衝突を解決して」, or any similar phrasing in English or Japanese. Auto-detects whether a rebase or merge is in progress, or follows the explicit argument if given. Determines the base branch with evidence when none is specified.
argument-hint: "[--rebase|--merge] [--base <branch>]"
---

# resolve-conflict

Resolves an in-progress rebase/merge conflict, or starts a rebase/merge against a given base branch and resolves the resulting conflicts.

## Arguments

- `--rebase` / `--merge`: explicitly picks the method. If omitted, detect an in-progress rebase/merge via `git status` and follow it. If neither is in progress, default to rebase
- `--base <branch>`: the base branch. If omitted, determine it with the procedure in step 2

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Procedure

### 1. Check the current state

Run the following in parallel:

- `git status` — whether a rebase or merge is in progress, and the list of conflicted files
- `git status --porcelain` — uncommitted changes
- `git rev-parse --abbrev-ref HEAD` — current branch name

The two paths through this skill differ from here on, so settle which one applies first:

- **Joining**: a rebase or merge is already in progress. The base and the start point are already fixed by it
- **Starting**: nothing is in progress, so this skill starts one

The next two guards apply to the starting path only. Joining a conflict that is already in progress is always allowed: refusing it would leave the user stuck mid-operation.

**Never start a new rebase or merge on a protected branch such as `main` / `master`.** If the current branch is one of these, stop and present the following to the user in Japanese.

```
現在のブランチ <BRANCH> は保護ブランチのため、このスキルでは実行できません。
```

If `git status --porcelain` is not empty, stop and take the choice with a selection prompt (stash them, commit them first, or abort). Present the following to the user in Japanese.

```
未コミットの変更があります。この状態で <BASE> への rebase を開始すると失敗します。
どうしますか?
```

On the joining path, conflicted files show up in `git status` as a matter of course. Do not stash them.

### 2. Determine the base branch

Run this only on the starting path. On the joining path the base is already fixed by the operation in progress; skip to step 5.

When `--base <branch>` was given, adopt it and use the procedure below only to confirm it. Otherwise determine the base from local information with evidence. **Never guess `main`.**

{{ includeTemplate "agents/skills/_shared/git-base.md" . }}

This skill rebases or merges **onto the tip of `origin/<BASE>`**, not onto the merge-base: bringing the base-side commits in is the point of running it. Use `<MB>` from 2-5 only to report how far the branch has diverged.

### 3. Create a backup branch (mandatory)

Run this only on the starting path. Before starting a rebase or merge, **always** create a backup branch.

```bash
git branch "backup/$(git rev-parse --abbrev-ref HEAD)-resolve-$(date +%Y%m%d-%H%M%S)"
```

Note the created branch name (`<BACKUP_BRANCH>`) and the current HEAD SHA, verify the branch exists with `git branch --list "<BACKUP_BRANCH>"` before moving on, and present the following to the user in Japanese.

```
バックアップブランチを作成しました: <BACKUP_BRANCH> (元の HEAD: <SHA>)
```

On the joining path, HEAD is mid-operation and a backup of it is not a recovery point. Skip this step and say so in the final report, naming the original branch tip from `ORIG_HEAD` instead.

### 4. Start the rebase or merge

Run this only on the starting path.

```bash
git rebase origin/<BASE>
```

or, for `--merge`:

```bash
git merge origin/<BASE>
```

### 5. Resolve each conflicted file

For each conflicted file, read it and resolve the conflict based on the intent of both sides. Ask the user when it is ambiguous.

### 6. Stage and continue

Stage resolved files explicitly with `git add <FILE>` (never `git add -A` / `git add .`). Finish with `git rebase --continue` (rebase) or `git commit` (merge). For a rebase spanning multiple commits, repeat steps 5 and 6 until it completes.

### 7. Verify and report

Confirm the working tree is clean with `git status`. The report must cover only the following points.

- Whether this was a rebase or a merge, and against which base
- The list of resolved files
- The backup branch name and the original HEAD SHA. On the joining path, that no backup was created, plus the `ORIG_HEAD` SHA instead
- That `git status` is clean
- For a rebase, that the history has diverged from the remote, so a force push is needed. The user runs `git push --force-with-lease origin HEAD` themselves

## Notes

- Never invent changes whose intent is unclear; always confirm with the user
- Only run `--abort` (`git rebase --abort` / `git merge --abort`) when the user explicitly asks for it
- **Never start a new rebase or merge on a protected branch.** Joining a conflict that is already in progress on any branch is fine; starting one is not
- **Always create a backup branch before starting a rebase or merge.** Do not delete it on your own; leave deletion to the user's later judgment
- Do not use hook-disabling flags such as `--no-verify`
- This skill never pushes
