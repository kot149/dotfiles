---
name: autosquash
description: 現在のブランチの fixup! / squash! コミットを `git rebase -i --autosquash` でまとめるスキル。ユーザーが「autosquashして」「fixupコミットをまとめて」「rebase --autosquashして」などと依頼した場合に使用する。マージ先ブランチは `origin/HEAD` と merge-base の距離からローカルで特定し、判断が割れる場合のみ PR 情報やユーザーへの確認で確定させる。
---

# autosquash

現在のブランチに積まれている `fixup!` / `squash!` コミットを、対応する元コミットへ `git rebase -i --autosquash` でまとめるスキル。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること。
- `origin` リモートが設定されていること (base をローカルで特定するため)。

## 手順

### 1. 状態を確認する

以下を並列で実行し、現状を把握する:

- `git status --short` — 未コミット変更がないか確認
- `git rev-parse --abbrev-ref HEAD` — 現在のブランチ名
- `git log --oneline -30` — 直近のコミット履歴 (fixup!/squash! が何個あるか)

未コミット変更がある場合は `git stash push -u` で退避してから進める。退避したことをユーザーに報告し、手順9で `git stash pop` して復元する。

### 2. マージ先ブランチ (base) と起点コミットを確定する

rebase の起点にするため base ブランチと分岐点を決める。ローカルの情報だけで決まるので `gh` は必須にしない。**当てずっぽうで `main` を使わず、必ず下記の手順で根拠を持って決める。**

{{ includeTemplate "agents/skills/_shared/git-base.md" . }}

### 3. fixup!/squash! コミットの有無を確認する

```bash
git log --oneline <MB>..HEAD
```

このリスト内に `fixup!` / `squash!` プレフィックスのコミットが存在するかを確認する。1件も無い場合は「autosquash 対象のコミットはありません」と報告して終了する。

### 4. rebase 内容をユーザーに提示して承認を得る

autosquash によってどのコミットがどこにまとめられるかを、`git log` の結果から抜粋してユーザーに提示する。承認待ちで止まらず、提示後そのまま次の手順に進む (バックアップブランチを作ってから実行するので、想定と違えばそこから復旧できる)。

提示例:
```
以下のコミットを autosquash で以下のようにまとめます:
- <sha> fixup! feat: add X → <sha> feat: add X に統合
- <sha> squash! fix: Y → <sha> fix: Y に統合
base: origin/<BASE> (起点: <MB> = ブランチ分岐時点のコミット)
```

### 5. バックアップブランチを作成する (必須)

履歴に触る前に、**必ず**バックアップブランチを作成する。

```bash
git branch "backup/$(git rev-parse --abbrev-ref HEAD)-autosquash-$(date +%Y%m%d-%H%M%S)"
```

作成したブランチ名 (`<BACKUP_BRANCH>`) と現在の HEAD SHA を控え、`git branch --list "<BACKUP_BRANCH>"` で存在確認が取れてから次に進む。ブランチ名はユーザーにも提示する。

### 6. autosquash を実行する

承認後、エディタを開かず非対話で autosquash する:

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "$MB"
```

- `GIT_SEQUENCE_EDITOR=:` により todo リストは編集せずそのまま採用される (autosquash による並び替え・fixup 指定を活かす)。
- 起点は 2-5 で求めた merge-base であること。`origin/<BASE>` を直接渡すと base 側の更新まで取り込まれてしまうので使わない。
- コンフリクトが発生した場合は `git rebase --abort` して中断し、状況をユーザーに報告する。手動解決はユーザーから明示的な指示があった場合のみ行う。

### 7. 結果を確認する

```bash
git log --oneline <MB>..HEAD
```

fixup!/squash! コミットが消えて、対応する元コミットにまとまっていることを確認する。

### 8. バックアップとの差分検証 (必須)

autosquash は fixup!/squash! の内容を元コミットへ折りたたむだけなので、**最終ツリーはバックアップと完全に一致する**のが期待値。一致しないなら履歴操作の途中で内容が変質している。

```bash
git diff "<BACKUP_BRANCH>" HEAD
git diff "<BACKUP_BRANCH>" HEAD --stat
```

差分が空であることに加えて、tree SHA の一致も確認する:

```bash
BACKUP_TREE=$(git rev-parse "<BACKUP_BRANCH>^{tree}")
HEAD_TREE=$(git rev-parse HEAD^{tree})
[ "${BACKUP_TREE}" = "${HEAD_TREE}" ] && echo "TREE_MATCH" || echo "TREE_MISMATCH"
```

`TREE_MISMATCH` の場合、または `git diff` に差分が出た場合は **ユーザーに報告する**。自己判断で `git reset --hard "<BACKUP_BRANCH>"` などの破壊的な復旧は行わない。復旧に必要なバックアップブランチ名と元の HEAD SHA を添えて報告し、対応はユーザーの判断に委ねる。

コンフリクトを手動解決した場合は解決内容の分だけツリーが変わりうるので、その差分が解決意図と一致するかをユーザーに提示する。

### 9. force push はユーザーが行う

autosquash 後はリモートと履歴が乖離するため force push が必要だが、**AI は絶対に force push を実行しない**。ユーザー自身が実行する。

autosquash 完了時にユーザーへ以下を伝えるだけに留める:

- autosquash が完了したこと
- バックアップブランチ名と元の HEAD SHA (復旧用)。削除は後日ユーザー判断とし、勝手に削除しない
- 手順8の検証結果 (ツリー一致の有無)
- 手順1で stash した場合は復元済みであること
- 必要に応じてユーザー自身で `git push --force-with-lease origin HEAD` を実行してほしいこと (`--force-with-lease` を推奨する旨だけ案内)

`git push` 系のコマンドはこのスキル内で実行しない。

## 注意事項

- **`main` / `master` などの保護ブランチ上では絶対に実行しない。** 現在ブランチがこれらの場合は中断し、理由をユーザーに報告する (PR の base ではなく、rebase 対象である HEAD 側のブランチをチェックする)。
- **他人が作業している共有ブランチには実行しない。** rebase 対象は自ブランチのみ。
- **履歴を破壊的に書き換えるので、実行前に必ずバックアップブランチを作る。** 作成前に rebase を始めない。
- **実行後は必ずバックアップとの tree 一致を検証する。** 不一致は報告のみに留め、勝手に修正・復旧しない。
- コンフリクト時に destructive な回復 (`--abort`, `reset --hard`) を勝手に実行しない。
- `--no-verify` などフック無効化フラグは使わない。
- **base の取り込み (base 側の新しいコミットを HEAD に載せること) はこのスキルでは行わない。** 起点は常に merge-base に固定し、fixup の折りたたみ以外の履歴変化を起こさない。
