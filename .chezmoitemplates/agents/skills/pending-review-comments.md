---
name: pending-review-comments
description: レビュー指摘をGitHub PRのインラインコメントとしてpending状態（ユーザーがSubmitするまで他人に見えない下書きレビュー）で投稿する。ユーザーが「pendingでレビューコメントを投稿して」「レビュー指摘をPRにインラインで下書き投稿して」「post pending review comments」「まだ公開せずにコメントだけ付けて」などと依頼した場合、または他のレビュー作業の結果をPRへ書き込む段階で使用する。Submit（レビューの公開）は絶対に行わず、必ずユーザーの手作業に委ねる。
---

# Pending Review Comments

レビュー指摘を GitHub PR の **pending レビュー**（下書き）としてインライン投稿する。
pending レビューは作成者本人にしか見えず、ユーザーが GitHub UI で Submit するまで他の人には公開されない。

## Input

$ARGUMENTS

指摘の入力元は次のいずれか:

- 直前までの会話にあるレビュー結果（`/deep-review`、`/code-review`、Codex レビュー、自前のレビューなど）
- `$ARGUMENTS` で渡されたファイルパスやテキスト
- ユーザーが本文中に列挙した指摘

各指摘は最低限 **ファイルパス・行・指摘本文** が必要。行が特定できない指摘は投稿せず、後述のとおりユーザーへ報告する。

## 絶対厳守ルール

- **必ず pending 状態で作成する**。reviews API への POST で `event` フィールドを **一切含めない**。`event` を省略した場合のみレビューは PENDING で作成される。`event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` の指定は禁止
- **Submit 系の操作を行わない**: `gh pr review --comment/--approve/--request-changes`、`POST .../reviews/{id}/events` は使用禁止。Submit はユーザーが手動で行う
- **全指摘をインラインコメントにする**: 各指摘は `comments` 配列の要素として `path` + `line` を指定し該当行にアンカーする。レビュー body は空文字にし、body に指摘やサマリーを書かない
- **既存の pending レビューを勝手に消さない**: 破棄はユーザーの明示的な承認を得てから
- **指摘の内容を勝手に足さない**: 入力にない指摘を創作しない。逆に、投稿できなかったものは必ず報告する

## 手順

### 1. 対象PRの特定

```sh
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr view --json number,state,headRefName --jq '{number,state,headRefName}'
```

`$ARGUMENTS` に PR 番号や URL があればそれを優先する。現在のブランチに PR が無く、番号も指定されていない場合は、その旨を伝えて終了する（勝手に PR を作らない）。

### 2. 既存 pending レビューの確認

```sh
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[] | select(.state=="PENDING")] | {count: length, ids: [.[].id]}'
```

GitHub は 1 ユーザーにつき 1 PR あたり 1 件しか pending レビューを持てない。既に存在する場合は投稿せずユーザーに選択を求める:

- 既存 pending を GitHub 上で Submit してもらってから再実行する
- 既存 pending を破棄する（承認を得たうえで `gh api -X DELETE repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}`）
- 今回の投稿を中止する

Claude Code では `AskUserQuestion` で選択を受け付ける。同ツールが無い環境では選択肢を平文で提示して回答を待つ。

### 3. アンカー行の検証

```sh
gh pr diff {number}
```

diff と各指摘の行を突き合わせて確認する:

- 追加/変更行への指摘: `side: "RIGHT"`、`line` は **変更後** ファイルの行番号
- 削除行への指摘: `side: "LEFT"`、`line` は **変更前** ファイルの行番号
- 複数行にまたがる指摘: `start_line` + `line`（`start_side` / `side` も揃える）
- 行が diff の範囲外の場合: 同じファイル内で、その指摘に最も関連する **diff 内の行** にアンカーし直す
- 適切な行が見つからない指摘: インライン投稿せず「diff 外のため投稿不可」として保留リストに入れ、最後にユーザーへ内容ごと報告する

パスは **リポジトリルートからの相対パス** で、diff に現れるものと完全一致させる。

### 4. コメント本文の生成

1指摘につき1コメント。1コメントに複数の指摘を詰め込まない。

```
**[<カテゴリ> / <重要度>] <指摘タイトル>**

<何が問題か（1〜3行）>

**提案:** <どう直すか>
```

- カテゴリ・重要度が入力に無ければラベル行は省いてタイトルだけにする
- `[deep-review]` `[Claude]` のような生成ツール名のラベルは付けない
- 修正コードを示す場合は GitHub の suggestion ブロックを使ってよい:

  ````
  ```suggestion
  <置き換え後の行>
  ```
  ````

  suggestion は `line` で指定した行（範囲指定なら `start_line`〜`line`）を丸ごと置き換えるので、行数と内容を diff と厳密に一致させること。

### 5. 投稿

ペイロードをファイルに書き出して POST する（`event` は含めない）:

```json
{
  "body": "",
  "comments": [
    {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "..."},
    {"path": "src/bar.ts", "start_line": 10, "line": 15, "start_side": "RIGHT", "side": "RIGHT", "body": "..."}
  ]
}
```

```sh
gh api repos/{owner}/{repo}/pulls/{number}/reviews --input payload.json
```

`commit_id` は省略してよい（PR の最新コミットが使われる）。特定コミットに固定したい場合のみ明示する。

### 6. 結果確認と報告

レスポンスの `state` が `PENDING` であることを確認する。PENDING 以外なら公開されてしまっているので、直ちにユーザーに報告する。

報告内容:

- 投稿した件数と、ファイル・行の一覧
- 投稿できなかった指摘（diff 外など）とその内容・理由
- 「レビューは pending 状態です。GitHub 上で内容を確認して手動で Submit してください」の一文（必須）
- PR の Files changed タブへのリンク

## Error Handling

- **422 で投稿全体が失敗**: レスポンスの `errors` から原因コメントを特定し、アンカーを修正するか対象から外して **1回だけ** 再試行する。それでも失敗したらインライン投稿を断念してユーザーに報告する。body 一括形式へ勝手に切り替えない
- **`line` が diff 外**: 手順3のルールで貼り直すか保留にする。無理に近い行へ貼らない
- **pending レビューが既に存在**: 手順2の分岐に従う。DELETE は承認を得てから
- **PR が closed / merged**: 投稿せずユーザーに確認する
- **`gh` 未認証**: `gh auth status` の結果を示し、認証を促して終了する
