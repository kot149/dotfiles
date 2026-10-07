---
name: deep-review
description: In-depth code review that runs multiple perspective-specific reviewer subagents in parallel, has judge subagents verify each finding against the real code, then fixes the valid findings. Reviews in 10 independent perspectives (security/quality/naming/comment/perf/a11y/test/arch/meta/spec), also fetching spec documents such as Jira/Confluence from the PR body to check spec consistency. Use when the user asks for "deep review", "review this PR", "review the diff from multiple angles", "review and fix", 「PRをレビュー」「差分を多角的にレビュー」「レビューして修正して」, or requests a review with a PR number or diff range in English or Japanese. Findings can also be posted as pending PR review comments. The `--fix` flag skips the approach selection prompt and auto-fixes, and `--post` similarly proceeds to pending review comment posting (only valid for PR targets).
argument-hint: "[<PR number|PR URL|base...head|paths>] [--fast|--full] [--fix] [--post]"
---

# Deep Review

Run multiple reviewer subagents in parallel from different perspectives, have judge subagents evaluate validity, then fix the valid findings.

Detailed instructions for reviewers and judges live in files next to this SKILL.md. **Do not read them yourself**; pass their absolute paths to subagents, who read them directly. This keeps your own context small.

- `common-rules.md`: rules shared by all reviewers (evidence requirement, false-positive catalog, output format, inventory table)
- `perspectives/<label>.md`: one detailed checklist per perspective
- `judge.md`: judge steps, verification bars, verdict criteria, output format

## Token Discipline

The run launches up to 20 subagents. Everything you paste into a prompt is emitted once per subagent, and everything a subagent returns lands in your context. Hold to these rules throughout:

- **Shared premises go into one context file** (`$CTX_PATH`, written once in Phase 0.7). Prompts carry only paths and the per-subagent payload. Never paste the diff, PR body, existing comments, or spec documents into a prompt
- **Bulky fetch results go straight to files** (`gh ... > file`, `--jq` truncation) instead of through your context
- **Repository searches in Phase 0 are delegated** to one prep subagent so their raw output never enters your context
- Subagents return only what you need to aggregate; their output formats are already minimal. Do not ask them for extra narrative

## Target

The request may specify the target (PR number/URL, branch diff, file paths) plus the following flags.

| Flag | Effect |
|---|---|
| `--fast` | Pin to light mode regardless of size |
| `--full` | Pin to heavy mode regardless of size |
| `--fix` | Main policy fixed to option A (auto-fix all VALID findings); the Phase 3b-2 A/B/E prompt is skipped |
| `--post` | Main policy fixed to option E (post pending review comments). PR targets only: otherwise warn in Japanese (`` `--post`はPR以外の対象では無効です``), ignore it, and prompt normally |

Both `--fix` and `--post`: run Phase 4b (post) then Phase 4 (fix). A fixed main policy never replaces the meta/spec additional selections (M1-M3 / S1-S4); prompt for those normally when such findings remain.

## Design Premises

- Reviewers and judges are delegated to **subagents** (child agents with independent contexts)
- Each subagent returns a final response text. The orchestrator (you) parses that string directly
- Every role in this skill (reviewers, judges, the prep helper) only reads
- Fixes are always made by the orchestrator itself (never let subagents rewrite files)

### How to Launch Subagents

{{ includeTemplate "agents/skills/_shared/subagents.md" . }}

Two things this skill adds on top:

- Every shared premise lives in `$CTX_PATH`; make sure each prompt points at it
- When falling back to sequential execution, note that in the report in Japanese (e.g. `注: 並列実行手段がないため逐次実行にフォールバックしました`). Control the parallelism cap by the number of subagents launched at once

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Reviewers

There are 10 perspectives. Each label's detailed checklist is in `perspectives/<label>.md`. This table is only for mode selection and aggregation.

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

### 0.0 Resolve Directories

- `$SKILL_DIR`: absolute path of the directory containing this SKILL.md (the root of this skill in whichever skill store it was loaded from). All file references passed to subagents use `$SKILL_DIR/...` absolute paths
- `$CTX_DIR`: a fresh scratch directory for this run (`mktemp -d "${TMPDIR:-/tmp}/deep-review.XXXXXX"`). Remember the printed path; shell state does not persist between commands. Files created there:
  - `diff.patch` (`$DIFF_PATH`)
  - `existing-comments.txt`
  - `spec-docs.md` (`$SPEC_PATH`)
  - `context.md` (`$CTX_PATH`)

### 0.1 Identify the Review Target

Decide the target from the user's request. **Always write the diff to `$DIFF_PATH` and pass the path**; never inline a diff into a prompt, however small.

- PR number/URL given: `gh pr diff <number> > $DIFF_PATH`. In the same call also take `gh pr view <number> --json title,body,url,additions,deletions,changedFiles,headRefName,baseRefName,state,isDraft,author,headRefOid,files`
- Branch diff given: write `git diff <base>...<head>` to `$DIFF_PATH`. Also take `git log --oneline <base>..<head>` and `git diff --stat` at the same time
- File paths given: use those paths as the target list (no diff)
- Unspecified: write `git diff HEAD` to `$DIFF_PATH`. If the diff is empty, use `git diff HEAD~1`. Untracked files (`git status --porcelain` lines starting with `??`) do not appear in the diff; add them to `$FILES` marked "(untracked: read whole)"

Variables to keep: changed file list as `$FILES`, change intent (PR title + body, or commit log plus the stated intent) as `$PURPOSE`, full 40-char commit SHA as `$SHA`.

For PR targets, also record whether the PR's `headRefName` is checked out locally (`git branch --show-current`). Fixing in Phase 4 requires it; if it is not, note that in Japanese at this point (e.g. `注: PRブランチが未チェックアウトのため、修正フェーズでは先にチェックアウトが必要です`) so the user is not surprised later.

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

### 0.4 Fetch Existing Review Comments

Mandatory for PR targets. Use GraphQL rather than the REST comments endpoint: only review threads carry the resolved state, and the resolved state is what decides whether a point may be raised again. **Write the result straight to `$CTX_DIR/existing-comments.txt`**; the `--jq` filter already truncates bodies, so you never hold the full comment bodies yourself. Read back only the line count.

```sh
gh api graphql -F owner='<owner>' -F repo='<repo>' -F pr=<PR> -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          isResolved isOutdated path line
          comments(first: 20) { nodes { author { login } body } }
        }
      }
      comments(first: 100) { nodes { author { login } body } }
      reviews(first: 50) { nodes { author { login } state body } }
    }
  }
}' --jq '
  def short: .[:300] | gsub("\\s+"; " ");
  .data.repository.pullRequest |
  (.reviewThreads.nodes[] |
    "\(if .isResolved then "resolved" else "open" end) \(.path):\(.line // "-") " +
    ([.comments.nodes[] | "\(.author.login): \(.body | short)"] | join(" | "))),
  (.comments.nodes[] | "conversation \(.author.login): \(.body | short)"),
  (.reviews.nodes[] | select(.body != "") | "review(\(.state)) \(.author.login): \(.body | short)")
' > "$CTX_DIR/existing-comments.txt"
```

The file serves three purposes for reviewers and judges:

1. **Avoid duplicates**: do not repeat what is already flagged
2. **Calibrate perspective**: see what the team treats as a problem, and the granularity and evidence style of findings
3. **Judge whether already fixed**: the current HEAD may already reflect existing reviews. Reading it blind misreads it as "well done"

Resolved threads are never resurrected. Open threads whose point is only half-addressed in the current HEAD may be picked up as remaining issues.

### 0.5 Prep Subagent

Delegate the three lookups below (convention documents, symmetric counterparts, linked spec documents) to **one read-only subagent** (`prep`) so the search output stays out of your context. Launch it right after 0.1 and let it run while you do 0.2 to 0.4. Its prompt:

```
You are the "prep" helper for a multi-perspective code review. Read-only: do not edit any files. Return exactly the three sections below, tersely, and nothing else.

Repository root: <absolute path>
Changed files: $FILES
Change description (contains links to spec documents, if any):
<$PURPOSE>

## CONVENTION_PATHS
List the paths that exist among: repo-root CLAUDE.md / AGENTS.md; CLAUDE.md in the directories of the changed files; .claude/rules/*.md; docs/architecture/, docs/adr/, adr/, docs/**/naming*; CONTRIBUTING.md, .github/ review guidelines, docs/**/code_review*. Also state the first-level directory layout under the main source root (it reveals layer structure). If none of the convention files exist, write "none found".

## SYMMETRY
Check whether the changed code has a counterpart implementation: read/write or get/set filename pairs, create/update/delete handlers with the same prefix, types sharing a base class, or a file at the same position in another feature's directory. Report the counterpart path(s) with one line on how they pair, or "none".

## SPEC_DOCS
Extract spec-document links from the change description: Jira issues (*.atlassian.net/browse/XXX-###, keys like ABC-123), Confluence (*.atlassian.net/wiki/...), Google Docs/Drive, Notion, and other PRD/design/Figma/Slack/Lucid links. Fetch each with the matching MCP server's read tool (Atlassian issue/page fetch, Google Drive file content, Notion page fetch; load tool definitions first if the agent loads them lazily). For Jira include the comments. For each document write:
- title / url
- verbatim quotes of the requirements, acceptance criteria, field/error names, and constraints that an implementation could be checked against (skip boilerplate, greetings, and unrelated comments)
If a fetch fails or no tool matches, write "link confirmed only, body not fetched: <url>". If the description has no such links, write "(no linked spec documents)". If MCP tools are unavailable to you entirely, write "MCP unavailable" and list the URLs.
```

When the reply arrives:

- Write the `SPEC_DOCS` section to `$SPEC_PATH` as-is. If it says "MCP unavailable", fetch the listed URLs yourself with the MCP tools and write the same title / url / verbatim-quotes shape to `$SPEC_PATH`; on failure write `(link fetch failed, URLs only: <urls>)`
- Keep `CONVENTION_PATHS` and `SYMMETRY` for the context file. **A "none found" / "none" is passed on as such**: without conventions the only basis later is measured majority patterns in existing code, and without a counterpart the naming / arch comparison is recorded as skipped for that reason. Omitting the fact makes reviewers write generic advice

### 0.6 Permalink Format

`file:line` alone takes effort to verify. Assemble the format for the context file.

```
https://github.com/<owner>/<repo>/blob/<full 40-char SHA>/<path>#L<start>-L<end>
```

- **Use the full 40-char SHA.** Short SHAs, branch names, and unexpanded command substitutions like `$(git rev-parse HEAD)` produce broken links
- Include one line of context on each side of the range (to flag line 3, use `#L2-L4`)
- For local diffs / file-specified targets where no SHA can be determined, the format is `none (file:line only)`

### 0.7 Write the Context File

Write `$CTX_PATH` once, in this shape. Every reviewer and judge reads it; the field names are the ones the perspective files refer to as `$NAME`.

```
# deep-review context
MODE: Light|Standard|Heavy
PURPOSE: <PR title and body, or commit log plus stated intent, verbatim>
FILES: <changed files, one per line; untracked ones marked "(untracked: read whole)">
DIFF_PATH: <$DIFF_PATH, or "none (file targets)">
CONVENTION_PATHS: <paths, one per line> | none found (only evidence: measured majority patterns in existing code)
EXISTING_COMMENTS: <path to existing-comments.txt> | not a PR | not fetched: <reason> (duplicates possible)
SYMMETRY: <counterpart path(s) and pairing> | none
SPEC_DOCS: <$SPEC_PATH> | (no linked spec documents) | (link fetch failed, URLs only: <urls>)
PERMALINK: <format from 0.6> | none (file:line only)
```

## Phase 1: Parallel Detail Review

Launch reviewer subagents for the mode-selected perspectives **in parallel** (10 including meta in standard/heavy mode, 6-7 in light mode), all together in one batch. Avoid launching them one by one in sequence (it serializes and slows down). Each subagent has an independent context.

Start each subagent as `<perspective> review` with this prompt, unchanged apart from the perspective name. No per-perspective additions: everything a perspective needs is in the context file.

```
You are the "<perspective>" reviewer in a multi-perspective code review. Read these three files in order and follow them:
1. $SKILL_DIR/common-rules.md  (shared rules, output format, mandatory CHECKLIST)
2. $SKILL_DIR/perspectives/<perspective>.md  (your checklist)
3. $CTX_PATH  (change intent, file list, diff path, conventions, existing comments, permalink format)
Then review the diff at the DIFF_PATH given there, reading target files as your checklist requires. Do not edit any files.
```

## Phase 2: Collect & Aggregate

**Critical**: do not proceed to the next phase until **all** launched subagents are done. Advancing to Phase 3 or later while any reviewer is still outstanding is prohibited. The orchestrator withholds judgment until all results are in.

Once all results are in:

1. Parse each reviewer's reply, extracting `FINDING` blocks and the `CHECKLIST` table
2. **Merge the inventory tables**: combine all reviewers' CHECKLIST rows, keyed by perspective, and keep them. Present them to the user in Phase 3b-1. Perspectives excluded by light mode are recorded orchestrator-side as "out of scope due to light mode"
3. If everyone said "LGTM", report that to the user in Japanese (e.g. `全観点LGTMでした`) with the merged inventory and finish. **Do not return bare "no issues" without the inventory** (approvers need to see what was and was not examined)
4. Otherwise aggregate the findings. Tag each finding with `reviewer: <label>` and number them `#1, #2, ...` in the order collected. These numbers stay fixed for the rest of the run: judges, the Phase 3b-1 list, and option B all refer to them

### Under-Reporting Guard

The false-positive catalog exists to reduce false positives, not to reduce findings. Suspect over-suppression when any of the following hits.

- **About to finish with 0 CRITICAL / HIGH findings**: check the merged inventory for rows still marked "not examined"
- **A CHECKLIST "not applicable" row has no reason written**
- **A counterpart really exists but the naming / arch table shows no comparison record**: an asymmetry miss is certain

In each case relaunch the affected perspective **narrowed to the missing rows**: add one line to its prompt, `Examine only these checklist items: <items>; other rows may be copied from your previous CHECKLIST as "not re-examined"`. Relaunch at most once per perspective.

Reviewer-declared severities are provisional at this point. Do not calibrate yet; judges first verify which findings hold, and the orchestrator calibrates the VALID ones in Phase 3 (see "Severity Calibration").

## Phase 3: Judge Findings

Always split judges into **multiple parallel subagents**. Passing all findings to a single subagent shallows how deeply it reads code per finding, increasing misjudgments (missed false positives / valid issues ruled INVALID).

### Split Strategy

Pick the split policy from the aggregated finding count `N`. Launch **all judges in parallel** either way.

1. **Split by perspective (default, N <= 24)**: one judge per reviewer label:
   - Up to 10 parallel: `judge-<label>` per perspective (round down to max 4 parallel in light mode)
   - Do not launch judges whose label has 0 findings
   - Each judge examines only its own perspective's findings, so it is easy to focus on which code to read
2. **Split by finding count (N > 24, or 10+ findings concentrated on one perspective)**: chunk the findings:
   - Aim for 5-8 findings per chunk (keep findings on the same file in the same chunk)
   - Up to 8 parallel chunks. For N > 64, assign across 8 parallel judges with ceil(N/8) findings each
   - Even when chunking, keep `spec` and `meta` in independent chunks, never mixed with other perspectives (different evaluation axes)
3. **Cross-check (optional, for high-importance PRs)**: additionally pass all findings to one meta-judge and compare against the perspective judges. Findings where they disagree are shown separately at user-presentation time as "findings where judges disagreed"

Right after aggregating findings in Phase 2, the orchestrator computes N, picks a split policy from the above, and **logs which policy was adopted in Japanese** (e.g. `ジャッジ分割: 観点別（N=XX）` / `ジャッジ分割: 件数分割（N=XX、Xチャンク）`).

### Judge Prompt

Launch each judge as `judge <perspective or chunk#>` with the following prompt. Paste each finding block verbatim as the reviewer returned it, with its `#N` prepended; do not reformat or summarize.

```
You are a judge scrutinizing code review findings. Read $SKILL_DIR/judge.md and follow it exactly. Then read $CTX_PATH (change intent, file list, diff path, conventions, existing comments, counterpart, spec documents). Do not edit any files.
Perspective file: $SKILL_DIR/perspectives/<label>.md   (perspective-split judges only; omit this line for mixed chunks)

Assigned findings (keep their numbers in your output):
<findings>
```

### Aggregating Results

- Do not advance to Phase 3b until all judge subagents have returned
- Parse each judge's output and merge it **by NUMBER onto the Phase 2 findings**. Judges return only the verdict fields; title, file, line, description, and suggestion stay as the reviewer wrote them unless the judge supplied a corrected `FILE`/`LINE` or a `SUGGESTION`, which then override
- Findings with `EVIDENCE: UNVERIFIED` get an **"unverified" mark by default at user-presentation time**. For CRITICAL/HIGH ones, re-submit just those findings to a different subagent for re-judgment (max once)
- Merge DUPLICATE verdicts into the merge target by following `DUPLICATE_OF`
- With the cross-check policy, diff the perspective judges against the meta-judge and separately list "findings with split opinions"

### Severity Calibration

The judge's SEVERITY is a per-finding recommendation made without seeing the other perspectives. Compare all VALID findings across perspectives and assign the final severity using the following rubric. **Cross-perspective calibration can only be done by one party seeing everything.**

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
- A judge's `EVIDENCE: UNVERIFIED` finding never goes above the reviewer's declared severity

## Phase 3b: User Confirmation

**Always confirm with the user before fixing**. Unless `ALL_CLEAR`, never skip this phase regardless of judge results.

### Strict Rules for Phase 3b

**The review results are presented before any approach selection prompt, and the presentation ends the turn.** Text wedged between tool calls may never be shown to the user, so a list followed in the same turn by a selection prompt (or by any dummy tool call as a separator) counts as "selection prompt without showing the list", which is prohibited.

1. Phase 3b-1: output the full list of VALID findings as **normal response text (Markdown) and end the turn with that text as the final output**. After the list text, **make no tool calls of any kind**
2. Phase 3b-2 runs in **a later turn after the user reacts** to the list. If the user's response already states the approach (e.g. "fix them all"), skip the selection prompt and follow it

Exception: with `--fix` / `--post` the main policy is already decided, so Phase 3b-2 is execution rather than a selection prompt and may follow in the same turn as the list (except when meta/spec additional selections are needed).

### Phase 3b-1: Present the VALID Finding List

This step is unconditional and ends the turn. Even with 0 VALID findings, explicitly tell the user in Japanese (e.g. `VALID指摘は0件です`). Write all user-visible headings and body in Japanese, as normal text (Markdown):

1. The **complete list** of judge-VALIDated findings (number / reviewer / severity / file:line / title / description / suggestion in a table or bullets, omitting none) under the heading `## レビュー結果（VALID XX件）`
   - Keep the `#N` numbers assigned in Phase 2 so option B can refer to them; do not renumber after sorting
   - Mark `EVIDENCE: UNVERIFIED` ones explicitly with an "unverified" mark in Japanese (e.g. `未検証`)
   - Sort by severity (CRITICAL -> HIGH -> MEDIUM -> LOW)
   - For PR targets with a SHA available, attach permalinks (format from 0.6)
2. Counts only (for reference) of findings excluded as INVALID/DUPLICATE, under the heading `## 除外件数`
3. **Points checked and found fine** under the heading `## 確認済み・問題なし`. Never omit it even with many findings; approvers need to read "what was and was not examined". Present the merged inventory **compactly, one bullet per perspective**, grouping checklist items by result instead of one row per item:
   ```
   - security: 問題なし: Injection, Authn/authz, Secret exposure, Input validation, XSS/CSRF, Crypto, Sessions, Races ／ 該当なし: SSRF（外部URL取得なし）
   - naming: 問題なし: ... ／ 該当なし: Counterpart（対応実装なし） ／ 未確認: <item>
   ```
   Only "not applicable" and "not examined" items carry their reason; the "what was examined" details stay with you and are shown on request
4. If there are meta findings, show them in a separate section under the heading `## アプローチ指摘（meta）` (with CATEGORY and proposal)
5. If there are spec findings, also show them in a separate section under the heading `## 仕様整合性（spec）` (with CATEGORY / SPEC_REF / FIX_TARGET). Highlight `FIX_TARGET=SPEC` ones in particular in Japanese as `仕様側の修正が必要`
6. When run in light mode, state the excluded perspectives in Japanese under the heading `## 対象外観点（Lightモード）`

**No history**: write only the final verdict per finding. Do not write process details like severity raises/lowers or judge re-verdicts in the list or the final report (e.g. notes like "severity was lowered from HIGH to LOW" are unnecessary).

End the list text with a single line in Japanese moving toward approach confirmation (e.g. `上記のVALID指摘への対応方針をお知らせください`), then **end the turn**.

### Phase 3b-2: Confirm the Approach

With `--fix` / `--post` the main policy (A/B/E) is fixed as described under Target; still prompt for the meta/spec additional selections when needed. Otherwise, in the **turn after receiving the user's response** to the Phase 3b-1 list, present the following options in Japanese (skip when the user's response already states the policy):

```
今回のVALID指摘への対応方針を選んでください：

A. VALID指摘をすべて自動修正する（LOWを含む全重要度）
B. 修正する指摘を選ぶ（番号を指定）
E. VALID指摘をPRレビューコメントとして投稿する（Phase 4bへ。pending状態のインラインコメント。PR対象時のみ提示）

VALID meta指摘が残っている場合、追加で：
  M1. アプローチ変更を受け入れて修正に含める
  M2. アプローチを維持する（meta指摘はスキップ）
  M3. アプローチ再検討のため中断する（終了）

VALID spec指摘が残っている場合、追加で：
  S1. 実装を仕様に合わせる（コード修正）
  S2. 仕様を実装に合わせる（仕様側の修正が必要。オーケストレーターは仕様を更新せず、「仕様の改訂が必要」として報告する。Jira/Confluenceの編集権限がある場合、別途ユーザー確認の上で更新を提案する）
  S3. spec指摘をスキップする（実装・仕様とも現状維持）
  S4. 仕様自体の再検討が必要なため中断する（終了）
```

Accept the user's selection. When multiple questions are needed (fix policy + meta policy), ask them together at once.

Follow the user selection:
- A / B / M1 / S1: to Phase 4 (Fix)
- E: to Phase 4b (Post Pending PR Review). After posting, report the result in Japanese and finish. Fix as well only when the user explicitly wants both, in post-then-fix order
- M3 / S4: report the abort reason in Japanese and finish
- M2 / S3: skip only the applicable findings and follow the other findings' fix policy (A/B/E)
- S2: do not touch the implementation; include in the final user report in Japanese under the heading `## 仕様の改訂が必要` (no automatic spec-doc updates)

## Phase 4: Fix Valid Findings

Only findings the user chose to fix in Phase 3b.

Precondition for PR targets: the PR's `headRefName` must be checked out. If it is not, stop before editing and ask the user via selection prompt in Japanese whether to check it out (`gh pr checkout <number>`) or finish with the list only. Never edit files on a different branch.

1. Fix granularity follows the user selection:
   - Option A (all auto): every VALID finding regardless of severity, LOW included
   - Option B (individual): only the finding numbers the user specified
   - With M1 selected, include the meta findings
2. The orchestrator (you) edits files directly to fix. Never let subagents rewrite
3. Run the project's existing checks for the changed files: the linter, type checker, and the test files that exercise the changed modules, using the commands the repository already defines (package scripts, `Makefile`, `pyproject.toml`, CI definition). Do not add new tooling. Report failures verbatim in Japanese under `## 修正後チェック` and do not hide them; a check the repository does not define is reported as not run
4. Leave the fixes uncommitted. Commit only when the user asks
5. Report a summary of the fixes in Japanese and finish

## Phase 4b: Post Pending PR Review

Run only when option E applies (user choice or `--post`; PR targets only, so never offer E for local diffs or file-specified targets). Delegate the posting procedure to the [[pending-review-comments]] skill. That skill owns the procedure, pending-state rules, and error handling.

As deep-review-side preconditions, prepare the inputs to the skill as follows:

- **Only judge-VALIDated findings**. Never pass INVALID/UNCERTAIN ones
- Pass each finding with `FILE` / `LINE` / title / `DESCRIPTION` / `SUGGESTION` / `<reviewer>` / `<SEVERITY>` aligned (judge-corrected file/line/suggestion where present). Pass `<reviewer>` as `<kind>` and `<SEVERITY>` as `<grade>`; the comment head format belongs to [[pending-review-comments]]
- Include the evidence (convention-document quotes, measured breakdowns) in the comment body for findings that have it

After posting, report the result in Japanese (e.g. `pendingコメントを投稿しました`) and finish.

## Error Handling

- **Subagent response parse failure**: skip that reviewer and continue, noting in the final report in Japanese which perspective was skipped
- **No CHECKLIST returned**: restart that reviewer once. If still missing on the second try, record "no inventory table" in the merged inventory and continue (do not silently fill it in)
- **No applicable a11y**: expect LGTM from a11y when there are no UI changes
- **No applicable test**: expect at most "recommend adding tests"-level findings from test when no test files changed
- **Judge timeout/failure**: relaunch that judge once. If it fails again, do not drop its findings; carry them into the Phase 3b-1 list as VALID with the `未検証` mark and the reviewer's severity, and note in Japanese that the judge did not return (e.g. `注: <label>のジャッジが応答しなかったため未検証のまま掲載しています`). Phase 3b confirmation still applies
- **Subagent ignoring the specified format**: loosely match `FINDING:` lines in the reply to extract. If nothing is extractable, discard that reviewer's result
- **Post-fix checks fail**: do not loop on fixing check failures silently. Report the failing output and ask via selection prompt in Japanese whether to fix the failures, revert the offending fix, or leave it to the user
- **Existing review comment fetch failure**: on permission/API failure, set `EXISTING_COMMENTS: not fetched: <reason> (duplicates possible)` in the context file and continue, and also write that fact in the final report in Japanese (e.g. `注: 既存レビューコメントを取得できませんでした（重複を含む可能性あり）`)
- **Prep subagent failure or missing section**: do the missing lookups (0.5) yourself, keeping the same output shape
- **Spec document fetch failure**: on permission failure/bad URL/unconnected MCP, set `SPEC_DOCS: (link fetch failed, URLs only: <urls>)` and continue; the spec reviewer caps its findings at MEDIUM
- **Subagent cannot read `$SKILL_DIR` or `$CTX_DIR` files**: fall back to inlining the applicable file's content into that subagent's prompt (read it yourself only in this fallback case)
