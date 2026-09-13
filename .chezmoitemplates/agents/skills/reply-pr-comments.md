---
name: reply-pr-comments
description: Skill for replying to GitHub PR review finding comments (review threads). Use when the user asks things like "reply to the review comments", "respond to the findings", "write replies to the review feedback", "reply to PR comments", 「レビューコメントに返信して」「指摘に返事して」「レビュー指摘へのリプライを書いて」, or any similar phrasing in English or Japanese. For any finding with a corresponding fix commit, always include that commit hash in the reply. Always show the full text to the user for approval before posting.
---

# Reply PR Comments

Reply to review finding comments on a GitHub PR.
Write one reply per finding describing "how it was addressed", and **always
include the commit hash for anything with a fix commit**.

## Input

$ARGUMENTS

A PR number / URL and narrowing conditions (specific file, specific reviewer,
specific thread) may be passed.
With no narrowing specified, target all unresolved threads on the current
branch's PR.

## Strict Rules (must follow)

- **For any finding with a fix commit, always write the commit hash.** Replies
  of just "fixed it" are forbidden. Write the hash in the form `commit: <sha>`
  (short 7-8 digit form) right after the opening summary sentence, and **do not
  write the commit message (subject/body)**
- **When a hash is included, do not repeat in prose what is visible from the
  commit diff.** Do not list changed file/function/line names or paraphrase the
  diff. At most, add a 1-2 line summary of "what was resolved and how"
- **Only cite hashes of pushed commits.** Hashes of local-only commits disappear
  on rebase or amend, so push before writing them into a reply (get the user's
  approval before pushing)
- **Never claim something was addressed when it was not.** Check the diff to
  confirm the commit actually fixes the finding before citing it. Do not call
  uncommitted work-in-progress changes "fixed"
- **Link every referenceable resource.** When referencing Jira tickets,
  Confluence / Notion documents, other PRs / issues, or external docs in the
  body, use URL links instead of bare identifiers (e.g.
  `[ABC-123](https://<org>.atlassian.net/browse/ABC-123)`). When the URL cannot
  be confirmed, write only the identifier without guessing a URL
- **Show the full reply text to the user and get approval before posting.**
  Never post without approval
- **One reply per thread.** Do not bundle answers to multiple findings into a
  single comment
- **Never resolve a thread unilaterally.** Ask the user to choose when needed
- **Match the finding's language.** Reply in the same language as the finding
  (findings in English get English replies, findings in other languages get
  replies in that language)

## Procedure

### 1. Fetch the Target PR and Review Threads

```sh
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr view --json number,state,headRefName,baseRefName --jq '{number,state,headRefName,baseRefName}'
```

Prefer the PR number or URL from `$ARGUMENTS` when given. When the current
branch has no PR and no number is given, present the following to the user in
Japanese and stop:

```
現在のブランチに対応するPRが見つかりませんでした。PR番号またはURLを指定してください。
```

Fetch review threads via GraphQL (REST `pulls/{n}/comments` does not expose
resolution state):

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

- The reply target `comment_id` is the `databaseId` of each thread's **first
  comment**
- Threads with `isResolved: true` are out of scope (handle them only when the
  user explicitly names them)
- Threads that already carry your own reply are out of scope unless a new
  finding comment was added after it
- Plain PR-level comments (issue comments, not review threads) are fetched with
  `gh pr view --json comments`. They cannot be threaded, so replies to them
  become new comments via `gh pr comment`

### 2. Judge How Each Finding Was Addressed

Classify each finding by looking at the actual code and history. Do not fill
gaps by guessing.

| Classification | Meaning | Hash |
|---|---|---|
| Fixed | Fixed as suggested, with a commit | **Required** |
| Fixed differently | Resolved in a different way than suggested | **Required** |
| Not addressing (this time) | Will not address, or split into another ticket | Not needed (reason plus ticket number if one was cut) |
| Planned | To be fixed later | Not needed (when and where it will be fixed) |
| Alignment | Answer to a question, clearing up a misunderstanding, explaining the spec | Attach one if an applicable commit exists |

### 3. Identify the Fix Commits

Find the commit for each finding mechanically. Use the PR's `baseRefName` as
the base branch.

```sh
git log --format='%h %s' origin/<base>..HEAD -- <path>   # commits touching the relevant file
git log -S'<string contained in the change>' --format='%h %s' origin/<base>..HEAD
git show --stat <sha>
git show <sha> -- <path>
```

- With multiple candidates, inspect diffs with `git show` and pick the commit
  that actually resolves the finding. List every commit when the fix spans
  several of them
- **Verify the commit is pushed**:

  ```sh
  git log --oneline origin/<head>..HEAD   # non-empty means unpushed commits exist
  ```

  When an unpushed commit must be cited, get push approval first, push, then use
  the **post-push hash** (generate the reply text only after pushing, since
  rebase/amend changes hashes)
- When fixup commits are stacked, hashes change after autosquash. Do not reply
  before squashing
- A finding that maps to no commit is never classified as "fixed". Drop it into
  one of the other categories from step 2

### 4. Draft the Replies

One reply per finding. Template:

```
<what was done, in one sentence: what was resolved and how> commit: <sha>

<1-2 lines only when extra context is needed>
```

- **Put the hash right after the opening "did X" sentence.** Do not collect
  hashes at the end or on a separate line
- With multiple commits, list the hashes like `commit: <sha>, <sha>`
- When a hash is included, the details are visible from the diff, so do not
  write them in the body. No diff paraphrases, no file/function/line lists, no
  commit-message transcription
- For not-addressed / planned / alignment cases, omit the hash and write the
  reason or answer in the body
- Do not paraphrase the finding or write long preambles. Keep thanks to one
  word at most (e.g. "Thanks") and do not repeat it
- Link resources referenced in the body:
  - Jira tickets: `[ABC-123](https://<org>.atlassian.net/browse/ABC-123)`. Take
    the org domain from Jira URLs in the PR body or existing comments
  - PRs / issues in the same repository: `#123` (GitHub auto-links). Other
    repositories: `owner/repo#123`
  - Confluence / Notion / Google Docs: link the heading or page title as the
    link text
  - Code locations: GitHub permalinks (blob URL containing the commit from
    `git rev-parse HEAD`)
  - Commit hashes stay bare as `commit: <sha>` (GitHub auto-links them)
  - Never guess an unconfirmable URL; write only the identifier
- Do not add tool or authorship labels (such as `[Claude]`)

Examples (match the finding's language — English findings get English replies, Japanese findings get Japanese replies):

```
Added an early return so a missing `nil` check no longer slips through. commit: a1b2c3d
```

```
ご指摘のとおり早期リターンを追加し、`nil` チェック漏れが起きないようにしました。commit: a1b2c3d
```

```
This behavior follows the spec decided in [ABC-123](https://example.atlassian.net/browse/ABC-123), so leaving it as is.
```

### 5. Present to the User and Get Approval

Before posting, present the following to the user in Japanese per thread:

```
対象: `<ファイル>:<行>` — <指摘の要約>(引用1-2行)
分類: <修正済み / 別方法で対応 / 今回は対応しない / 対応予定 / 確認回答> commit: <sha>
返信文(全文):
<reply body as drafted in step 4, in the same language as the finding>
```

Then present the following to the user in Japanese and have them choose:
post / edit the text / post only some / abort.

```
返信案は以上です。どうしますか?
1. 投稿する
2. 文面を修正する
3. 一部のみ投稿する
4. 中止する
```

In agents with a selection UI tool (such as `AskUserQuestion`), use it; where
there is none, present the same options as a plain numbered list and wait for
an answer.

### 6. Post

Reply to a review thread (`comment_id` is the `databaseId` of the first comment
taken in step 1):

```sh
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_id>/replies \
  -f body="$(cat reply.md)"
```

Always pass the body via a file (prevents newlines and backquotes from breaking
in the shell).

Replying to a PR-level comment:

```sh
gh pr comment <number> --body-file reply.md
```

### 7. Report Results and Resolve

- Present the following to the user in Japanese to report how many were
  posted, with per-thread file, line, and cited hash:

  ```
  <N>件の返信を投稿しました。
  - `<ファイル>:<行>` — commit: <sha>
  - ...
  ```

- Present the following to the user in Japanese to report failed threads with
  reasons; never resend unilaterally:

  ```
  投稿に失敗したスレッドがあります。
  - `<ファイル>:<行>` — <理由>
  再送はしません。対応方法を教えてください。
  ```

- Present the following to the user in Japanese to ask whether to resolve.
  Only with approval:

  ```sh
  gh api graphql -f query='
  mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }
  ' -F id=<thread_id>
  ```

  Do not resolve threads classified anything other than "fixed" (discussion may
  still continue)

## Error Handling

- **Only unpushed commits exist**: hold the reply and present the following to
  the user in Japanese to ask for push approval. Do not post with a local hash:

  ```
  未プッシュのコミットがあるため、返信を保留しています。プッシュしてよいですか?
  ```

- **No commit matches the finding**: do not write "fixed"; present the
  following to the user in Japanese to ask about the status. When uncommitted
  work-in-progress changes exist, commit them first (using the `commit` skill
  if needed):

  ```
  指摘に対応するコミットが見つかりませんでした。対応状況を教えてください。
  - `<ファイル>:<行>` — <指摘の要約>
  ```

- **Reply fails with 404 / 403**: check permissions with `gh auth status`. When
  the PR is closed / merged, present the following to the user in Japanese to
  confirm:

  ```
  返信の投稿に失敗しました(404 / 403)。PRはクローズ/マージ済みでしょうか? 対応方法を教えてください。
  ```
- **Thread is outdated**: replying is still possible despite `isOutdated`. Note
  in the body as needed that the line has moved
- **`gh` not authenticated**: show the `gh auth status` output, present the
  following to the user in Japanese to prompt for authentication, and stop:

  ```
  `gh`の認証が切れています。認証してから再実行してください。
  ```
