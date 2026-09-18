---
name: deep-review
description: Loop-style in-depth code review that runs multiple perspective-specific reviewer subagents in parallel, has judge subagents verify each finding against the real code, then fixes the valid findings and re-reviews. Reviews in 10 independent perspectives (security/quality/naming/comment/perf/a11y/test/arch/meta/spec), also fetching spec documents such as Jira/Confluence from the PR body to check spec consistency. Use when the user asks for "deep review", "review this PR", "review the diff from multiple angles", "review and fix", 「PRをレビュー」「差分を多角的にレビュー」「レビューして修正して」, or requests a review with a PR number or diff range in English or Japanese. Findings can also be posted as pending PR review comments. The `--fix` flag skips the approach selection prompt and auto-fixes, and `--post` similarly proceeds to pending review comment posting (only valid for PR targets).
argument-hint: "[--fast|--full] [--fix|--post]"
---

# Deep Review

Run multiple reviewer subagents in parallel from different perspectives, have judge subagents evaluate validity, fix the valid findings, then repeat the review-fix loop up to 5 times.

Detailed instructions for reviewers and judges live in files next to this SKILL.md. **Do not read them yourself**; pass their absolute paths to subagents, who read them directly. This keeps your own context small.

- `common-rules.md` — rules shared by all reviewers (evidence requirement, false-positive catalog, output format, inventory table)
- `perspectives/<label>.md` — one detailed checklist per perspective
- `judge.md` — judge steps, verification bars, verdict criteria, output format

## Target

$ARGUMENTS

Arguments may specify the target (PR number/URL, branch diff, file paths) plus the following flags.

| Flag | Effect |
|---|---|
| `--fast` | Pin to light mode. Narrow the perspectives regardless of size |
| `--full` | Pin to heavy mode. All perspectives plus thorough verification regardless of size |
| `--fix` | Skip the approach selection prompt in Phase 3b-2 and proceed with option A (auto-fix all VALID findings) |
| `--post` | Skip the approach selection prompt in Phase 3b-2 and proceed with option E (post pending review comments). If the review target is not a PR, warn that this is an invalid argument, ignore it, and proceed to the normal selection prompt |

If both `--fix` and `--post` are given, treat it as the user explicitly requesting "do both posting and fixing" as described for option E, and run both in the order Phase 4b (post) then Phase 4 (fix).

Neither flag substitutes for the additional selections on meta/spec findings (M1-M3 / S1-S4). If such findings remain, prompt for those selections normally.

## Design Premises

- Reviewers and judges are delegated to **subagents** (child agents with independent contexts)
- Each subagent returns a final response text. The orchestrator (you) parses that string directly
- Reviewers and judges only read code, so use **read-only** subagents
- Fixes are always made by the orchestrator itself (never let subagents rewrite files)

### How to Launch Subagents

Translate into whatever means the running agent has.

- Claude Code: the `Agent` tool. Use `subagent_type: "Explore"` for read-only roles, and batch multiple `Agent` calls in one message to run them in parallel
- Codex CLI: issue as many `spawn_agent` calls as needed, then `wait` (`features.multi_agent` required. Pick read-only roles from `[agents]` in `config.toml`)

On any agent, satisfy all of the following:

- Subagents do not inherit conversation history. Include every shared premise explicitly in the prompt
- **Do not pass conversation context (narratives like "I wrote it this way with such intent" from the ongoing work)**. Passing it lets them reuse it as a reason not to flag things. The only things you may pass are primary sources (PR body, tickets, convention documents, in-code comments)
- Do not let subagents rewrite files. On agents that cannot restrict to read-only, state the prohibition explicitly in the prompt
- Sections marked "launch in parallel" must be launched together with the agent's parallel execution means. On agents with no parallel means, fall back to sequential execution and note that in the report in Japanese (e.g. `注: 並列実行手段がないため逐次実行にフォールバックしました`). Control the parallelism cap by the number of subagents launched at once

## Selection Prompts to the User

Every place in this document that says "selection prompt" means presenting options and letting the user choose. On agents with a selection UI tool (such as `AskUserQuestion`) use it; on agents without one, present the same options as a numbered plain-text list and have them answer by number or free text. In either case, do not proceed until you get an answer.

## Reviewers (10 Perspectives)

Each label's detailed checklist is in `perspectives/<label>.md`. This table is only for mode selection and aggregation.

| Label | Perspective |
|---|---|
| security | Injection, authn/authz, secret exposure, input validation, XSS/CSRF, crypto |
| quality | Readability, error handling, silent degradation and observability, recoverability, DRY, immutability |
| naming | Truthful names, collisions with existing code, consistent wording, scope-appropriate detail, counterpart symmetry |
| comment | Redundant/missing comments per [[trim-comments]], meta-comments, statement-vs-reality consistency |
| perf | N+1, complexity, memory, re-renders, bundle size, caching, blocking I/O |
| a11y | WCAG 2.2 AA: semantics, ARIA, keyboard, focus, screen readers, contrast |
| test | Mutation checks, boundary values, brittle tests, excessive mocking, valueless-test deletion |
| arch | Layer violations, dependency direction, cycles, interface design, backward compatibility, counterpart asymmetry |
| meta | YAGNI, simpler alternatives, scope, incremental shipping, existing assets, tech choice |
| spec | Spec-vs-implementation consistency and validity of the spec itself (Jira/Confluence/PRD linked from the PR body) |

## Phase 0: Preparation

### 0.0 Resolve the Skill Directory

Set `$SKILL_DIR` to the absolute path of the directory containing this SKILL.md (the root of this skill in whichever skill store it was loaded from). All file references passed to subagents below use `$SKILL_DIR/...` absolute paths.

### 0.1 Identify the Review Target

Decide the target from the contents of `$ARGUMENTS`, and **save the diff to a temp file and pass the path to subagents** (do not inline it into prompts; summarization loses information).

- PR number/URL given: `gh pr diff <number> > /tmp/deep-review-<target>.diff`. In the same call also take `gh pr view <number> --json title,body,url,additions,deletions,changedFiles,headRefName,baseRefName,state,isDraft,author,headRefOid,files`
- Branch diff given: write `git diff <base>...<head>` to a temp file. Also take `git log --oneline <base>..<head>` and `git diff --stat` at the same time
- File paths given: use those paths as the target list (no diff)
- Unspecified: write `git diff HEAD` to a file. If the diff is empty, use `git diff HEAD~1`

Variables to keep: diff file path as `$DIFF_PATH`, changed file list as `$FILES`, change intent as `$PURPOSE`, full 40-char commit SHA as `$SHA`.

Only diffs under 100 lines may be embedded directly into prompts. Anything larger must be passed by path, with an instruction to "read the target files directly for the review".

### 0.2 Acceptance Check

This is not a gate for refusing reviews. The default is to **state the verdict in one line in Japanese and continue**.

| State | Handling |
|---|---|
| Already merged / closed | Continue with a note in Japanese: `注: このPRは既にマージ済みのため、事後レビューとして続行します` |
| Auto-generated PR from a dependency bot etc. | Pin to light mode |
| Changes are only generated artifacts, lockfiles, or formatting | Pin to light mode and state in Japanese that generated artifacts are excluded from findings (e.g. `注: 生成物は指摘対象外とします`) |
| `isDraft` | Continue but note in Japanese (e.g. `注: ドラフトのため未完成部分を前提とします`) |
| 0-line diff | Do not review; report in Japanese (e.g. `差分が0件のためレビューを終了します`) and finish |

### 0.3 Mode Decision

Decide the mode from size. An explicit `--fast` / `--full` takes precedence.

| Mode | Condition (guideline) | Reviewers | Judge split |
|---|---|---|---|
| Light | Under 300 changed lines and 8 or fewer files | 6 perspectives: security / quality / naming / comment / test / spec (add a11y if there are UI changes) | Max 4 parallel |
| Standard | Larger than above, within 1500 lines / 30 files | All 10 perspectives | Follow the split strategy below |
| Heavy | Over 1500 lines or over 30 files | All 10 perspectives | Prefer finding-count splitting, max 8 parallel |

**When the size is near a mode boundary, pick the lighter mode.** Use `--full` only when you want a thorough look. Log the chosen mode in one line in Japanese (e.g. `モード: Light（変更XXX行 / Xファイルのため）`).

### 0.4 Locate Convention Documents (Do Not Read the Contents)

Only resolve paths. Reading the contents is the subagents' job.

- Coding conventions / instruction files: repo-root `CLAUDE.md` / `AGENTS.md`, `CLAUDE.md` in the directory of changed files, `.claude/rules/*.md`
- Naming conventions, architecture conventions, design decision records: `docs/architecture/`, `docs/adr/` / `adr/`, `docs/**/naming*`, and the directory layout itself that reveals layer structure (first level under `src/`)
- Review comment label conventions: `CONTRIBUTING.md`, `.github/`, `docs/**/code_review*`

**Pass both the paths found and the fact that some were not found.** If there are no conventions, the only basis later is "measured majority patterns in existing code". Without telling reviewers this, they start writing generic advice.

### 0.5 Fetch Existing Review Comments (Mandatory for PR Targets)

```sh
gh api "repos/<owner>/<repo>/pulls/<PR>/comments?per_page=100" \
  --jq '.[] | "\(.user.login) \(.path):\(.line // .original_line)\n\(.body[0:300])\n"'
```

Summarize and pass to all reviewers as `$EXISTING_COMMENTS`. Three purposes:

1. **Avoid duplicates** — do not repeat what is already flagged
2. **Calibrate perspective** — see what the team treats as a problem, and the granularity and evidence style of findings
3. **Judge whether already fixed** — the current HEAD may already reflect existing reviews. Reading it blind misreads it as "well done"

Do not resurrect resolved threads. Points that were flagged but only half-addressed may be picked up as remaining issues.

### 0.6 Identify Symmetric Counterparts

Check whether the change target has a **counterpart implementation**, and if so pass its path as `$SYMMETRY` to the naming / arch reviewers.

| Symmetry type | How to find |
|---|---|
| read / write, get / set | Search for `_read_` <-> `_write_` filename pairs |
| create / update / delete | Handlers/models with the same prefix |
| Types sharing a base | Search by base class name |
| Same role in a different feature | Files at the same position in the directory layout |

**Record "none" when there is no counterpart** (it becomes the reason the comparison was skipped).

### 0.7 Fetch Linked Spec Documents

Extract the following links from the PR body (`$PURPOSE`), fetch their contents, and keep them as `$SPEC_DOCS`.

- Use the tools of a connected MCP server. Tool names differ per agent; on agents with lazy loading, load the tool definitions first
- Jira issues (`*.atlassian.net/browse/XXX-###`, keys in `ABC-123` form): fetch body + comments with the Atlassian MCP issue-fetch tool
- Confluence pages (`*.atlassian.net/wiki/...`): fetch the body with the Atlassian MCP page-fetch tool
- Google Docs/Drive (`docs.google.com`, `drive.google.com`): fetch with the Google Drive MCP file-content tool (if permitted)
- Notion (`notion.so/...`): fetch with the Notion MCP
- Other PRD/design/Figma/Slack/Lucid links: fetch with the corresponding MCP tool where possible. If there is no matching tool or fetching fails, record "link confirmed only, body not fetched"
- Summarize each fetched document as `title`, `url`, `body` (an excerpt of the key parts is fine)
- If **no spec documents are found at all**, set `$SPEC_DOCS = "(no linked spec documents)"`

### 0.8 Permalink Format

`file:line` alone takes effort to verify. Assemble the format and pass it to all subagents.

```
https://github.com/<owner>/<repo>/blob/<full 40-char SHA>/<path>#L<start>-L<end>
```

- **Use the full 40-char SHA.** Short SHAs, branch names, and unexpanded command substitutions like `$(git rev-parse HEAD)` produce broken links
- Include one line of context on each side of the range (to flag line 3, use `#L2-L4`)
- For local diffs / file-specified targets where no SHA can be determined, omit permalinks and keep `file:line`

### 0.9 Initialize Loop Counter

`ROUND=1`, `MAX_ROUNDS=5`

## Phase 1: Parallel Detail Review

Launch reviewer subagents for the mode-selected perspectives **in parallel** (10 including meta in standard/heavy mode, 6-7 in light mode), all together in one batch. Avoid launching them one by one in sequence (it serializes and slows down). Each subagent has an independent context.

Start each subagent as `<perspective> review round $ROUND` with this prompt. Keep it this short; the detail lives in the files the subagent reads.

```
You are the "<perspective>" reviewer in a multi-perspective code review.

First read these two files and follow both:
1. $SKILL_DIR/common-rules.md — shared rules (evidence requirement, false-positive catalog, finding output format, mandatory CHECKLIST inventory table)
2. $SKILL_DIR/perspectives/<perspective>.md — your detailed checklist and perspective-specific instructions

Then review the change. Read $DIFF_PATH yourself, and read the target file bodies as needed. Do not edit any files.

Change intent: $PURPOSE
Changed files: $FILES
Target diff: $DIFF_PATH
Convention document paths: <path list found in 0.4, or the fact that none was found>
Existing review comments: $EXISTING_COMMENTS
Permalink format: <format from 0.8>
```

Per-perspective additions to the prompt:

- `naming` / `arch`: add `Counterpart: $SYMMETRY` (path, or "none")
- `spec`: add `Linked spec documents: $SPEC_DOCS`
- `meta` / `spec`: their perspective files define their own FINDING formats; no extra prompt text needed

## Phase 2: Collect & Aggregate

**Critical**: do not proceed to the next phase until **all** launched subagents are done. Advancing to Phase 3 or later while any reviewer is still outstanding is prohibited. The orchestrator withholds judgment until all results are in.

Once all results are in:

1. Parse each reviewer's reply, extracting `FINDING` blocks and the `CHECKLIST` table
2. **Merge the inventory tables** — combine all reviewers' CHECKLIST rows into one table and keep it. Present it to the user in Phase 3b-1. Perspectives excluded by light mode are recorded orchestrator-side as "out of scope due to light mode"
3. If everyone said "LGTM", report that to the user in Japanese (e.g. `全観点LGTMでした`) with the merged inventory table and finish. **Do not return bare "no issues" without the table** (approvers need to see what was and was not examined)
4. Otherwise aggregate the findings. Tag each finding with `reviewer: <label>` and list them

### Under-Reporting Guard

The false-positive catalog exists to reduce false positives, not to reduce findings. Suspect over-suppression when any of the following hits.

- **About to finish with 0 CRITICAL / HIGH findings** — check the merged inventory table for rows still marked "not examined". If any remain, relaunch just those perspectives
- **A CHECKLIST "not applicable" row has no reason written** — relaunch that perspective
- **A counterpart really exists but the naming / arch table shows no comparison record** — an asymmetry miss is certain. Relaunch

Relaunch at most once per perspective.

### Severity Calibration (Orchestrator's Job)

Do not use reviewer-declared severities as-is. Compare all findings across perspectives and reassign using the following rubric. **Cross-perspective calibration can only be done by one party seeing everything.**

| Finding content | severity |
|---|---|
| Crash on a reachable path / data loss or corruption / security vulnerability / fatal misbehavior | CRITICAL |
| Correctness issue but with limited impact | HIGH |
| Violation of a rule stated in a convention document (quotable) | HIGH |
| Layer crossing / dispersed domain where fixing only one side causes a concrete divergence accident | HIGH |
| Name-vs-reality mismatch (a getter-sounding name that mutates, misleading readers into breaking things) | HIGH |
| Public contract promises something the implementation cannot deliver (on a reachable path) | HIGH |
| Concrete mutation shown where "breaking it still passes existing tests" | HIGH |
| Unexpected state silently falling back to a default with no operational means to notice | HIGH |
| Existing callers that really exist and break under the contract change (count shown) | HIGH |
| Same mismatch but on a not-yet-reachable path (unimplemented, 501, etc.) | LOW (note "needed at wiring time") |
| No convention, but deviates from the measured majority of existing code (majority shown with measurements) | MEDIUM |
| Logging exists but granularity/aggregation policy differs from similar processing | MEDIUM |
| Stale prose where a misunderstanding breaks nothing (e.g. outdated line-number references) | LOW |
| Not caused by this PR, or issues on unchanged lines | LOW |

- **Findings rooted in design/naming/architecture must not be CRITICAL** (cap at HIGH). If it manifests as a reachable defect, it is not a design discussion; security / quality should have raised it as a correctness issue
- **When torn between two severities, pick the lower.** Mass-produced CRITICALs destroy the priority order itself

## Phase 3: Judge Findings (Multiple Parallel Subagents)

Always split judges into **multiple parallel subagents**. Passing all findings to a single subagent shallows how deeply it reads code per finding, increasing misjudgments (missed false positives / valid issues ruled INVALID).

### Split Strategy

Pick the split policy from the aggregated finding count `N`. Launch **all judges in parallel** either way.

1. **Split by perspective (default, N <= 24)** — one judge per reviewer label:
   - Up to 10 parallel: `judge-<label>` per perspective (round down to max 4 parallel in light mode)
   - Do not launch judges whose label has 0 findings
   - Each judge examines only its own perspective's findings, so it is easy to focus on which code to read
2. **Split by finding count (N > 24, or 10+ findings concentrated on one perspective)** — chunk the findings:
   - Aim for 5-8 findings per chunk (keep findings on the same file in the same chunk)
   - Up to 8 parallel chunks. For N > 64, assign across 8 parallel judges with ceil(N/8) findings each
   - Even when chunking, keep `spec` and `meta` in independent chunks, never mixed with other perspectives (different evaluation axes)
3. **Cross-check (optional, for high-importance PRs)** — additionally pass all findings to one meta-judge and compare against the perspective judges. Findings where they disagree are shown separately at user-presentation time as "findings where judges disagreed"

Right after aggregating findings in Phase 2, the orchestrator computes N, picks a split policy from the above, and **logs which policy was adopted in Japanese** (e.g. `ジャッジ分割: 観点別（N=XX）` / `ジャッジ分割: 件数分割（N=XX、Xチャンク）`).

### Judge Prompt

Launch each judge as `judge <perspective or chunk#> round $ROUND` with the following prompt.

```
You are a judge scrutinizing code review findings.

First read $SKILL_DIR/judge.md and follow it exactly (mandatory steps, verification bars per claim type, false-positive catalog, verdict criteria, output format). Do not edit any files.

Assigned findings:
<Paste the chunk's findings here>

Reference info:
- Changed file list: $FILES
- Change intent: $PURPOSE
- Target diff: $DIFF_PATH
- Convention document paths: <path list found in 0.4>
- Existing review comments: $EXISTING_COMMENTS
- Linked spec documents (spec judges only): $SPEC_DOCS
```

### Aggregating Results

- Do not advance to Phase 3b until all judge subagents have returned
- Parse each judge's output and merge into one list
- Findings with `EVIDENCE: UNVERIFIED` get an **"unverified" mark by default at user-presentation time**. For CRITICAL/HIGH ones, re-submit just those findings to a different subagent for re-judgment (max once)
- Merge DUPLICATE verdicts into the merge target by following `DUPLICATE_OF`
- With the cross-check policy, diff the perspective judges against the meta-judge and separately list "findings with split opinions"

## Phase 3b: User Confirmation (Whether to Proceed to Fixes)

**Always confirm with the user before fixing**. Unless `ALL_CLEAR`, never skip this phase regardless of judge results.

### Strict Rules (Entire Phase 3b)

**Presenting the review results before the approach selection prompt is strictly mandatory.** Two bugs of the same kind happened in the past:

- Bug 1: asked for the approach without showing review results
- Bug 2: output the list text, then inserted a dummy tool call (e.g. just running `true`) before the selection prompt. Text wedged between tool calls may not be shown to the user, so this equals "selection prompt without showing the list"

Always keep this order:

1. First, as Phase 3b-1, output the full list of VALID findings as **normal response text (Markdown), and end the turn with that text as the final output**. After the list text, **make no tool calls of any kind** (neither the selection prompt nor dummy command runs as a message-splitting workaround)
2. In **a later turn after the user reacts** to the list, run the Phase 3b-2 selection prompt. If the user's response already states the approach (e.g. "fix them all"), you may skip the selection prompt and follow that instruction

**"List plus selection prompt in the same turn" is prohibited no matter what is wedged between.** A list presentation counts as complete only when the turn fully ends and hands the user a chance to read.

Exception: with `--fix` / `--post` the main approach is already fixed, so Phase 3b-2 is execution of a decided policy rather than a selection prompt, and may follow in the same turn as the list (except when meta/spec additional selections are needed).

### Phase 3b-1: Present the VALID Finding List (Unconditional, Mandatory, End Turn)

**Before any selection prompt, always run this step and end the turn with the list text.** Even with 0 VALID findings, explicitly tell the user in Japanese (e.g. `VALID指摘は0件です`). Skipping this step to jump to a selection prompt is prohibited.

Output the following as normal text (Markdown). Write all user-visible headings and body in Japanese:

1. The **complete list** of judge-VALIDated findings (reviewer / severity / file:line / title / description / suggestion in a table or bullets, omitting none) under the heading `## レビュー結果（VALID XX件）`
   - Mark `EVIDENCE: UNVERIFIED` ones explicitly with an "unverified" mark in Japanese (e.g. `未検証`)
   - Sort by severity (CRITICAL -> HIGH -> MEDIUM -> LOW)
   - For PR targets with a SHA available, attach permalinks (format from 0.8)
2. Counts only (for reference) of findings excluded as INVALID/DUPLICATE, under the heading `## 除外件数`
3. **Points checked and found fine** — include the Phase 2 merged inventory table as "what was examined / result" under the heading `## 確認済み・問題なし`. Never omit it even with many findings. Approvers need to read "what was and was not examined"
4. If there are meta findings, show them in a separate section under the heading `## アプローチ指摘（meta）` (with CATEGORY and proposal)
5. If there are spec findings, also show them in a separate section under the heading `## 仕様整合性（spec）` (with CATEGORY / SPEC_REF / FIX_TARGET). Highlight `FIX_TARGET=SPEC` ones in particular in Japanese as `仕様側の修正が必要`
6. When run in light mode, state the excluded perspectives in Japanese under the heading `## 対象外観点（Lightモード）`

**No history**: write only the final verdict per finding. Do not write process details like severity raises/lowers, judge re-verdicts, or changes since previous rounds in the list or the final report (e.g. notes like "severity was lowered from HIGH to LOW" are unnecessary).

End the list text with a single line in Japanese moving toward approach confirmation (e.g. `上記のVALID指摘への対応方針をお知らせください`), then **end the turn**.

### Phase 3b-2: Confirm the Approach

With `--fix` / `--post` given, skip the main-policy (A/B/E) selection prompt and treat them as option A / option E respectively. `--post` is only valid when the review target is a PR; for non-PR targets warn in Japanese (e.g. `` `--post`はPR以外の対象では無効です``), ignore it, and prompt normally. Even with a flag-fixed main policy, still prompt normally for meta/spec additional selections (M1-M3 / S1-S4) when needed.

Without flags, in the **turn after receiving the user's response** to the Phase 3b-1 list, present the following options in Japanese (you may skip this selection prompt if the user's response already states the policy):

```
今回のVALID指摘への対応方針を選んでください：

A. VALID指摘をすべて自動修正する（CRITICAL/HIGHは必須、MEDIUMは可能な範囲、LOWは報告のみ）
B. 修正する指摘を選ぶ（番号を指定）
E. VALID指摘をPRレビューコメントとして投稿する（Phase 4bへ。pending状態のインラインコメント。PR対象時のみ提示）

VALID meta指摘が残っている場合、追加で：
  M1. アプローチ変更を受け入れて修正に含める
  M2. アプローチを維持する（meta指摘はスキップ）
  M3. アプローチ再検討のため中断する（終了）

VALID spec指摘が残っている場合、追加で：
  S1. 実装を仕様に合わせる（コード修正）
  S2. 仕様を実装に合わせる（仕様側の修正が必要 — オーケストレーターは仕様を更新せず、「仕様の改訂が必要」として報告する。Jira/Confluenceの編集権限がある場合、別途ユーザー確認の上で更新を提案する）
  S3. spec指摘をスキップする（実装・仕様とも現状維持）
  S4. 仕様自体の再検討が必要なため中断する（終了）
```

Accept the user's selection. When multiple questions are needed (fix policy + meta policy), ask them together at once.

Follow the user selection:
- A / B / M1 / S1: to Phase 4 (Fix)
- E: to Phase 4b (Post Pending PR Review). After posting, report the result in Japanese and finish (no fixes. Only when the user explicitly wants both posting and fixing, run post-then-fix in that order)
- M3 / S4: report the abort reason in Japanese and finish
- M2 / S3: skip only the applicable findings and follow the other findings' fix policy (A/B/E)
- S2: do not touch the implementation; include in the final user report in Japanese under the heading `## 仕様の改訂が必要` (no automatic spec-doc updates)

## Phase 4: Fix Valid Findings

Only findings the user chose to fix in Phase 3b.

1. Fix granularity follows the user selection:
   - Option A (all auto): CRITICAL/HIGH required, MEDIUM where possible, LOW report-only
   - Option B (individual): only the finding numbers the user specified
   - With M1 selected, include the meta findings
2. The orchestrator (you) edits files directly to fix. Never let subagents rewrite
3. After fixes, `ROUND++`
4. If `ROUND > MAX_ROUNDS`, report a summary of the fixes in Japanese as max-rounds reached (e.g. `上限5ラウンドに到達したため終了します`) and finish
5. Otherwise update `$DIFF_PATH` with `git diff HEAD` and return to Phase 1 (confirm with the user in Phase 3b again before the next round's review)

**Also confirm whether to proceed to the next round**: after fixes, confirm via selection prompt in Japanese whether to re-review or finish:

```
Round $ROUND の修正が完了しました。次の手順を選んでください：
1. 再レビューする（次ラウンドへ）
2. 終了する
```

## Phase 4b: Post Pending PR Review

Run only when the user picked option E in Phase 3b. Delegate the posting procedure to the [[pending-review-comments]] skill. That skill owns the procedure, pending-state rules, and error handling.

As deep-review-side preconditions, prepare the inputs to the skill as follows:

- **Only judge-VALIDated findings**. Never pass INVALID/UNCERTAIN ones
- Pass each finding with `FILE` / `LINE` / title / `DESCRIPTION` / `SUGGESTION` / `<reviewer>` / `<SEVERITY>` aligned. Label each comment head as `[<reviewer> / <SEVERITY>]` (e.g. `[quality / LOW]`)
- Include the evidence (convention-document quotes, measured breakdowns) in the comment body for findings that have it
- For non-PR targets (local diffs or file-specified), do not offer option E in the first place. Same when `--post` was given (see Phase 3b-2)

After posting, report the result in Japanese (e.g. `pendingコメントを投稿しました`) and finish. No fixes (for both posting and fixing, only when the user explicitly says so, in post-then-fix order).

## Error Handling

- **Subagent response parse failure**: skip that reviewer for that round only and continue. If the same reviewer is unparsable for 2 consecutive rounds, exclude it from later rounds on
- **No CHECKLIST returned**: restart that reviewer once. If still missing on the second try, record "no inventory table" in the merged table and continue (do not silently fill it in)
- **No applicable a11y**: expect LGTM from a11y when there are no UI changes
- **No applicable test**: expect at most "recommend adding tests"-level findings from test when no test files changed
- **Judge timeout/failure**: no verdict material, so do not drop findings; treat all findings as VALID and proceed to fixes
- **Subagent ignoring the specified format**: loosely match `FINDING:` lines in the reply to extract. If nothing is extractable, discard that reviewer's result
- **Existing review comment fetch failure**: on permission/API failure, state "existing comments not fetched" to all reviewers and continue, and also write that fact in the final report in Japanese (e.g. `注: 既存レビューコメントを取得できませんでした（重複を含む可能性あり）`) (duplicate findings may be mixed in)
- **No convention documents found**: pass that fact to reviewers. Also tell them the only evidence is measured majority patterns in existing code
- **Spec document fetch failure**: on permission failure/bad URL/unconnected MCP, set `$SPEC_DOCS = "(link fetch failed, URLs only: <urls>)"` and continue; the spec reviewer caps its findings at MEDIUM
- **Subagent cannot read `$SKILL_DIR` files**: fall back to inlining the applicable file's content into that subagent's prompt (read it yourself only in this fallback case)
