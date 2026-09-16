---
name: issue-recon-loop
description: >-
  Repeat the issue-recon investigation round after round until it converges,
  that is, until a round produces neither a correction to an earlier finding
  nor a new one. Each round re-investigates from the current findings, aimed at
  the weakest evidence and the still-open unknowns, and reports in Japanese the
  converged information set plus the decisions that genuinely need a human.
  Use when asked things like "investigate this ticket until nothing new comes
  up", "run issue recon repeatedly", "issue recon loop", "keep digging until it
  converges",
  「訂正や新しい発見が出なくなるまで調査して」「issue-reconを繰り返して」
  「収束するまで調べて」.
  Investigation only. Does not write implementation code.
argument-hint: "[ticket] [--max-rounds=N] [--auto]"
---

# Issue Recon Loop

Run [[issue-recon]] repeatedly on one ticket. A single pass answers the
unknowns it thought to ask; the loop exists because answering them reliably
exposes unknowns the first pass could not have phrased, and occasionally shows
that an earlier answer was wrong.

The loop ends on **convergence**: a round that produces no correction and no
new finding. The deliverable is the converged information set, not a log of the
rounds.

## Target

$ARGUMENTS

Arguments may name the ticket (key, URL, issue number, or prose) plus these
flags.

| Flag | Effect |
|---|---|
| `--max-rounds=N` | Round cap. Default 5, hard maximum 8 |
| `--auto` | Do not pause between rounds. Run to convergence or the cap, then report once |

## Capability Mapping

**Subagent**: delegating research to a child agent with an independent context.

- Claude Code: the `Agent` tool. `Explore` for read-only exploration roles,
  `general-purpose` for roles that need to run commands. Launch parallel agents
  by grouping multiple `Agent` calls in one message
- Codex CLI: issue the needed number of `spawn_agent` calls, then `wait`
  (requires `features.multi_agent`. Pick roles from `[agents]` in `config.toml`)

Agents with no parallel mechanism fall back to sequential execution and note
that in the output. Every research subagent is read-only and gets a fresh
context.

**Ask the user to choose**: use a selection UI tool (`AskUserQuestion` and
similar) where the agent has one, otherwise present the same options as a
numbered plain-text list and wait for an answer.

## The Ledger

The loop carries one working document across rounds. Keep it in a scratch file
so it survives context pressure, and treat it as the single source of state.

Each entry:

```
ID  | 問い | 現在の答え | 根拠 | 確度 | 状態 | 最終更新ラウンド
```

- **確度**: `確定` (primary evidence read directly) / `暫定` (one subagent
  report, unverified) / `未解決`
- **状態**: `解決済` / `調査中` / `要人間判断` / `訂正済`
- An entry is never deleted. A corrected entry keeps its ID and records the new
  answer; the old answer is dropped, not archived (the final report shows only
  the current state)

## Round 1: Full Recon

Run [[issue-recon]] end to end, with one change: instead of reporting to the
user, write the result into the ledger. Every unknown from its Step 2 becomes
an entry, and its Step 3 tracks fill them in.

If the skill body is unavailable, fall back to: read the ticket and all its
comments, list the concrete unknowns, resolve in parallel everything code,
documents, or data can settle, and record evidence as `path:line`, a query, or
a URL.

## Rounds 2..N: Targeted Re-Investigation

Each later round is aimed, not a repeat of round 1. Build the round's question
set from the ledger in this priority order, and stop adding when the round has
enough to keep 3-6 subagents busy:

1. **`未解決` entries** — what is still missing, and what other angle would
   settle it
2. **`暫定` entries the plan hangs on** — re-derive the answer from the primary
   source, with a subagent that was not told the previous answer
3. **Unknowns implied by round N-1's answers** — the real yield of the loop. An
   answer that named a new caller, table, flag, or code path creates unknowns
   about that thing
4. **Consistency probes** — pick pairs of settled entries that must agree
   (schema vs. code, spec vs. implementation, two callers of the same contract)
   and have a subagent check they actually do
5. **`要人間判断` entries** — re-test the classification once. Most items that
   look undecided are settled by an existing convention

Round rules:

- **Blind re-derivation**: when re-checking a `暫定` entry, give the subagent
  the question and the sources, never the previous answer. Told the answer, it
  confirms the answer
- **Fresh angle**: do not re-run an identical search and call the identical
  result a confirmation. Confirmation requires a different path to the same
  fact (different file, different tool, different direction of the call graph)
- **Spot-check yourself**: read the cited line directly for any entry the
  implementation plan depends on. Subagent reports are not primary evidence
- A round that only re-reads what round N-1 already read has produced nothing;
  count it as a no-change round

## Convergence Check

At the end of every round, classify each result as exactly one of:

- **訂正**: an existing entry's answer changed
- **新規**: an entry was added, or an entry moved out of `未解決`
- **変化なし**: same answer, no new entry

Converged when a round yields zero 訂正 and zero 新規. Report the round count
and stop.

Stop early, before convergence, when any of these hits. Say which one in the
report:

- Round cap reached (`--max-rounds`, default 5)
- Two consecutive rounds where the only remaining open entries are
  `要人間判断` — no artifact can close them, so more rounds cannot help
- Every remaining `未解決` entry is blocked on access the agent does not have
  (credentials, environment, a private document)
- A round would only re-check what a previous round already settled with
  primary evidence

Never keep looping to reach a satisfying number of findings. An early
convergence on a small ticket is the correct outcome, not a failure.

## Between Rounds

Without `--auto`, end each round with a short Japanese status of 3-5 lines and
then continue, unless the user interrupts:

```
ラウンドN: 訂正X件 / 新規Y件 / 未解決Z件
今回分かった主なこと: (1-2行)
次ラウンドで当たる対象: (1-2行)
```

Do not re-report the whole ledger between rounds. With `--auto`, skip these
entirely and report once at the end.

If a round produces a **訂正 to something the user already acted on** (they
made a decision on an earlier status, or started implementing), say so
immediately rather than waiting for the final report.

## Final Report

Present in Japanese, in the [[issue-recon]] Step 5 format, with these
additions. Omit an empty section rather than padding it.

```
## 実装に必要な情報

(issue-recon の報告フォーマットに従う:
 要件 / 確定した調査結果 / 実装の入り口 / 人間の判断が必要な項目 /
 調査できなかったこと)

### 調査の収束
- ラウンド数と終了理由(収束 / 上限到達 / 判断待ちのみ / アクセス不能)
- 最終ラウンドで訂正・新規がゼロだったこと、または残った未解決の件数

### 途中で訂正された結論
ループ中に答えが変わった項目のみ。「最初こう思ったが」は書かず、
今の答えと、それが以前の理解を覆すものであることだけを1行で書く
```

Report rules:

- **Current state only.** The report describes what is true now. Do not narrate
  the rounds, list what each round found, or explain how an answer evolved.
  The `調査の収束` and `途中で訂正された結論` sections are the entire allowance
  for process, and the latter exists only so the user notices a reversal that
  affects a decision they already made
- Every claim carries evidence as `path:line`, a query, or a URL
- Mark any entry still at `暫定` explicitly as 未確認 rather than presenting it
  as settled
- Human-decision items follow the [[issue-recon]] rules: answerable in one
  line, each with a recommended default

## Notes

- Investigation only. Do not write implementation code, and do not modify the
  ticket
- Scale to the ticket. A small ticket may converge in round 2; run it and say
  so rather than manufacturing a third round
- Do not pull personal or sensitive records into the ledger or the report.
  Shapes, counts, and distributions only
- Live databases are read-only, limited queries, non-production where possible.
  Obtain credentials without exposing their values (see the
  [[keychain-credentials]] skill)
- After the report, offer the next step in Japanese as one line:

  ```
  判断が必要な項目を決めたら、実装に進めますか?
  ```
