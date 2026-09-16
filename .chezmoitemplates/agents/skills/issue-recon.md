---
name: issue-recon
description: >-
  Skill for gathering everything needed to implement an issue or ticket.
  Reads the ticket and all its comments, turns it into a list of concrete
  unknowns, then resolves in parallel every unknown that existing code,
  documents, or the database can settle, and reports in Japanese only the
  remaining items that genuinely need a human decision, each with a
  recommended default.
  Use when asked things like "collect the information needed to implement
  this ticket", "investigate before implementing ABC-123", "what do I still
  need to decide for this issue", "issue recon",
  「このチケットの実装に必要な情報を集めて」「実装前に調査して」
  「このissueで決めないといけないことを洗い出して」.
  Investigation only. Does not write implementation code.
---

# Issue Recon

Turn an issue or ticket into an implementation-ready information set.
Everything that can be settled by reading existing code, documents, or data is
settled here with evidence attached. Everything else is handed back to the
human as a small, specific set of decisions.

The output is not a summary of the ticket. It is the answer to "what does
someone need to know to start writing this code, and what is still genuinely
undecided".

## Capability Mapping

**Subagent**: delegating research to a child agent with an independent context.

- Claude Code: the `Agent` tool. `Explore` for read-only exploration roles,
  `general-purpose` for roles that need to run commands. Launch parallel agents
  by grouping multiple `Agent` calls in one message
- Codex CLI: issue the needed number of `spawn_agent` calls, then `wait`
  (requires `features.multi_agent`. Pick roles from `[agents]` in `config.toml`)

Agents with no parallel mechanism fall back to sequential execution and note
that in the output. Every research subagent is read-only and gets a fresh
context: pass it the facts it needs rather than assuming it saw the ticket.

**Ask the user to choose**: use a selection UI tool (`AskUserQuestion` and
similar) where the agent has one, otherwise present the same options as a
numbered plain-text list and wait for an answer.

**Ticket access**: Jira goes through the Atlassian MCP server's issue-fetch and
JQL-search tools, Linear through the Linear MCP server, GitHub Issues through
`gh issue view`. Tool ids differ per agent, and agents that load tool schemas
lazily must load the definitions before the first call.

## Step 0: Identify the Target

Accept a ticket key (`ABC-123`), a ticket URL, a GitHub issue number, or a
prose description. Resolve it to exactly one ticket before going further.

If the target is ambiguous, list the candidates and ask the user to choose.
If no ticket exists and the user only described the work in prose, say so, and
treat their description as the ticket body for the rest of the skill.

## Step 1: Read the Ticket Fully

Run this yourself rather than delegating it: the ticket is the input every
later step depends on.

Fetch the body **and every comment**. Comments are where scope changes,
reversals, and half-answers live. Also fetch:

- The parent epic and any linked or blocking tickets (positioning only, 1-2
  lines each, unless a linked ticket carries the actual spec)
- Attachments, design-document links, Slack permalinks, Figma links named in
  the body or comments. Read what you can access; list what you cannot
- Any PR or branch already linked to the ticket

Do not stop at the body just because the body looks complete.

## Step 2: Build the Unknown List

Rewrite the ticket into a flat list of **concrete unknowns**, each phrased as a
question whose answer changes the code. This list is the spine of the whole
skill: every later step either answers an item or escalates it.

Cover at least these angles, dropping the ones that do not apply:

- **Behavior**: what exactly happens, for each input class and each state
- **Edge cases**: empty, zero, missing, expired, duplicate, concurrent,
  already-applied, permission-denied, upstream-down
- **Data**: which tables/collections/fields are involved, their real types,
  nullability, indexes, and what the production data actually looks like
  (distribution, volume, existing dirty rows)
- **Interfaces**: request/response shapes, API contracts, events, and every
  existing caller of anything being changed
- **Existing conventions**: how comparable features in this repository are
  already built, so the new code matches
- **Non-functional**: expected volume, latency budget, transactional
  boundaries, idempotency, backfill/migration needs
- **Permissions and visibility**: who can see and do this
- **Observability and rollout**: logs, metrics, feature flag, release order

Mark each unknown as **resolvable by investigation** or **needs a human**.
Default to "resolvable" and only mark "needs a human" when the answer is a
product, policy, or priority choice that no artifact can contain. An unknown
that merely *looks* undecided ("which error message?") is usually resolvable by
finding the existing convention.

## Step 3: Resolve in Parallel

Launch one subagent per applicable track, all in one batch. Skip tracks with
nothing to investigate. Give every subagent the same closing instruction:

> Answer each assigned question with a verdict plus evidence as
> `path:line`, a query, or a URL. If the evidence does not settle it, say
> "unresolved" and state what is missing. Never fill a gap by guessing.

### Track A: Codebase

- The exact code paths the change touches, entry point to persistence
- Existing callers and consumers of anything whose contract changes
- The established pattern for this kind of feature in this repository
  (validation, error handling, transactions, logging, auth checks, tests)
- Whether any of the requested behavior already exists, partially or fully
- Test layout: where the tests for this area live and what shape they take

### Track B: Documents and History

- Design docs, specs, ADRs, README sections covering this area, in-repo and in
  Confluence / Notion / Drive
- Prior tickets and PRs touching the same area, and any reasoning recorded
  there for why it works the way it does
- Slack threads linked from the ticket

### Track C: Data and Schema

- Schema definitions from the repository first (migrations, DDL, ORM models,
  ERDs). Prefer this over touching a live database
- When the live database is genuinely needed, run **read-only queries only**
  (`SELECT` / `find` with a limit; no write, no DDL, no long full scans), and
  prefer a non-production environment. Obtain credentials without exposing
  their values (see the `keychain-credentials` skill)
- Do not pull personal or sensitive records into the output. Report shapes,
  counts, and distributions, not rows

### Track D: External Dependencies

Only when the ticket depends on one: external API contracts, SDK behavior,
library capability and version constraints, rate limits, sandbox availability.

## Step 4: Close the Loop

Cross-check the returned answers against the ticket and against each other.
Then, for each unknown:

1. **Settled** → record the answer and its evidence
2. **Contradicted** → two sources disagree. Re-check the primary source
   yourself. If they still disagree, it becomes a human decision, stated as the
   contradiction it is
3. **Unresolved** → decide whether one more targeted investigation would settle
   it. Run it. Only after that does it escalate

Do not take subagent reports at face value. Spot-check any claim the plan hangs
on by reading the cited line yourself.

## Step 5: Report

Present to the user in Japanese, in this order. Omit a section that is empty
rather than padding it.

```
## 実装に必要な情報

### 要件
チケットとコメントから確定した、実装する挙動。入力ごと・状態ごとに書く

### 確定した調査結果
調査で答えが出た項目。1項目1行、根拠を `path:line` / クエリ / URL で付ける
- 既存の実装とパターン: どこに何があり、新しいコードは何に倣うか
- データとスキーマ: 実際の型・NULL可否・件数・既存データの状態
- 影響範囲: 契約が変わるものの呼び出し元、動かなくなる可能性のある箇所

### 実装の入り口
どのファイルのどこから手を付けるか、変更が必要なファイルと役割

### 人間の判断が必要な項目
調査では決まらなかったものだけ。1項目ごとに:
- 問い(コードの何が変わるのかまで書く)
- 選択肢と、それぞれを選んだ場合にどうなるか
- 推奨案と、その理由
- 調査で分かっている関連事実

### 調査できなかったこと
アクセス権がない、環境がない等で確認できなかった項目と、その理由
```

Rules for the last two sections:

- Every human-decision item must be answerable in one line by the user. If it
  needs a paragraph to answer, it was not split finely enough
- Every human-decision item carries a recommended default. "どうしますか" with
  no recommendation is not an acceptable item
- Never move an item into the human-decision list because investigating it was
  tedious. It goes there only when no artifact can hold the answer
- State what could not be checked. A silent gap reads as a confirmed fact

## Notes

- Investigation only. Do not write implementation code, and do not modify the
  ticket, in this skill
- Scale the effort to the ticket. A one-line copy fix does not need four
  parallel tracks; run the relevant ones and say so
- If the ticket turns out to be under-specified to the point that the unknown
  list is mostly human decisions, report that directly instead of producing a
  thin brief
- After the report, offer the next step in Japanese as one line:

  ```
  判断が必要な項目を決めたら、実装に進めますか?
  ```
