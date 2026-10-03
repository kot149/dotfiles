---
name: fixup
description: Skill for folding current uncommitted changes into the appropriate existing commit. Use when the user asks to "fixup this", "fold into existing commit", "create a fixup commit", or similar. By default uses `git commit --fixup=<sha>` (just stacking a fixup commit, method A); when the user explicitly requests it or the `--method=B` argument is passed, uses `git history fixup <sha>` (rewriting history in place, method B, requires git 2.55+). When `--autosquash` is passed, stacks the fixup commit with method A and then continues to run autosquash. Determine the owning commit for each change mechanically with `git blame` / `git log -p`, present the plan to the user, and execute without waiting for approval.
argument-hint: "[--method=A|B] [--autosquash]"
---

# fixup

A skill that analyzes uncommitted changes (staged / unstaged), determines which existing commit each change belongs to, and fixups them.

There are two methods, with method A as the default (see "5. Choose the method").

| Method | Command | History rewrite |
| --- | --- | --- |
| A: fixup-commit method | `git commit --fixup=<sha>` | No (autosquash needed later) |
| B: history-rewrite method | `git history fixup <sha>` | Done in place (no autosquash needed) |

With method A, reordering history with autosquash is not this skill's responsibility by default. Stop after stacking the fixup commit; if the user wants to continue with autosquash, point them to the [[autosquash]] skill. Only when the `--autosquash` argument is passed does this skill continue through autosquash (see "Arguments").

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Arguments

`--method=A` / `--method=B`:

- Takes precedence over the method selection in step 5. Use the specified method as-is, with no user confirmation or inference
- When `--method=B` is specified, if the prerequisites are not met (older than git 2.55) or the history contains merge commits (`git log --merges <MB>..HEAD` returns hits), do not fall back to method A; stop with the reason and ask the user for confirmation. Present the following to the user in Japanese (fill in the reason): `"方法Bは使えません（理由: <REASON>）。方法Aに切り替えますか、それとも中止しますか？"`

`--autosquash` (alone or alongside other instructions):

- Applies only to method A (the default, or when `--method=A` is specified). **If combined with `--method=B`, the combination is contradictory, so stop before executing and ask the user for confirmation** (method B completes by rewriting history in place, so there is no role for autosquash). Present the following to the user in Japanese: `"--autosquash は方法A専用のため、--method=B とは併用できません。どちらで進めますか？（Aに切り替え / Bのままautosquashなし / 中止）"`
- In the step 6 plan, explicitly state that "after stacking the fixup commit, autosquash will also run" (do not wait for approval). Present the following to the user in Japanese: `"fixupコミットを積んだ後、そのまま autosquash まで続けて実行します（承認待ちなし）。"`
- After stacking the fixup commit in step 7-A, run the step 8 check and then execute the [[autosquash]] skill (step 10)

With no arguments, only present the plan in step 6 and do not run autosquash (if the user wants to continue with autosquash, point them to the [[autosquash]] skill).

## Prerequisites

- The working directory is inside a Git repository
- The current branch is not a protected branch (`main` / `master` / `develop`, etc.)
- When choosing method B, git 2.55 or later is required (check with `git --version`)

## Steps

### 1. Check the current state

Run the following in parallel to understand the current state:

- `git status --short` — list of files with uncommitted changes
- `git rev-parse --abbrev-ref HEAD` — current branch name
- `git diff --stat` — summary of unstaged diffs
- `git diff --cached --stat` — summary of staged diffs
- `git --version` — used to decide whether method B (`git history fixup`) is available

If there are no uncommitted changes, present the following to the user in Japanese: `"fixup対象の変更がありません"` and stop.

If the current branch is a protected branch such as `main` / `master` / `develop`, stop and present the following to the user in Japanese (fill in the branch name): `"現在のブランチ <BRANCH> は保護ブランチのため、このスキルは実行できません。"`

### 2. Determine the merge-target branch (base) and the fork point

Decide the base branch and fork point to pin down the range of commits eligible for fixup. This is decided from local information alone, so `gh` is not required.

{{ includeTemplate "agents/skills/_shared/git-base.md" . }}

The fixup-eligible range is `<MB>..HEAD`, where `<MB>` is the merge-base from step 2.

### 3. Collect candidate fixup-target commits

```bash
git log --oneline <MB>..HEAD
```

These are the commits on the branch that can accept a fixup. Exclude commits already prefixed with `fixup!` / `squash!` from fixup targets (they are themselves tied to an original commit).

If there are 0 candidate commits, stop and present the following to the user in Japanese: `"fixup可能なコミットがありません。通常の git commit を使ってください。"`

### 4. Determine the owning commit for each change

**Target both staged and unstaged changes.** However, a mix is hard to analyze, so tidy up the state first:

- If both staged and unstaged changes exist, treat both together as fixup candidates. Stage the unstaged portion with an explicit `git add <FILES...>` on the target files before proceeding with analysis (do not use `git add -A` / `git add .`). Present the following to the user in Japanese (fill in the file list): `"未ステージの変更をステージしました: <FILES>"`

Once the target range is fixed, infer the owning commit for each change as follows:

#### 4-1. Coarse per-file inference

For each changed file:

```bash
git log --oneline <MB>..HEAD -- <FILE>
```

This lists the candidate commits touching the file. If there is exactly one, it is the first candidate.

#### 4-2. Precise per-line inference (recommended)

Trace which commit introduced the changed lines with `git blame`:

```bash
git diff [--cached] -U0 <FILE>
```

For each hunk, find the origin of the target lines (deleted lines / pre-change context lines) with:

```bash
git blame -L <start>,<end> HEAD -- <FILE>
```

If the blamed commit SHA is inside the `<MB>..HEAD` range, it is the strongest fixup candidate. If it is outside the range (a commit older than the base), switch to proposing a fixup into the newest in-branch commit that touches the file.

**Hunks consisting only of newly added lines** cannot be traced with blame, so pick from the per-file candidates in 4-1.

#### 4-3. When the evidence is split

If changes belonging to multiple commits are mixed within a single file, split the fixup targets per hunk. This requires rearranging the staged state per hunk, so follow the splitting procedure in A-2.

#### 4-4. Decide fixup-commit granularity (method A)

With method A, **split `fixup!` commits by unit of meaning even when the owning commit is the same.** Do not combine them into one giant `fixup!` per owning commit. Keeping them split allows reviewing and reverting each one individually before autosquash.

Guidelines for splitting:

- **One commit per review comment.** Even for multiple comments on the same commit, create one fixup commit per comment
- Split different kinds of changes (bug fix / refactoring / typo fix, etc.) by kind
- Split changes that can be reviewed and reverted independently

Conversely, combine a single unit of meaning spanning multiple files into one commit (do not split mechanically per file).

Stacking multiple `fixup!` commits on the same owning commit is fine, since autosquash applies them in order. Follow A-2 for the creation procedure.

Method B absorbs changes directly into the target commit, leaving no intermediate commits, so this granularity splitting matters little. However, apply changes whose result depends on order in stages, as with method A.

### 5. Choose the method

Priority order:

1. **If a `--method=A` / `--method=B` argument was passed, follow it** (if the prerequisites are not met, stop as described in "Arguments")
2. If the user explicitly names a method ("with git history fixup", "just stack a fixup commit", etc.), follow it
3. If neither applies, **choose method A (stack a fixup commit) by default without asking**. Method A does not rewrite history, so it is easy to undo, and the content can be reviewed before consolidating with [[autosquash]]

When the `--autosquash` argument is passed, proceed with method A (see "Arguments").

Report the chosen method to the user in one line before executing (do not wait for approval). Present the following to the user in Japanese (pick one): `"fixup方法としてA（fixupコミットを積む）を使います。承認待ちなしで続行します。"` / `"fixup方法としてB（git history fixupで履歴を直接書き換え）を使います。承認待ちなしで続行します。"`

### 6. Present the fixup plan to the user

Report which change goes into which commit. Do not block for approval; proceed to the next step right after presenting. Change the trailing note by method. Present the following plan template to the user in Japanese (fill in SHAs, titles, and files):

```
以下の内容で fixup します（方法: A / fixupコミットを積む）:

[1] fixup -> <sha1> feat: add user model（コメント1: バリデーション追加）
    - src/models/user.ts（すべての変更）
    - src/models/user.test.ts（すべての変更）

[2] fixup -> <sha1> feat: add user model（コメント2: 型名の修正）
    - src/models/types.ts（すべての変更）

[3] fixup -> <sha2> fix: handle empty payload
    - src/api/handler.ts のハンク @@ -42,7 +42,10 @@ のみ

base: origin/<BASE>（起点: <MB> = ブランチの分岐点コミット）
履歴の統合には別途 autosquash の実行が必要です。
```

With `--autosquash`, present the following trailing lines to the user in Japanese instead:

```
base: origin/<BASE>（起点: <MB> = ブランチの分岐点コミット）
fixupコミットを積んだ後、そのまま autosquash で履歴を統合します（SHAが変わるため force push が必要になります）。
```

With method B, present the following trailing lines to the user in Japanese instead:

```
方法: B / git history fixup（履歴を直接書き換え）
- 対象コミットより後の子孫コミットはSHAが変わります
- 書き換え前にバックアップブランチを作成します
- 完了後は force push（--force-with-lease）が必要になります
```

### 7-A. Method A: create the fixup commits

#### A-1. Fixing up all changes into a single commit

If the target changes are already staged, simply run:

```bash
git commit --fixup=<TARGET_SHA>
```

To include unstaged portions, stage them first and then run:

```bash
git add <FILES...>
git commit --fixup=<TARGET_SHA>
```

Do not use `git add -A` / `git add .`; specify only the needed files explicitly (to avoid sweeping in unrelated untracked files).

#### A-2. Creating multiple separate fixup commits

This covers both the case of multiple owning commits and the case of splitting multiple `fixup!` commits for the same owning commit per 4-4. Repeat the following for each fixup commit:

1. Clear the current index once: `git reset` (working tree stays as-is)
2. Stage only the changes included in commit [n]
   - Whole file: `git add <FILE>`
   - Per hunk: interactive `git add -p` is not available, so write out the patch, keep only the needed hunks, and apply it to the index:
     ```bash
     git diff -U3 <FILE> > <SCRATCH>/fixup-N.patch
     # Edit <SCRATCH>/fixup-N.patch, keeping only the hunks for this commit
     git apply --cached --check <SCRATCH>/fixup-N.patch   # verify applicability first
     git apply --cached <SCRATCH>/fixup-N.patch
     ```
     When editing the patch, match the hunk headers (`@@ -a,b +c,d @@`) to the actual kept hunks. If manual line counting is tedious, use `git apply --cached --recount` to recalculate the counts.
     After applying, always verify with `git diff --cached` that the staged content matches the intended hunks. If it drifted, `git reset` and retry.
3. Run `git commit --fixup=<TARGET_SHA_n>`
4. Move on to the next fixup commit

At each step, check `git status --short` and verify no unexpected files slipped in.

### 7-B. Method B: rewrite history with `git history fixup`

`git history fixup <commit>` absorbs **changes staged in the index** directly into the target commit and replays descendant commits. Commit messages and authors are preserved.

#### B-1. Take a backup

Always create a backup branch before rewriting.

```bash
git rev-parse HEAD
git branch backup/fixup-$(date +%Y%m%d-%H%M%S)
```

Tell the user the created branch name and the original HEAD SHA. Present the following to the user in Japanese (fill in names): `"バックアップブランチ <BRANCH> を作成しました。元のHEADは <ORIGINAL_SHA> です。"`

#### B-2. Decide the application order

When fixing up into multiple commits, process them **from newest to oldest (from the HEAD side toward the base side)**. Descendant commits are replayed and change SHAs, but ancestor commit SHAs stay unchanged, so later target SHAs remain valid.

#### B-3. Apply per target

Repeat the following for each target commit:

1. Clear the index: `git reset` (working tree stays as-is)
2. Stage only the changes to absorb into that commit (same constraints as method A step A-2. Do not use `git add -A` / `git add .`. For per-hunk staging, route the patch through `git apply --cached`)
3. Verify the staged content with `git status --short`
4. Check the result with a dry run:
   ```bash
   git history fixup --dry-run --empty=abort --update-refs=head <TARGET_SHA>
   ```
   `--dry-run` updates no refs and only prints the refs it would update. If it errors, stop here and present the following to the user in Japanese (fill in the cause): `"dry-runでエラーになりました（原因: <CAUSE>）。ここで中断します。"`
5. Run it for real:
   ```bash
   git history fixup --empty=abort --update-refs=head <TARGET_SHA>
   ```
6. Move on to the next target

#### B-4. Handling the options

- Attach `--empty=abort` by default. It prevents a target or descendant commit that becomes empty after the fixup from silently disappearing. On abort, present the following to the user in Japanese and confirm whether to use `--empty=drop` (the command default) if dropping it is really intended: `"対象または子孫コミットが空になるため中断しました。本当に破棄する場合は --empty=drop を使いますか？"`
- Attach `--update-refs=head` by default. The default `--update-refs=branches` would rewrite **all local branches** descending from the target commit (including the backup branch created in B-1). The backup must keep pointing at the pre-rewrite SHA, so never use `branches`; always specify `head`. Only use `--update-refs=branches` after confirming with the user when there is a clear intent to rewrite other local branches too.
- Do not use `--reedit-message`. To change a message, separately suggest `git history reword`.

#### B-5. On failure

When `git history fixup` hits a conflict it aborts and history is left unchanged. In that case:

- Consider that the owning-commit inference may be wrong, re-examine the candidates, and re-present them to the user. Present the following to the user in Japanese (fill in candidates): `"fixup先の推定が間違っている可能性があります。候補を見直しました: <CANDIDATES>。"`
- If the change simply cannot be absorbed, present the following to the user in Japanese to offer switching to method A (`git commit --fixup`) or making a regular commit: `"この変更は直接取り込めません。方法A（fixupコミットを積む）か通常のコミットに切り替えますか？"`
- **Do not silently re-fixup into a different commit.** Re-examine the candidates and re-present them to the user. Present the following to the user in Japanese: `"別のコミットへの付け替えは独断で行いません。候補を確認してください。"`

If you judge history to be broken, do not attempt recovery yourself; present the B-1 backup branch name and the original HEAD SHA and explain the recovery (`git reset --hard <ORIGINAL_SHA>`). Present the following to the user in Japanese (fill in names): `"履歴が壊れた可能性があります。自分では復旧せず、バックアップブランチ <BRANCH> と元のHEAD <ORIGINAL_SHA> から git reset --hard <ORIGINAL_SHA> で復旧できます。"`

### 8. Verify the result

```bash
git log --oneline <MB>..HEAD
git status --short
```

For method A:

- The expected number of `fixup!` commits is stacked
- The working tree is clean (no leftover uncommitted changes) (leftovers should have been agreed with the user in advance)

For method B:

- No `fixup!` commits are stacked (they should be absorbed into history)
- The commit count matches the backup point (it should not have shrunk, since `--empty=abort` is attached)
- The intended changes are in the target commit: `git show --stat <new SHA>`
- The backup branch and the working tree contents match:
  ```bash
  git diff <BACKUP_BRANCH> HEAD
  ```
  The expectation is that only the fixuped changes show up as the diff. If there is any other diff, present the following to the user in Japanese (fill in the diff summary) and **do not fix it yourself**: `"想定外の差分があります: <DIFF>。こちらでは修正しませんので確認してください。"`

### 9. Completion report

For method A, present the following report template to the user in Japanese (fill in commits):

```
作成したfixupコミット:
- <sha> fixup! <original commit title>

履歴の統合には autosquash スキルが必要です（--autosquash 指定時はステップ10に続くため不要です）。
pushはご自身でお願いします（このスキルではpushしません。autosquash後は force push が必要になります）。
```

For method B, present the following report template to the user in Japanese (fill in log, branch, SHA):

```
書き換え後の履歴（git log --oneline <MB>..HEAD）:
<LOG>

バックアップブランチ: <BRANCH>（元のHEAD: <ORIGINAL_SHA>）
SHAが変わったため、pushには git push --force-with-lease が必要です。pushはご自身でお願いします（このスキルではpushしません）。
問題なければバックアップブランチはご自身で削除できます。
```

### 10. With `--autosquash`: continue with autosquash

Run only when `--autosquash` was passed. After the step 8 check passes and the working tree has no unexpected leftovers, launch the [[autosquash]] skill to consolidate history. Hand over the base determined in step 2 to the autosquash side so it does not re-determine the base.

If autosquash fails midway (conflicts, etc.), follow the failure procedure on the autosquash skill side. **The fixup commits are already created, so do not revert them on your own.** Present the following to the user in Japanese: `"autosquashで失敗しましたが、fixupコミットは作成済みのため戻しません。autosquash側の失敗手順に従ってください。"`

After completion, present the following report template to the user in Japanese (fill in log). **This skill does not push.**

```
autosquash後の履歴（git log --oneline <MB>..HEAD）:
<LOG>

SHAが変わったため force push が必要になります。pushはご自身でお願いします（このスキルではpushしません）。
```

## Notes

- **Do not run on a protected branch.** Stop if the current branch is `main` / `master` / `develop` or similar.
- **Do not fixup into commits older than the base.** The range outside <MB>..HEAD is other people's history, so leave it alone. For changes whose only owning commit is outside the range, suggest making a regular commit to the user.
- **Do not fixup into existing `fixup!` / `squash!` commits.** They are themselves tied to an original commit, so double fixup only causes confusion.
- **Always verify staged content after splitting per hunk.** Splitting via patch can sweep in the wrong hunk, so confirm with `git diff --cached` that only the intended hunks are staged before committing.
- **Do not use `git add -A` / `git add .`.** Always specify files explicitly (prevents accidental commits of files like `.env`).
- **Do not force-push.** Pushing after autosquash / history rewrite is the user's responsibility.
- **Method B rewrites history destructively.** Always create a backup branch before running, and confirm with `--dry-run`. It cannot be used on history containing merge commits, so stop and ask the user whether to switch to method A when `git log --merges <MB>..HEAD` returns hits (see Arguments).
- **Method B uses `--update-refs=head` by default.** With the default `--update-refs=branches`, the backup branch created in B-1 points at the same SHA as the target commit, so the backup itself would be rewritten and recovery would become impossible. Always specify `--update-refs=head` to protect the backup.
- **With method A, split fixup commits by unit of meaning even for the same owning commit.** One commit per review comment (see 4-4).
- For changes whose owner is genuinely unknown, always leave the "make a new commit" option open. Do not force them into an existing commit.
