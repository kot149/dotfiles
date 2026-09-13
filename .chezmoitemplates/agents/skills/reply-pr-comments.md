---
name: reply-pr-comments
description: GitHub PRのレビュー指摘コメント（レビュースレッド）へ返信するスキル。ユーザーが「レビューコメントに返信して」「指摘に返事して」「レビュー指摘へのリプライを書いて」「reply to PR comments」などと依頼した場合に使用する。対応する修正コミットがある指摘には、必ずそのコミットハッシュを添えて返信する。投稿前に必ず全文をユーザーに提示して承認を得る。
---

# Reply PR Comments

GitHub PR のレビュー指摘コメントに返信する。
指摘ごとに「どう対応したか」を1件ずつ返信し、**修正コミットがあるものには必ずコミットハッシュを添える**。

## Input

$ARGUMENTS

PR 番号 / URL、対象を絞る条件（特定ファイル、特定レビュワー、特定スレッド）が渡されることがある。
指定が無ければ現在のブランチの PR の、未解決（unresolved）スレッド全件を対象にする。

## 絶対厳守ルール

- **修正コミットがある指摘には必ずコミットハッシュを書く**。「修正しました」だけの返信は禁止。ハッシュは `commit: <sha>` の形（短縮形7〜8桁）で冒頭の対応内容の直後に書き、**コミットメッセージ（件名・本文）は書かない**
- **ハッシュを書いた場合、コミットの差分を見れば分かる内容を本文で繰り返さない**。変更したファイル名・関数名・行の羅列や、diff の言い換えは書かない。書くとしても「何をどう解決したか」の要約1〜2行に留める
- **push 済みコミットのハッシュしか書かない**。ローカルにしか無いコミットのハッシュはリベースや amend で消えるため、返信に書く前に push する（push はユーザーの承認を得てから）
- **実際に対応していないものを対応したと書かない**。コミットが指摘を直しているかを diff で確認してから引用する。未コミットの作業中変更を「修正済み」と書かない
- **参照するリソースは、リンクにできる限りすべてリンクにする**。Jira チケット、Confluence / Notion などのドキュメント、他の PR / issue、外部ドキュメントを本文で参照するときは、識別子を裸で書かずに URL 付きのリンクにする（例: `[ABC-123](https://<org>.atlassian.net/browse/ABC-123)`）。URL が確認できない場合は推測で組み立てず、識別子のみを書く
- **投稿前に返信文の全文をユーザーに提示し、承認を得る**。承認なしに投稿しない
- **1スレッド1返信**。複数の指摘への回答を1つのコメントにまとめない
- **スレッドの resolve は勝手に行わない**。必要ならユーザーに選択を求める
- **指摘の言語に合わせる**。日本語の指摘には日本語、英語の指摘には英語で返す

## 手順

### 1. 対象PRとレビュースレッドの取得

```sh
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr view --json number,state,headRefName,baseRefName --jq '{number,state,headRefName,baseRefName}'
```

`$ARGUMENTS` に PR 番号や URL があればそれを優先する。現在のブランチに PR が無く番号の指定も無い場合は、その旨を伝えて終了する。

レビュースレッドは GraphQL で取得する（REST の `pulls/{n}/comments` では解決状態が取れない）:

```sh
gh api graphql -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:50){nodes{databaseId author{login} body createdAt}}
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F number=<number>
```

- 返信先の `comment_id` は、各スレッドの **最初のコメント** の `databaseId`
- `isResolved: true` のスレッドは対象外（ユーザーが明示的に指定した場合のみ扱う）
- 既に自分の返信が付いているスレッドは、その後に新しい指摘コメントが追加されていない限り対象外
- PR 全体への通常コメント（レビュースレッドではない issue comment）は `gh pr view --json comments` で取得する。返信はスレッド化できないので `gh pr comment` での新規コメントになる

### 2. 対応状況の判定

指摘ごとに、実際のコードと履歴を見て次のいずれかに分類する。推測で埋めない。

| 分類 | 内容 | ハッシュ |
|---|---|---|
| 修正済み | 指摘どおり直したコミットがある | **必須** |
| 別案で対応 | 指摘とは違う形で解決した | **必須** |
| 未対応（今回はしない） | 対応しない、または別チケットに切る | 不要（理由と、切ったチケットがあればその番号） |
| 対応予定 | これから直す | 不要（いつ・どこで直すか） |
| 認識合わせ | 質問への回答、誤解の解消、仕様の説明 | 該当コミットがあれば添える |

### 3. 修正コミットの特定

指摘に対応するコミットを機械的に探す。ベースブランチは PR の `baseRefName` を使う。

```sh
git log --format='%h %s' origin/<base>..HEAD -- <path>   # 該当ファイルを触ったコミット
git log -S'<変更に含まれる文字列>' --format='%h %s' origin/<base>..HEAD
git show --stat <sha>
git show <sha> -- <path>
```

- 候補が複数ある場合は、指摘を実際に解消しているコミットを `git show` の diff で確認して選ぶ。複数コミットに分かれている場合は全部列挙する
- **push 済みか確認する**:

  ```sh
  git log --oneline origin/<head>..HEAD   # 空でなければ未 push のコミットがある
  ```

  未 push のコミットを引用する必要がある場合は、先に push の承認を得てから push し、**push 後のハッシュ**を使う（rebase/amend でハッシュが変わるため、返信文の生成は push 後に行う）
- fixup コミットを積んでいる場合は、autosquash 後にハッシュが変わる。squash 前に返信しない
- どのコミットとも紐づけられない指摘は、「修正済み」に分類しない。分類2の他のカテゴリに落とす

### 4. 返信文の作成

1指摘1返信。テンプレート:

```
<対応内容を1文で。何をどう解決したか> commit: <sha>

<補足が必要な場合のみ1〜2行>
```

- **ハッシュは冒頭の「〇〇しました」の文の直後に置く**。末尾や別行にまとめない
- コミットが複数ある場合は `commit: <sha>, <sha>` のようにハッシュを並べる
- ハッシュを書いた場合、詳細は差分を読めば分かるので本文には書かない。diff の言い換え、ファイル・関数・行の列挙、コミットメッセージの転記はしない
- 未対応・対応予定・認識合わせの場合はハッシュを省き、理由や回答を本文に書く
- 指摘の言い換えや長い前置きを書かない。謝辞は1語まで（「ありがとうございます」等）にとどめ、繰り返さない
- 本文中で参照するリソースはリンクにする:
  - Jira チケット: `[ABC-123](https://<org>.atlassian.net/browse/ABC-123)`。組織のドメインは PR 本文や既存コメント内の Jira URL から取る
  - 同一リポジトリの PR / issue: `#123`（GitHub が自動リンクする）。別リポジトリは `owner/repo#123`
  - Confluence / Notion / Google Docs などのドキュメント: 見出しやページ名をリンクテキストにして URL を張る
  - コード上の位置: GitHub の permalink（`git rev-parse HEAD` のコミットを含む blob URL）にする
  - コミットハッシュは `commit: <sha>` のまま裸で書く（GitHub が自動リンクする）
  - URL が特定できないものは推測で組み立てず、識別子だけを書く
- ツール名や生成主体のラベル（`[Claude]` など）は付けない

例:

```
`nil` チェックが漏れていたので、早期リターンするようにしました。 commit: a1b2c3d
```

```
この挙動は [ABC-123](https://example.atlassian.net/browse/ABC-123) で決まった仕様なので、このままにしています。
```

### 5. ユーザーへの提示と承認

投稿前に、スレッドごとに次を並べて提示する:

- ファイル・行・指摘の要約（引用は1〜2行）
- 分類と、引用するコミットハッシュ
- 返信文の**全文**

そのうえで、投稿する / 文面を直す / 一部だけ投稿する / 中止する を選ばせる。
選択提示は、選択 UI ツール（`AskUserQuestion` 等）を持つエージェントではそれを使い、無い場合は同じ選択肢を平文の番号付きリストで提示して回答を待つ。

### 6. 投稿

レビュースレッドへの返信（`comment_id` は手順1で取った最初のコメントの `databaseId`）:

```sh
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_id>/replies \
  -f body="$(cat reply.md)"
```

本文は必ずファイル経由で渡す（改行やバッククォートがシェルで壊れるのを防ぐ）。

PR 全体へのコメントへの返答:

```sh
gh pr comment <number> --body-file reply.md
```

### 7. 結果報告と resolve

- 投稿できた件数、スレッドごとのファイル・行・引用ハッシュを一覧で報告する
- 失敗したスレッドは理由とともに報告し、勝手に再送しない
- resolve するかはユーザーに確認する。承認を得た場合のみ:

  ```sh
  gh api graphql -f query='
  mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }
  ' -F id=<thread_id>
  ```

  「修正済み」以外の分類のスレッドは resolve しない（議論が続く可能性があるため）

## Error Handling

- **未 push のコミットしか無い**: 返信を保留し、push の承認を求める。ローカルハッシュで投稿しない
- **指摘に対応するコミットが見つからない**: 「修正済み」と書かず、ユーザーに状況を確認する。作業中の未コミット変更がある場合はコミット（必要なら `commit` スキル）を先に済ませる
- **404 / 403 で返信できない**: `gh auth status` で権限を確認する。PR が closed / merged の場合はユーザーに確認する
- **スレッドが outdated**: `isOutdated` でも返信自体は可能。行が動いている旨を必要に応じて本文に書く
- **`gh` 未認証**: `gh auth status` の結果を示し、認証を促して終了する
