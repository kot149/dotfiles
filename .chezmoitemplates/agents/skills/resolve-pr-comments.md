---
name: resolve-pr-comments
description: Skill for checking GitHub PR review comments (review threads) and resolving the addressed ones. Use when the user asks things like "resolve the review comments", "mark the addressed findings as resolved", "resolve PR comments", 「レビューコメントをresolveして」「対応済みの指摘を解決済みにして」, or any similar phrasing in English or Japanese. Only resolve, react to, or reply to threads you started; treat threads started by others as reference-only. Never resolve a thread when in doubt.
---

# Resolve PR Comments

## Goal

Check the review comments (review threads) on the given PR and resolve the
addressed ones among the threads you started. Leave a reply when needed. Treat
threads started by others as reference-only: never resolve, react, or reply to
them. Finally, report the still-unresolved comments.

## Target PR

$ARGUMENTS

## Steps (obey strictly)

**Batch independent commands into one message.** Commands that do not consume
each other's output must be issued as several tool calls in a **single**
message, never one call per message. Agents batch their approval prompt per
message, so issuing them one at a time forces the user through one prompt per
command. This applies to Step 1 and Step 2/2b (all read-only fetches together)
and to Step 5 (every reaction, reply, and resolve for every target thread
together, after the judgment in Step 4b is finished). Split into a second
message only when a command genuinely needs an earlier one's output.

Step 1: **Identify the PR** — take the PR number or URL from the arguments. When
the arguments are empty, get the PR tied to the current branch with
`gh pr view --json number,url`. Also identify the repository owner/repo. In
addition, get your own GitHub username with `gh api user --jq .login`.

Step 2: **Fetch the review comments** — fetch all unresolved review threads
with the GraphQL query below. Support pagination and fetch every thread.

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

Step 2b: **Also fetch non-inline comments** — also fetch all plain comments (PR
conversation issue comments, not tied to a review thread) and review bodies.
These are never resolve targets, but use them as material for judging each
thread's intent and whether it was already discussed, withdrawn, or addressed.

```bash
gh pr view NUMBER --json comments,reviews \
  --jq '{comments: [.comments[] | {author: .author.login, createdAt, body}],
         reviews: [.reviews[] | select(.body != "") | {author: .author.login, state, submittedAt, body}]}'
```

Step 3: **Check the current code diff** — run `gh pr diff <NUMBER>` to grasp the
PR's changes. Also read the files to check the current state of the code each
comment points at.

Step 4: **Split each thread into yours and others'** — compare the
`author.login` of each review thread's first comment (the comment that started
the thread) against your own GitHub username from Step 1.

- Match (a thread you started) → candidate for the following steps
  (resolve/reaction/reply)
- No match (a thread someone else started) → never resolve, react, or reply.
  Only reference it to understand findings and to judge your own threads. In
  Step 6, report only the unresolved count

Step 4b: **Analyze your own threads** — for each unresolved thread of yours,
judge the following:

- What problem the comment points at
- Whether the problem is already fixed in the current code
- Whether a reply is needed (e.g. explaining the fix)

Criteria:

- **Addressed**: the code the comment pointed at was actually changed or
  removed, or the feedback is already reflected in the code (based on facts
  verifiable in the diff)
- **Unaddressed**: the pointed-out problem still remains in the code
- **Untouched proposal (suggestion/nits)**: a proposal requiring a code change
  that has not been made yet counts as "unaddressed"; report it and leave the
  decision to the user. Never reply "will address it later" and resolve it
  unilaterally
- **Undecidable**: when context is insufficient, treat as unaddressed

Reflect the plain comments and review bodies from Step 2b in your judgment as
follows:

- The finding was withdrawn by the reviewer, or stated as "no action needed" →
  may be treated as addressed
- Discussion on the approach continues outside the thread, or it remains as a
  follow-up → treat as unaddressed
- When an inline comment's finding is supplemented or scoped by a plain
  comment, judge what is being asked including that supplement
- Findings contained in plain comments themselves (which have no thread and
  cannot be resolved) are only reported in Step 6 with their status

Step 5: **Resolve the addressed threads** — for each of your own threads judged
addressed in Step 4b (threads started by others are out of scope). Decide 5a-5c
for every target thread first, then issue all of those commands in one message
as parallel tool calls; the reaction, the reply, and the resolve are independent
API calls and none of them needs another's output.

5a. Add a 👍 reaction to the thread's latest reviewer comment (the latest
comment written by someone other than you). Take the target comment ID from the
Step 2 query result:

```bash
gh api graphql -f query='
mutation($subjectId: ID!) {
  addReaction(input: {subjectId: $subjectId, content: THUMBS_UP}) {
    reaction { content }
  }
}' -f subjectId="COMMENT_ID"
```

Adding the same reaction twice errors, so ignore that error and move on.

5b. Leave a reply when needed (a concise explanation of the fix):
```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}' -f threadId="THREAD_ID" -f body="DESCRIPTION_OF_FIX"
```

5c. Resolve the thread:
```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId="THREAD_ID"
```

Reply/reaction guidelines:
- **Always add a 👍 reaction to every thread you resolve** — attach it
  regardless of whether you reply, as a sign that it was addressed
- **Only factual reports allowed**: replies state only "what was changed" as
  fact. Replies promising unperformed work ("will fix", "will address") are
  forbidden.
- Trivial fix (typo, formatting, etc.) with code already fixed: resolve only,
  no reply
- Fix involving a code change with code already fixed: reply with a one-line
  note on what changed, then resolve
- Suggestion/nits-level comments where addressing is optional: do not resolve;
  leave the decision to the user
- Comments needing discussion: do not resolve; leave the decision to the user
- **When in doubt, do not resolve** — reporting it unresolved is safer than
  resolving it by mistake

Step 6: **Report the results** — present the following to the user in Japanese:

```
## PR #<number> コメント対応結果

### 解決済みコメント(<N>件、自分のスレッドのみ)
- `<ファイル>:<行>` — <コメントの要約> → <対応内容>
- ...

### 未解決コメント - 自分のスレッド(<N>件)
- `<ファイル>:<行>` — <コメントの要約>(理由: <未対応の理由>)
  - 対応: <必要なアクション>
- ...

### 未解決コメント - 他者のスレッド(<N>件、参照のみ、未解決のまま)
- `<ファイル>:<行>` — <作成者> — <コメントの要約>
- ...

### Outdatedなコメント(<N>件)
- `<ファイル>:<行>` — <コメントの要約>
```

When plain comments (non-inline comments / review bodies) contain findings, add
the following section to the report above, presented to the user in Japanese.
These cannot be resolved, so only report their status.

```
### スレッド外コメント(<N>件)
- <作成者>のコメント — <指摘の要約>(状態: <対応済み / 未対応 / 判断不可>)
  - 対応: <必要なアクション>
```

When unresolved comments remain, each entry carries its own action note on
whether action is needed, as shown in the templates above.
