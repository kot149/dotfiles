---
name: loop-until-settled
description: >-
  Run any skill or task round after round until it settles, that is, until a
  round produces neither a correction to an earlier result nor a new one. Each
  round re-runs the target aimed only at the weakest results and the still-open
  items, not as a repeat of round 1, and the deliverable is the settled result
  set rather than a log of the rounds.
  Use when asked things like "repeat X until nothing new comes up", "loop this
  until it converges", "run /some-skill until it settles", "keep going until
  there are no corrections",
  「訂正や新しい発見が出なくなるまで繰り返して」「収束するまでやって」
  「/xxx を収束するまで回して」.
  Not for time-interval polling. A recurring task on a wall-clock interval is
  the `loop` skill instead.
argument-hint: "<skill or task> [--max-rounds=N] [--auto]"
---

# Loop Until Settled

Run one target repeatedly until its results stop changing. A single pass
answers what it thought to ask; the loop exists because answering those items
reliably exposes items the first pass could not have phrased, and occasionally
shows that an earlier result was wrong.

The loop ends on **settlement**: a round that produces no correction and no new
item. The deliverable is the settled result set, not a log of the rounds.

This is convergence-driven, not clock-driven. For "every N minutes" use the
`loop` skill.

## Target

$ARGUMENTS

The target is whatever remains after removing the flags below. It is one of:

- **A skill invocation** — `/deep-review #123`, `issue-recon ABC-123`, with or
  without the leading slash. Load that skill and follow its body as the round's
  work
- **A prose task** — "この関数の性能問題を洗い出して", "find every place that
  bypasses the auth middleware". Treat the task itself as the round's work

If the target is empty or names no recognizable skill or task, ask the user what
to loop before doing anything.

| Flag | Effect |
|---|---|
| `--max-rounds=N` | Round cap. Default 5, hard maximum 8 |
| `--auto` | Do not pause between rounds. Run to settlement or the cap, then report once |

Flags the target skill defines are passed through to it untouched. When a flag
name collides, the one appearing after the target name belongs to the target.

## Target Classification

Decide this once, in round 1, and say which it is in the first status line.

- **Read-only target** (investigation, review, audit, search). Rounds produce
  findings. A correction means a finding's answer changed
- **Mutating target** (fix, refactor, apply, rewrite). Rounds produce changes.
  A correction means a previous round's change was wrong or was undone

For a mutating target, additional rules apply:

- Each round's changes must leave the tree in a working state (the project's
  build and tests pass, when it has them) before the round is counted
- Never let a later round silently revert an earlier round's change. If it must
  be reverted, that is a 訂正 and is reported
- Do not commit between rounds unless the user asked for it. One settled result,
  one commit decision
- If the target both investigates and fixes, classify it as mutating

## Capability Mapping

### Subagents

{{ includeTemplate "agents/skills/_shared/subagents.md" . }}

### Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## The Ledger

The loop carries one working document across rounds. Keep it in a scratch file
so it survives context pressure, and treat it as the single source of state.

Each entry:

```
ID | 項目 | 現在の結果 | 根拠 | 確度 | 状態 | 最終更新ラウンド
```

- **項目**: the question, finding, or change this entry tracks
- **根拠**: `path:line`, a query, a command and its output, or a URL. Never a
  subagent's say-so alone
- **確度**: `確定` (primary evidence read directly, or a change verified by
  running it) / `暫定` (one subagent report, unverified) / `未解決`
- **状態**: `解決済` / `調査中` / `要人間判断` / `訂正済`
- An entry is never deleted. A corrected entry keeps its ID and records the new
  result; the old result is dropped, not archived (the final report shows only
  the current state)

If the target skill defines its own result format, map its output onto these
entries rather than replacing the ledger. The target's format governs the final
report; the ledger governs the loop.

## Round 1: Full Pass

Run the target end to end, exactly as it defines itself, with one change:
instead of reporting to the user, write the result into the ledger. Every item
the target produces becomes an entry, including the ones it considers settled.

Round 1 sets the baseline. Do not narrow scope yet — a first round that skips
part of the target's own procedure makes every later round's "new finding"
meaningless.

## Rounds 2..N: Targeted Re-Runs

Each later round is aimed, not a repeat of round 1. Build the round's work list
from the ledger in this priority order, and stop adding when the round has
enough to keep 3-6 subagents busy:

1. **`未解決` entries** — what is still missing, and what other angle would
   settle it
2. **`暫定` entries the outcome hangs on** — re-derive the result from the
   primary source, with a subagent that was not told the previous result
3. **Items implied by round N-1's results** — the real yield of the loop. A
   result that named a new caller, table, flag, code path, or file creates
   items about that thing
4. **Consistency probes** — pick pairs of settled entries that must agree
   (schema vs. code, spec vs. implementation, two callers of one contract, a
   change vs. its tests) and have a subagent check that they actually do
5. **`要人間判断` entries** — re-test the classification once. Most items that
   look undecided are settled by an existing convention

Round rules:

- **Blind re-derivation**: when re-checking a `暫定` entry, give the subagent
  the item and the sources, never the previous result. Told the result, it
  confirms the result
- **Fresh angle**: do not re-run an identical search and call the identical
  output a confirmation. Confirmation requires a different path to the same
  fact (different file, different tool, different direction of the call graph)
- **Spot-check yourself**: read the cited line directly, or run the thing, for
  any entry the outcome depends on. Subagent reports are not primary evidence
- A round that only re-reads what round N-1 already read has produced nothing;
  count it as a no-change round

## Settlement Check

At the end of every round, classify each result as exactly one of:

- **訂正**: an existing entry's result changed
- **新規**: an entry was added, or an entry moved out of `未解決`
- **変化なし**: same result, no new entry

Settled when a round yields zero 訂正 and zero 新規. Report the round count and
stop.

Stop early, before settlement, when any of these hits. Say which one in the
report:

- Round cap reached (`--max-rounds`, default 5)
- Two consecutive rounds where the only remaining open entries are
  `要人間判断` — no artifact can close them, so more rounds cannot help
- Every remaining `未解決` entry is blocked on access the agent does not have
  (credentials, environment, a private document)
- A round would only re-check what a previous round already settled with
  primary evidence
- A mutating target where two consecutive rounds changed the same lines back
  and forth. That is oscillation, not convergence. Stop, keep the state the
  user's own instruction favors, and report the disagreement

Never keep looping to reach a satisfying number of results. An early
settlement on a small target is the correct outcome, not a failure.

## Between Rounds

Without `--auto`, end each round with a short Japanese status of 3-5 lines and
then continue, unless the user interrupts:

```
ラウンドN: 訂正X件 / 新規Y件 / 未解決Z件
今回分かったこと: (1-2行)
次ラウンドで当たる対象: (1-2行)
```

Do not re-report the whole ledger between rounds. With `--auto`, skip these
entirely and report once at the end.

If a round produces a **訂正 to something the user already acted on** (they
made a decision on an earlier status, or started working from it), say so
immediately rather than waiting for the final report.

## Final Report

Present in Japanese. When the target skill defines a report format, use it and
append the two sections below. Otherwise use this shape. Omit an empty section
rather than padding it.

```
## 結果

(対象skillの報告フォーマットに従う。無い場合は
 確定した結果 / 残った未解決 / 人間の判断が必要な項目 / できなかったこと)

### 収束の状況
- ラウンド数と終了理由(収束 / 上限到達 / 判断待ちのみ / アクセス不能 / 振動)
- 最終ラウンドで訂正・新規がゼロだったこと、または残った未解決の件数

### 途中で訂正された結論
ループ中に結果が変わった項目のみ。「最初こう思ったが」は書かず、
今の結果と、それが以前の理解を覆すものであることだけを1行で書く
```

Report rules:

- **Current state only.** The report describes what is true now. Do not narrate
  the rounds, list what each round found, or explain how a result evolved.
  The `収束の状況` and `途中で訂正された結論` sections are the entire allowance
  for process, and the latter exists only so the user notices a reversal that
  affects a decision they already made
- Every claim carries evidence as `path:line`, a query, a command, or a URL
- Mark any entry still at `暫定` explicitly as 未確認 rather than presenting it
  as settled
- Human-decision items are answerable in one line and each carries a
  recommended default

## Notes

- The loop does not expand the target's scope. If the target is read-only, every
  round stays read-only; a round that wants to fix something records it as an
  item and stops there
- Scale to the target. A small target may settle in round 2; run it and say so
  rather than manufacturing a third round
- Do not pull personal or sensitive records into the ledger or the report.
  Shapes, counts, and distributions only
- Live databases are read-only, limited queries, non-production where possible.
  Obtain credentials without exposing their values (see the
  [[keychain-credentials]] skill)
- After the report, offer the next step in Japanese as one line, matched to the
  target (implementation for an investigation, commit for a set of changes)
