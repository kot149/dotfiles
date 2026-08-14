---
name: split-commit
description: 既存の 1 つのコミットを、論理単位ごとに複数のコミットへ分割するスキル。ユーザーが「このコミットを分割して」「commit を分けて」「1つのコミットを整理して分けたい」「split commit」などと依頼した場合に使用する。必ず作業前にバックアップブランチを作成し、分割後にバックアップとの tree 差分が無いことを検証する。差分がある場合は必ずユーザーに報告し、勝手に修正しない。
---

# split-commit

`origin/<BASE>..HEAD` の範囲内にある既存コミットを、論理単位ごとに複数コミットへ分割するスキル。

破壊的な履歴書き換え (interactive rebase の `edit`) を伴うため、**必ずバックアップブランチを作成**してから作業し、**分割後にバックアップと最終ツリーが一致することを検証**する。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること
- `gh` CLI が使用可能で認証済みであること (base ブランチ特定のため)
- 現在ブランチが保護ブランチ (`main` / `master` / `develop` など) でないこと
- 未コミット変更が無いこと (ある場合は事前にユーザーと処理方針を合意する)

## 手順

### 1. 状態を確認する

以下を並列で実行:

- `git status --short` — 未コミット変更が無いことを確認
- `git rev-parse --abbrev-ref HEAD` — 現在ブランチ名
- `git log --oneline -30` — 直近の履歴

未コミット変更がある場合は中断してユーザーに確認する。**勝手に stash しない。**

保護ブランチ上では中断する。

### 2. base ブランチを確定する

```bash
gh pr view --json baseRefName,headRefName,number,title,url
```

- PR がある場合は `baseRefName` を採用
- PR が無い場合は `AskUserQuestion` で確認 (候補: `main` / `master` / `develop`)

以降 `<BASE>` とする。

```bash
git fetch origin <BASE>
```

### 3. 分割対象のコミットを確定する

```bash
git log --oneline origin/<BASE>..HEAD
```

このリストから、ユーザーが指定したコミット (または AI が候補提示してユーザーが選んだコミット) を分割対象とする。**対象は `origin/<BASE>..HEAD` の範囲内でなければならない。** 範囲外は他人の履歴なので触らない。

対象コミットの詳細を確認:

```bash
git show --stat <TARGET_SHA>
git show <TARGET_SHA>
```

差分の中身を読み、どういう論理単位に分けられそうか AI が提案する。例:

```
コミット <sha> "feat: add user API" は以下の論理単位に分割できそうです:
[A] src/models/user.ts (モデル定義)
[B] src/api/user.ts + src/api/user.test.ts (API 実装 + テスト)
[C] docs/user-api.md (ドキュメント)

上記の分け方で分割しますか? 別の分け方を希望する場合は指示してください。
```

**ユーザー承認を得るまで作業を開始しない。**

### 4. バックアップブランチを作成する (必須)

分割対象コミットに触る前に、**必ず**バックアップブランチを作成する。ブランチ名にはタイムスタンプを含める:

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_BRANCH="backup/${CURRENT_BRANCH}-split-${TIMESTAMP}"
git branch "${BACKUP_BRANCH}"
```

作成後、`git branch --list "${BACKUP_BRANCH}"` で存在確認をしてからでないと次に進まない。バックアップの HEAD SHA (`git rev-parse "${BACKUP_BRANCH}"`) をメモしておき、後の検証で使う。

バックアップブランチ名をユーザーに提示する。

### 5. interactive rebase で対象コミットを `edit` にする

対象コミット `<TARGET_SHA>` の 1つ前を base に指定して、非対話でその 1 コミットだけを `edit` に書き換える:

```bash
GIT_SEQUENCE_EDITOR="sed -i.bak 's/^pick <SHORT_SHA>/edit <SHORT_SHA>/'" \
  git rebase -i <TARGET_SHA>^
```

- macOS の `sed` は `-i` に空文字を渡せないので `-i.bak` を使い、後で `.bak` を無視する
- `<SHORT_SHA>` は `git log --oneline` で表示される短縮 SHA (通常 7 文字)
- 複数コミットを分割する場合は、`sed` 式を複数指定するか、対象コミットの中で一番古いものを base に指定する

rebase が `edit` 状態で停止したら次へ進む。

### 6. 対象コミットの変更をワーキングツリーに戻す

```bash
git reset HEAD^
```

これで対象コミットの変更が unstaged 状態でワーキングツリーに残る。`git status` で想定の変更が展開されていることを確認する。

### 7. 論理単位ごとに commit を積み直す

Step 3 でユーザーと合意した分割案に沿って、単位ごとに:

```bash
git add <FILES_FOR_UNIT_A...>
git commit -m "<新しいコミットメッセージ A>"
```

を繰り返す。

- **`git add -A` / `git add .` は使わない。** 常にファイルを明示指定する
- ファイル内の hunk 単位で分ける必要がある場合は、対話式 `git add -p` を **ユーザーに手動実行してもらう** よう案内する (AI が自動化しない)
- コミットメッセージは元のメッセージや PR 文脈から妥当なものを AI が下書きし、ユーザー承認を得てから使う
- 各コミット後に `git status --short` で残差を確認する

全ての変更をコミットし終えたら、`git status --short` がクリーンであることを確認する。**残った変更を勝手に握りつぶさない。** 想定外の残差があればユーザーに報告する。

### 8. rebase を継続する

```bash
git rebase --continue
```

- 後続コミットとコンフリクトが発生した場合は **`--abort` せず** ユーザーに報告し、対処方針 (手動解決 / abort) を確認する
- rebase 完了まで進める

### 9. バックアップとの差分検証 (必須)

分割後の HEAD と、バックアップブランチのツリーが**完全に一致**することを検証する。これがこのスキルの本丸。

```bash
git diff "${BACKUP_BRANCH}" HEAD
git diff "${BACKUP_BRANCH}" HEAD --stat
```

- 出力が空であれば OK (ツリーが同一 = 分割前後で最終成果物が変わっていない)
- 出力に何か含まれていれば **NG**。分割中にコード内容が変わってしまっている

追加で tree ハッシュを比較して二重確認:

```bash
BACKUP_TREE=$(git rev-parse "${BACKUP_BRANCH}^{tree}")
HEAD_TREE=$(git rev-parse "HEAD^{tree}")
[ "${BACKUP_TREE}" = "${HEAD_TREE}" ] && echo "TREE_MATCH" || echo "TREE_MISMATCH"
```

- `TREE_MATCH` であれば分割成功
- `TREE_MISMATCH` の場合は **ユーザーに即報告し、リカバリ方針を確認する**。自己判断で `git reset --hard "${BACKUP_BRANCH}"` などの破壊的操作をしない (ユーザーが承認すれば実行してよい)

### 10. 結果報告

以下をユーザーに伝える:

- バックアップブランチ名 (`${BACKUP_BRANCH}`) と、そのまま残す旨 (削除は後日ユーザー判断)
- 分割後の履歴 (`git log --oneline origin/<BASE>..HEAD` の抜粋)
- ツリー差分検証の結果 (MATCH / MISMATCH)
- force push が必要な旨、および **AI は force push しない** こと (`git push --force-with-lease origin HEAD` はユーザーが実行)

### 11. バックアップブランチの後始末

削除は AI 側で自動的に行わない。ユーザーが force push 後、動作確認を経て問題がなければ手動削除する運用を案内する:

```bash
git branch -D "${BACKUP_BRANCH}"
```

## 注意事項

- **バックアップブランチ作成は省略しない。** Step 4 を飛ばして Step 5 以降に進むことは絶対にしない
- **ツリー差分検証は省略しない。** Step 9 の `TREE_MATCH` を確認せずに完了報告しない
- **保護ブランチ上では実行しない**
- **`origin/<BASE>` より前のコミットは分割しない**
- **コンフリクト時に勝手に `--abort` / `--skip` しない。** ユーザー判断を仰ぐ
- **hunk 単位の複雑な分割は AI が自動化しない。** ユーザーに `git add -p` を委ねる
- **`git add -A` / `git add .` は使わない**
- **force push はしない。** ユーザーの責務
- コミットメッセージは元コミットの文脈を活かしつつ、分割後の粒度に合わせて書き直す。ユーザー承認を得る
- 分割対象が複数ある場合、1 コミットずつ順に処理する (Step 3〜9 を対象ごとに繰り返す) ほうが安全。まとめて `edit` にすると事故のリカバリが難しい
- 完了後に履歴を整理したい場合は [[autosquash]] スキルとは無関係 (autosquash は fixup!/squash! 前提)。追加で並べ替えたい場合はユーザーに interactive rebase を委ねる
