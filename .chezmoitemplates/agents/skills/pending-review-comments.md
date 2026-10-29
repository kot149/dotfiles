---
name: pending-review-comments
description: Post review findings as inline comments on a GitHub PR in pending state (a draft review invisible to others until the user submits it). Use when the user asks things like "post the review comments as pending", "post the review findings as inline drafts on the PR", "post pending review comments", "just add the comments without publishing yet", 「pendingコメントで投稿して」「レビュー指摘をPRに下書きで入れて」「まだ公開せずコメントだけ付けて」, any similar phrasing in English or Japanese, or when writing the results of other review work to a PR. Never submit (publish) the review; always leave that to the user by hand.
---

# Pending Review Comments

Post review findings as inline comments on a GitHub PR as a **pending review** (draft).
A pending review is visible only to its author and stays hidden from everyone else until the user submits it in the GitHub UI.

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Input

The findings come from one of the following:

- Review results earlier in the conversation (`/deep-review`, `/code-review`, a Codex review, your own review, etc.)
- File paths or text named in the request
- Findings the user listed in the message body

Each finding needs at minimum a **file path, line, and body**. Do not post findings whose line cannot be determined; report them to the user as described below.

## Strict Rules

- **Always create in pending state**. POST to the reviews API with **no `event` field at all**. A review is created as PENDING only when `event` is omitted. Specifying `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` is forbidden
- **Never perform submit operations**: `gh pr review --comment/--approve/--request-changes` and `POST .../reviews/{id}/events` are forbidden. The user submits by hand
- **Make every finding an inline comment**: each finding goes in the `comments` array with `path` + `line` anchored to the relevant line. Keep the review body empty; never write findings or a summary in the body
- **Never delete an existing pending review on your own**: discarding one requires the user's explicit approval first
- **Never post a finding that duplicates an existing comment**: fetch existing review comments in step 3 and drop anything already raised at the same place with the same point. Treat resolved and outdated threads as "already raised"
- **Never invent finding content**: do not create findings that are not in the input. Conversely, always report the ones you could not post

## Steps

### 1. Identify the target PR

```sh
gh repo view --json nameWithOwner --jq .nameWithOwner
gh pr view --json number,state,headRefName --jq '{number,state,headRefName}'
```

If the request contains a PR number or URL, prefer it. If the current branch has no PR and no number was given, present the following to the user in Japanese and stop (never create a PR on your own):

```
現在のブランチに対応するPRが見つかりませんでした。PR番号またはURLを指定してください。
```

### 2. Check for an existing pending review

```sh
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[] | select(.state=="PENDING")] | {count: length, ids: [.[].id]}'
```

GitHub allows only one pending review per user per PR. If one already exists, do not post and present the following to the user in Japanese to have them choose:

```
既存の pending レビューが見つかりました。どうしますか?
1. 既存の pending を GitHub 上で Submit してから再実行する
2. 既存の pending を破棄する (承認後に `gh api -X DELETE repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}` で破棄します)
3. 今回の投稿を中止する
```

Take the choice with a selection prompt, with the question and options in Japanese as above.

### 3. Dedupe against existing comments

Do not pile another post onto a spot that already has the same finding. First fetch all existing review comments:

```sh
gh api --paginate repos/{owner}/{repo}/pulls/{number}/comments \
  --jq '.[] | {path, line, original_line, in_reply_to_id, user: .user.login, body}'
```

Resolved and outdated threads are included above, but their resolution state is not visible there, so supplement with GraphQL when needed:

```sh
gh api graphql -f query='
{
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {number}) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          comments(first: 10) { nodes { path line author { login } body } }
        }
      }
    }
  }
}'
```

The PR body and issue comments (`gh api repos/{owner}/{repo}/issues/{number}/comments`) sometimes contain the same finding, so check those too while the finding count is small.

Decision criteria:

- **Duplicate**: the same cause and same point already raised at the same spot in the same file (a few lines of drift still counts as the same)
- **Duplicate**: attached to a different line but targeting the same problem (the same bug in the same function, the same config value, etc.)
- **Not a duplicate**: same line but a different focus (one about naming, one about a boundary value, etc.)
- **Not a duplicate**: the existing comment is a question or chatter that does not stand as a finding

Do **not** re-raise content already covered in a resolved or outdated thread. It is either already fixed or deliberately set aside, so reposting only rehashes it. The only exception is when you verified the current code still shows the supposedly fixed problem; then you may post while referencing the existing thread.

List the findings you excluded as duplicates in the final report as "excluded as duplicates of existing comments" (never drop them silently).

### 4. Validate anchor lines

```sh
gh pr diff {number}
```

Compare the diff against each finding's line:

- Finding on an added/changed line: `side: "RIGHT"`, with `line` as the line number in the **new** file
- Finding on a deleted line: `side: "LEFT"`, with `line` as the line number in the **old** file
- Finding spanning multiple lines: `start_line` + `line` (align `start_side` / `side` too)
- Line outside the diff range: re-anchor to the **in-diff line** in the same file most relevant to the finding
- Finding with no suitable line: do not post inline; put it on the hold list as "unpostable: outside the diff" and report it with its content at the end

Paths must be **relative to the repository root** and match what appears in the diff exactly.

### 5. Compose comment bodies

One comment per finding. Never pack multiple findings into one comment.

```
**[<kind> / <grade>] <finding title>**

<what is wrong (1-3 lines)>

**Suggestion:** <how to fix it>
```

- `<kind>` is what sort of finding it is, as the caller classified it: a review perspective (`maintainability`, `security`), a finding category, or whatever taxonomy the caller uses. It is never the name of the skill or model that produced it
- `<grade>` is how the caller ranked or judged it: a severity (`HIGH`), a verdict (`PARTIALLY_VALID`), or any single token of that kind
- If the input has no `<kind>` or no `<grade>`, drop the label line and use just the title
- Do not add generator-name labels like `[deep-review]`, `[meta-review]` or `[Claude]`. A reader of the PR cares what the finding is, not which tool wrote it
- When showing fixed code, you may use a GitHub suggestion block:

  ````
  ```suggestion
  <replacement lines>
  ```
  ````

  A suggestion replaces the whole `line` (or `start_line` to `line` range), so match the line count and content against the diff exactly.

### 6. Post

Write the payload to a file and POST it (no `event` included):

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

`commit_id` may be omitted (the PR's latest commit is used). Specify it only when you want to pin a particular commit.

### 7. Verify results and report

Confirm the response `state` is `PENDING`. Anything else means it was published, so present the following to the user in Japanese immediately:

```
レビューが公開されてしまいました (state: <state>)。GitHub 上でご確認ください。
```

Present the report to the user in Japanese with the following contents (fill in the file/line lists, reasons, URLs, and the Files changed link):

```
<N>件投稿しました:
- `<ファイル>:<行>` — <指摘の要約>
- ...

投稿できなかった指摘:
- `<ファイル>:<行>` — <内容> (理由: <diff 外のため投稿不可など>)
- ...

既存コメントと重複のため除外した指摘:
- `<ファイル>:<行>` — <内容> (重複先: <comment URL>)
- ...

レビューは pending 状態です。GitHub 上で内容を確認して手動で Submit してください。
Files changed: https://github.com/<owner>/<repo>/pull/<number>/files
```

## Error Handling

- **Whole post fails with 422**: identify the offending comment from the response `errors`, fix its anchor or drop it, and retry **exactly once**. If it still fails, give up on inline posting and present the following to the user in Japanese. Never switch to a body-bulk format on your own:

  ```
  投稿全体が 422 で失敗しました。原因のコメント: `<ファイル>:<行>` — <エラー内容>。インライン投稿を断念します。対応方法を教えてください。
  ```

- **`line` outside the diff**: re-anchor or hold per the step 4 rules. Do not force it onto a barely related line. When holding, present the following to the user in Japanese:

  ```
  diff 外のため投稿を保留しました: `<ファイル>:<行>` — <指摘の要約>。最も関連する diff 内の行に貼り直すか、保留のままにします。どうしますか?
  ```

- **A pending review already exists**: follow the step 2 branches. DELETE only after approval
- **PR is closed / merged**: do not post; present the following to the user in Japanese and ask first:

  ```
  PR はクローズ/マージ済みです。投稿せずに終了しました。どうしますか?
  ```

- **`gh` not authenticated**: show the `gh auth status` result, present the following to the user in Japanese, and stop:

  ```
  `gh` の認証が切れています。`gh auth status` の結果は以下の通りです: <output>。認証してから再実行してください。
  ```
