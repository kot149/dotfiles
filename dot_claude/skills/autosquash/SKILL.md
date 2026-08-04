---
name: autosquash
description: 現在のブランチの fixup! / squash! コミットを `git rebase -i --autosquash` でまとめるスキル。ユーザーが「autosquashして」「fixupコミットをまとめて」「rebase --autosquashして」などと依頼した場合に使用する。マージ先ブランチは必ず `gh pr view` で対象PRの base ブランチを取得して確定させる。
---

# autosquash

現在のブランチに積まれている `fixup!` / `squash!` コミットを、対応する元コミットへ `git rebase -i --autosquash` でまとめるスキル。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること。
- `gh` CLI が使用可能で認証済みであること。
- 作業ブランチが GitHub にプッシュ済みで、対応する PR が存在する場合はそこから base を決定する。

## 手順

### 1. 状態を確認する

以下を並列で実行し、現状を把握する:

- `git status --short` — 未コミット変更がないか確認 (あれば中断してユーザーに相談)
- `git rev-parse --abbrev-ref HEAD` — 現在のブランチ名
- `git log --oneline -30` — 直近のコミット履歴 (fixup!/squash! が何個あるか)

未コミット変更がある場合は、`git stash` するか事前にコミットするかをユーザーに確認する。勝手に stash しない。

### 2. マージ先ブランチ (base) を確定する

**必ず PR 情報から base ブランチを取得する。** 推測しない。

```bash
gh pr view --json baseRefName,headRefName,number,title,url
```

- 現在のブランチに紐づく PR が存在する場合、その `baseRefName` を採用する。
- PR が見つからない場合 (`no pull requests found` エラー等) は、`AskUserQuestion` で base ブランチを確認する。リポジトリの慣例に応じて `main` / `master` / `develop` など複数候補を提示する。

取得した base ブランチ名を以降 `<BASE>` とする。

### 3. リモートの base を最新化する

```bash
git fetch origin <BASE>
```

### 4. fixup!/squash! コミットの有無を確認する

```bash
git log --oneline origin/<BASE>..HEAD
```

このリスト内に `fixup!` / `squash!` プレフィックスのコミットが存在するかを確認する。1件も無い場合は「autosquash 対象のコミットはありません」と報告して終了する。

### 5. rebase 内容をユーザーに提示して承認を得る

autosquash によってどのコミットがどこにまとめられるかを、`git log` の結果から抜粋してユーザーに提示する。破壊的操作 (履歴書き換え) なので **必ず承認を得てから実行する**。

提示例:
```
以下のコミットを autosquash で以下のようにまとめます:
- <sha> fixup! feat: add X → <sha> feat: add X に統合
- <sha> squash! fix: Y → <sha> fix: Y に統合
base: origin/<BASE>
実行してよろしいですか?
```

### 6. autosquash を実行する

承認後、エディタを開かず非対話で autosquash する:

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<BASE>
```

- `GIT_SEQUENCE_EDITOR=:` により todo リストは編集せずそのまま採用される (autosquash による並び替え・fixup 指定を活かす)。
- コンフリクトが発生した場合は rebase を中断せず状況をユーザーに報告し、`git rebase --abort` するか手動解決するかを確認する。**勝手に `--abort` しない。**

### 7. 結果を確認する

```bash
git log --oneline origin/<BASE>..HEAD
```

fixup!/squash! コミットが消えて、対応する元コミットにまとまっていることを確認する。

### 8. force push はユーザーが行う

autosquash 後はリモートと履歴が乖離するため force push が必要だが、**AI は絶対に force push を実行しない**。ユーザー自身が実行する。

autosquash 完了時にユーザーへ以下を伝えるだけに留める:

- autosquash が完了したこと
- 必要に応じてユーザー自身で `git push --force-with-lease origin HEAD` を実行してほしいこと (`--force-with-lease` を推奨する旨だけ案内)

`git push` 系のコマンドはこのスキル内で実行しない。

## 注意事項

- **`main` / `master` などの保護ブランチ上では絶対に実行しない。** 現在ブランチがこれらの場合は中断してユーザーに確認する (PR の base ではなく、rebase 対象である HEAD 側のブランチをチェックする)。
- **他人が作業している共有ブランチには実行しない。** rebase 対象は自ブランチのみ。
- コンフリクト時に destructive な回復 (`--abort`, `reset --hard`) を勝手に実行しない。
- `--no-verify` などフック無効化フラグは使わない。
