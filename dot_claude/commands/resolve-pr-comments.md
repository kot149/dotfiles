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

Step 3: **現在のコード差分を確認する** — PRの変更内容を把握するために `gh pr diff <NUMBER>` を実行する。各コメントが指摘しているファイルとコードの現在の状態も `Read` ツールで確認する。

Step 4: **各スレッドを分析する** — 未resolveの各review threadについて、以下を判定する:

- コメントが指摘している問題は何か
- 現在のコードではその問題が修正済みかどうか
- 返信が必要かどうか(修正方法の説明など)

判定基準:
- **対応済み**: コメントが指摘したコードが実際に変更・削除されている、またはフィードバックが既にコードに反映されている（diffで確認できる事実に基づく）
- **未対応**: 指摘された問題がまだコードに残っている
- **提案(suggestion/nits)で未着手**: コード変更を伴う提案で、まだ変更されていないものは「未対応」として報告し、ユーザーに対応要否を委ねる。「今後対応する」という返信をして勝手にresolveしてはならない
- **判断不能**: コンテキストが不足していて判断できない場合は未対応として扱う

Step 5: **対応済みスレッドをresolveする** — 対応済みと判断した各スレッドに対して:

5a. 必要に応じて返信を残す(修正内容の簡潔な説明）:
```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}' -f threadId="THREAD_ID" -f body="対応内容の説明"
```

5b. スレッドをresolveする:
```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId="THREAD_ID"
```

返信のガイドライン:
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

未resolveのコメントがある場合は、それぞれについて対応が必要かどうかの所見も添える。
