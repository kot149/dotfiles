---
name: resolve-pr-comments
description: GitHub PRのレビューコメント（レビュースレッド）を確認し、対応済みのものをresolveするスキル。ユーザーが「レビューコメントをresolveして」「対応済みの指摘を解決済みにして」「resolve PR comments」などと依頼した場合に使用する。必要に応じて返信と👍リアクションを残し、最後に未resolveのコメントを報告する。判断に迷うスレッドは絶対にresolveしない。
---

# Resolve PR Comments

## Goal

指定されたPRのレビューコメント(review thread)を確認し、対応済みのものをresolveする。必要に応じて返信を残す。最後に未resolveのコメントを報告する。

## Target PR

$ARGUMENTS

## Steps (obey strictly)

Step 1: **PRを特定する** — 引数からPR番号またはURLを取得する。引数が空の場合は、現在のブランチに紐づくPRを `gh pr view --json number,url` で取得する。リポジトリのowner/repoも特定する。

Step 2: **レビューコメントを取得する** — 以下のGraphQLクエリで未resolveのreview threadを全件取得する。ページネーションに対応し、全スレッドを取得すること。

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          viewerCanResolve
          viewerCanReply
          comments(first: 100) {
            nodes {
              id
              body
              author { login }
              createdAt
              path
              line
            }
          }
        }
      }
    }
  }
}' -f owner="OWNER" -f repo="REPO" -F pr=NUMBER
```

Step 2b: **インライン以外のコメントも取得する** — レビュースレッドに紐づかない通常のコメント(PR会話欄のissue comment)と、レビュー本文(review body)も全件取得する。これらはresolveの対象にはならないが、各スレッドの指摘意図や、既に議論・撤回・対応済みかどうかを判断する材料として使う。

```bash
gh pr view NUMBER --json comments,reviews \
  --jq '{comments: [.comments[] | {author: .author.login, createdAt, body}],
         reviews: [.reviews[] | select(.body != "") | {author: .author.login, state, submittedAt, body}]}'
```

Step 3: **現在のコード差分を確認する** — PRの変更内容を把握するために `gh pr diff <NUMBER>` を実行する。各コメントが指摘しているファイルとコードの現在の状態もファイルを読んで確認する。

Step 4: **各スレッドを分析する** — 未resolveの各review threadについて、以下を判定する:

- コメントが指摘している問題は何か
- 現在のコードではその問題が修正済みかどうか
- 返信が必要かどうか(修正方法の説明など)

判定基準:
- **対応済み**: コメントが指摘したコードが実際に変更・削除されている、またはフィードバックが既にコードに反映されている（diffで確認できる事実に基づく）
- **未対応**: 指摘された問題がまだコードに残っている
- **提案(suggestion/nits)で未着手**: コード変更を伴う提案で、まだ変更されていないものは「未対応」として報告し、ユーザーに対応要否を委ねる。「今後対応する」という返信をして勝手にresolveしてはならない
- **判断不能**: コンテキストが不足していて判断できない場合は未対応として扱う

Step 2bで取得した通常コメント・レビュー本文は、次のように判断へ反映する:

- 指摘がレビュワー自身によって撤回・取り下げられている、または「これは対応不要」と述べられている → 対応済みとして扱ってよい
- スレッド外で対応方針の議論が続いている、宿題として残されている → 未対応として扱う
- インラインコメントの指摘内容が通常コメント側で補足・限定されている場合は、その補足を含めて何が求められているかを判定する
- 通常コメント自体に含まれる指摘(スレッドを持たないためresolveできない)は、対応状況をStep 6で報告する

Step 5: **対応済みスレッドをresolveする** — 対応済みと判断した各スレッドに対して:

5a. スレッドの最新のレビュワーコメント(自分以外が書いたコメントのうち最新のもの)に 👍 リアクションをつける。対象のコメントIDはStep 2のクエリ結果から取得する:

```bash
gh api graphql -f query='
mutation($subjectId: ID!) {
  addReaction(input: {subjectId: $subjectId, content: THUMBS_UP}) {
    reaction { content }
  }
}' -f subjectId="COMMENT_ID"
```

既に同じリアクションがついている場合はエラーになるので、その場合は無視して次に進む。

5b. 必要に応じて返信を残す(修正内容の簡潔な説明）:
```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}' -f threadId="THREAD_ID" -f body="対応内容の説明"
```

5c. スレッドをresolveする:
```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId="THREAD_ID"
```

返信・リアクションのガイドライン:
- **resolveするスレッドには必ず👍リアクションをつける** — 返信の有無に関わらず、対応済みであることの意思表示として付ける
- **事実の報告のみ許可**: 返信には「何を変更したか」の事実だけを書く。「修正します」「対応します」など未実施の作業を約束する返信は禁止。
- 単純な修正（typo、フォーマット等）で既にコードが修正済み: 返信なしでresolveのみ
- コード変更を伴う修正で既にコードが修正済み: 何を変更したか1行で返信してからresolve
- suggestion/nitsレベルで対応が任意のコメント: resolveせず、ユーザーに判断を委ねる
- 議論が必要なコメント: resolveせず、ユーザーに判断を委ねる
- **判断に迷うものはresolveしない** — 誤ってresolveするより、未resolveで報告するほうが安全

Step 6: **結果を報告する** — 以下の形式でユーザーに報告する:

```
## PR #<number> コメント対応結果

### Resolveしたコメント (<N>件)
- `<file>:<line>` — <コメント要約> → <対応内容>
- ...

### 未resolveのコメント (<N>件)
- `<file>:<line>` — <コメント要約> (理由: <未対応の理由>)
- ...

### Outdatedなコメント (<N>件)
- `<file>:<line>` — <コメント要約>
```

インライン以外のコメント(通常コメント・レビュー本文)に指摘が含まれていた場合は、上記に加えて次の節も出す。これらはresolveできないため、対応状況の報告のみ行う。

```
### インライン以外のコメント (<N>件)
- <author> のコメント — <指摘要約> (状況: <対応済み / 未対応 / 判断不能>)
```

未resolveのコメントがある場合は、それぞれについて対応が必要かどうかの所見も添える。
