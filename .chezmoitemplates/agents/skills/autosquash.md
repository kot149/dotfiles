---
name: autosquash
description: Fold `fixup!` / `squash!` commits on the current branch into their target commits with `git rebase -i --autosquash`. Use when the user asks to "autosquash", "fold fixup commits", "run rebase --autosquash", 「autosquashして」「fixupコミットをまとめて」「fixupを畳んで」, or any similar phrasing in English or Japanese. Determine the merge-target branch locally from the distance between `origin/HEAD` and merge-base; only use PR info or ask the user to confirm when the evidence is ambiguous.
---

# autosquash

A skill that folds `fixup!` / `squash!` commits stacked on the current branch into their corresponding base commits with `git rebase -i --autosquash`.

## Prerequisites

- The working directory is inside a Git repository.
- The `origin` remote is configured (so the base can be determined locally).

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Procedure

### 1. Check the current state

Run the following in parallel to understand the current state:

- `git status --short` — check for uncommitted changes
- `git rev-parse --abbrev-ref HEAD` — current branch name
- `git log --oneline -30` — recent commit history (how many fixup!/squash! commits exist)

**Never run on protected branches such as `main` / `master`.** If the current branch is one of these, stop and present the following to the user in Japanese (check the branch being rebased, i.e. the HEAD side, not the PR base).

```
現在のブランチ <BRANCH> は保護ブランチのため、このスキルでは実行できません。
```

**Do not run on shared branches others are working on.** Only rebase your own branch. If the branch appears shared, stop and present the following to the user in Japanese.

```
このブランチは他の人も作業している共有ブランチの可能性があります。自分のブランチでのみ実行してください。
```

If there are uncommitted changes, stash them with `git stash push -u` before proceeding. Present the following to the user in Japanese, and restore them with `git stash pop` in step 9.

```
未コミットの変更をスタッシュしました: <stash entry, e.g. stash@{0}>
作業完了後に `git stash pop` で戻します。
```

### 2. Determine the merge-target branch (base) and the start commit

Decide the base branch and the fork point to use as the rebase start. This is decided from local information alone, so `gh` is not required. **Never guess `main`; always determine it with evidence using the procedure below.**

{{ includeTemplate "agents/skills/_shared/git-base.md" . }}

### 3. Check whether fixup!/squash! commits exist

```bash
git log --oneline <MB>..HEAD
```

Check whether this list contains any commits with the `fixup!` / `squash!` prefix. If there are none, present the following to the user in Japanese and finish.

```
autosquash 対象のコミットはありません (fixup! / squash! コミットが見つかりませんでした)。
```

### 4. Present the rebase plan to the user (no approval gate)

Show which commits autosquash will fold where, excerpted from `git log`. Do not block waiting for approval; proceed after presenting the plan (a dedicated recovery ref is saved before execution). Present the plan in Japanese.

Example (present the following to the user in Japanese):
```
以下のコミットを autosquash でまとめます:
- <sha> fixup! feat: add X → <sha> feat: add X に結合
- <sha> squash! fix: Y → <sha> fix: Y に結合
ベース: origin/<BASE> (開始点: <MB> = ブランチの分岐点)
実行前に専用refへ元のHEADを保存するので、結果が想定と異なる場合は復元できます。
```

### 5. Save a recovery ref (mandatory)

Before touching history, save HEAD outside `refs/heads`:

```bash
BACKUP_REF="refs/backup/autosquash/$(date +%Y%m%d-%H%M%S)/head"
ORIGINAL_SHA=$(git rev-parse HEAD)
git update-ref "$BACKUP_REF" "$ORIGINAL_SHA" ""
```

Check each command succeeds and `git rev-parse "$BACKUP_REF"` equals `ORIGINAL_SHA` before continuing. The empty old-value argument prevents overwriting an existing ref; on collision, choose a fresh name. Report the exact ref and original SHA in Japanese:

```
復元用refを保存しました: <BACKUP_REF> (元の HEAD: <SHA>)
```

### 6. Run autosquash

Run autosquash non-interactively without opening an editor:

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <MB>
```

- `GIT_SEQUENCE_EDITOR=:` accepts the todo list as-is without editing (keeping the autosquash reordering and fixup directives).
- The start point must be the merge-base found in 2-5. Do not pass `origin/<BASE>` directly, since that would also pull in updates on the base side.
- On conflict, abort with `git rebase --abort`. The history is back to its original state, so restore anything stashed in step 1 with `git stash pop`. Then present the following to the user in Japanese. Resolve manually only when the user has explicitly instructed so.

```
コンフリクトが発生したため `git rebase --abort` で中断しました。ブランチの履歴は変更されていません。
<IF_STASHED_IN_STEP_1: スタッシュを `git stash pop` で戻しました。>
手動での解決を希望される場合はお知らせください。
```

### 7. Check the result

```bash
git log --oneline <MB>..HEAD
```

Verify that the fixup!/squash! commits are gone and folded into their corresponding base commits.

### 8. Verify against the backup (mandatory)

Autosquash only folds the fixup!/squash! contents into their base commits, so the expectation is that **the final tree exactly matches the backup**. Any mismatch means the contents were altered during the history rewrite.

```bash
git diff "<BACKUP_REF>" HEAD
git diff "<BACKUP_REF>" HEAD --stat
```

In addition to an empty diff, also verify that the tree SHAs match:

```bash
BACKUP_TREE=$(git rev-parse "<BACKUP_REF>^{tree}")
HEAD_TREE=$(git rev-parse HEAD^{tree})
[ "${BACKUP_TREE}" = "${HEAD_TREE}" ] && echo "TREE_MATCH" || echo "TREE_MISMATCH"
```

On `TREE_MISMATCH` or a nonempty diff, report the following in Japanese. Never run `git reset --hard "<BACKUP_REF>"` independently. Report the exact ref and original HEAD SHA and let the user choose recovery. Before any approved reset, preserve current uncommitted / untracked work and appropriately end any in-progress operation. Since history is already rewritten, step 1's stash may conflict on `git stash pop`: leave it intact and report its entry instead.

```
検証結果: ツリー不一致 (TREE_MISMATCH) を検出しました。履歴の書き換え中に内容が変わっている可能性があります。
復元用ref: <BACKUP_REF> (元の HEAD: <SHA>)
<IF_STASHED_IN_STEP_1: スタッシュは <STASH_ENTRY> に残したままです。復元方法と併せてご判断ください。>
復元方法の判断をお知らせください。こちらで勝手に復元は行いません。
```

On `TREE_MATCH` (empty diff and matching tree SHAs), present the following to the user in Japanese.

```
検証結果: ツリー一致 (TREE_MATCH)。最終内容は復元用ref <BACKUP_REF> と同一です。
```

If conflicts were resolved manually, the tree may legitimately differ by the resolution; present that diff to the user in Japanese. Present the following to the user in Japanese, followed by the diff, and check it matches the resolution intent.

```
手動解決による差分は以下の通りです。解決内容と一致しているかご確認ください:
```

### 9. The user performs the force push

After autosquash the history diverges from the remote, so a force push is needed, but **the AI must never run a force push**. The user runs it themselves.

When autosquash completes, first restore anything stashed in step 1 with `git stash pop`, then present the following to the user in Japanese, filling in the bracketed values:

```
autosquash が完了しました。
復元用ref: <BACKUP_REF> (元の HEAD: <SHA>)
復元用refは削除せずに残しています。不要になった場合はご自身の判断で削除してください。
検証結果: <VERIFICATION_RESULT_FROM_STEP_8>
<IF_STASHED_IN_STEP_1: スタッシュを `git stash pop` で戻しました。>
必要であれば、ユーザー自身で `git push --force-with-lease origin HEAD` を実行してください (--force-with-lease を推奨します)。
```

The report must cover only the following points:

- That autosquash is complete
- The recovery ref and original HEAD SHA. Keep the ref until the user explicitly chooses deletion.
- The step 8 verification result (whether the trees match)
- If anything was stashed in step 1, that it has been restored
- Ask them to run `git push --force-with-lease origin HEAD` themselves if needed (only mention that `--force-with-lease` is recommended)

Do not run any `git push` commands inside this skill.

List checkpoints with `git for-each-ref --format='%(refname) %(objectname:short)' refs/backup/autosquash/`. After preserving current work and appropriately ending any in-progress operation, approved recovery uses `git reset --hard "<BACKUP_REF>"`; account separately for any stash from step 1. Delete only the chosen checkpoint with `git update-ref -d "<BACKUP_REF>"` when the user explicitly decides it is no longer needed.

## Notes

- **Always save a dedicated recovery ref before rewriting history.** Never start the rebase before saving and verifying it.
- **After execution, always verify the tree matches the backup.** On mismatch, only report it; do not fix or recover on your own.
- **On any path that ends without completing the rebase, account for the stash from step 1.** On a clean abort, pop it. After the history was already rewritten, leave it and report the entry name.
- Do not run destructive recovery beyond the step 6 `git rebase --abort` on your own judgment (no `reset --hard`, no retry with different options).
- Do not use hook-disabling flags such as `--no-verify`.
- **Incorporating the base (putting new base-side commits onto HEAD) is out of scope for this skill.** Always pin the start to the merge-base, and cause no history changes other than folding the fixups.
