---
name: autosquash
description: 現在のブランチの fixup! / squash! コミットを `git rebase -i --autosquash` でまとめるスキル。ユーザーが「autosquashして」「fixupコミットをまとめて」「rebase --autosquashして」などと依頼した場合に使用する。マージ先ブランチは `origin/HEAD` と merge-base の距離からローカルで特定し、判断が割れる場合のみ PR 情報やユーザーへの確認で確定させる。
---

# autosquash

現在のブランチに積まれている `fixup!` / `squash!` コミットを、対応する元コミットへ `git rebase -i --autosquash` でまとめるスキル。

## ユーザーへの選択提示

このドキュメントで「選択提示」と書いてある箇所は、選択肢を提示してユーザーに選ばせることを指す。選択UIツール (`AskUserQuestion` など) が使える agent ではそれを使い、無い agent では同じ選択肢を番号付きリストのプレーンテキストで提示し、番号または自由記述で答えてもらう。どちらの場合も回答を得るまで次の手順へ進まない。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること。
- `origin` リモートが設定されていること (base をローカルで特定するため)。

## 手順

### 1. 状態を確認する

以下を並列で実行し、現状を把握する:

- `git status --short` — 未コミット変更がないか確認 (あれば中断してユーザーに相談)
- `git rev-parse --abbrev-ref HEAD` — 現在のブランチ名
- `git log --oneline -30` — 直近のコミット履歴 (fixup!/squash! が何個あるか)

未コミット変更がある場合は、`git stash` するか事前にコミットするかをユーザーに確認する。勝手に stash しない。

### 2. マージ先ブランチ (base) と起点コミットを確定する

rebase の起点にするため base ブランチと分岐点を決める。ローカルの情報だけで決まるので `gh` は必須にしない。**当てずっぽうで `main` を使わず、必ず下記の手順で根拠を持って決める。**

{{ includeTemplate "agents/skills/_shared/git-base.md" . }}

### 3. fixup!/squash! コミットの有無を確認する

```bash
git log --oneline <MB>..HEAD
```

このリスト内に `fixup!` / `squash!` プレフィックスのコミットが存在するかを確認する。1件も無い場合は「autosquash 対象のコミットはありません」と報告して終了する。

### 4. rebase 内容をユーザーに提示して承認を得る

autosquash によってどのコミットがどこにまとめられるかを、`git log` の結果から抜粋してユーザーに提示する。破壊的操作 (履歴書き換え) なので **必ず承認を得てから実行する**。

提示例:
```
以下のコミットを autosquash で以下のようにまとめます:
- <sha> fixup! feat: add X → <sha> feat: add X に統合
- <sha> squash! fix: Y → <sha> fix: Y に統合
base: origin/<BASE> (起点: <MB> = ブランチ分岐時点のコミット)
実行してよろしいですか?
```

### 5. autosquash を実行する

承認後、エディタを開かず非対話で autosquash する:

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "$MB"
```

- `GIT_SEQUENCE_EDITOR=:` により todo リストは編集せずそのまま採用される (autosquash による並び替え・fixup 指定を活かす)。
- 起点は 2-5 で求めた merge-base であること。`origin/<BASE>` を直接渡すと base 側の更新まで取り込まれてしまうので使わない。
- コンフリクトが発生した場合は rebase を中断せず状況をユーザーに報告し、`git rebase --abort` するか手動解決するかを確認する。**勝手に `--abort` しない。**

### 6. 結果を確認する

```bash
git log --oneline <MB>..HEAD
```

fixup!/squash! コミットが消えて、対応する元コミットにまとまっていることを確認する。

### 7. force push はユーザーが行う

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
- **base の取り込み (base 側の新しいコミットを HEAD に載せること) はこのスキルでは行わない。** 起点は常に merge-base に固定し、fixup の折りたたみ以外の履歴変化を起こさない。
