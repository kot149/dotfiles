---
name: deep-review
description: Loop-style in-depth code review that runs multiple perspective-specific reviewer subagents in parallel, has judge subagents verify each finding against the real code, then fixes the valid findings and re-reviews. Reviews in 10 independent perspectives (security/quality/naming/comment/perf/a11y/test/arch/meta/spec), also fetching spec documents such as Jira/Confluence from the PR body to check spec consistency. Use when the user asks for "deep review", "review this PR", "review the diff from multiple angles", "review and fix", 「PRをレビュー」「差分を多角的にレビュー」「レビューして修正して」, or requests a review with a PR number or diff range in English or Japanese. Findings can also be posted as pending PR review comments. The `--fix` flag skips the approach selection prompt and auto-fixes, and `--post` similarly proceeds to pending review comment posting (only valid for PR targets).
argument-hint: "[--fast|--full] [--fix|--post]"
---

# Deep Review

Run multiple reviewer subagents in parallel from different perspectives, have judge subagents evaluate validity, fix the valid findings, then repeat the review-fix loop up to 5 times.

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

| Label | Perspective | Checklist |
|---|---|---|
| security | Security | Injection, authentication/authorization, secret exposure, input validation, XSS/CSRF, unsafe cryptography |
| quality | Code quality | Readability, function responsibility separation, error handling, DRY, immutability, nesting depth, magic numbers, **silent degradation and observability** (whether unexpected states silently fall back to defaults; whether fail-open, swallowed values, and continue-after-catch leave a trace in logs), **recoverability** (whether any path leaves data half-written when it crashes midway) |
| naming | Naming | Whether the name reveals content/role, misleading names, collisions or confusion with other existing features/roles, inconsistent wording for the same concept, too much or too little information for the scope, **mismatches with symmetric counterparts**. Note: casing convention (camelCase/snake_case etc.) violations are out of scope |
| comment | Comment quality | Redundant/obvious comments/docstrings, duplication, meta-comments narrating edit history, or conversely missing Why/constraints/pitfalls. Follow [[trim-comments]] as the criterion. Additionally **statement-vs-reality consistency** (whether facts claimed by docstrings, READMEs, PR bodies, and design docs hold in the current code) |
| perf | Performance | N+1, unnecessary re-renders, memory leaks, complexity, cache misses, bundle size, unnecessary loops |
| a11y | Accessibility | WCAG 2.2, aria attributes, keyboard operation, screen readers, contrast, focus management |
| test | Test quality | Coverage gaps, boundary values, brittle implementation-dependent tests, excessive mocking, AAA pattern, clear test names, **mutation checks** (whether existing tests fail when a condition is inverted, a set operation is flipped, or one member is removed from a union), proposing deletion of valueless tests (only asserting trivial results, tautologies asserting mock setup values verbatim, duplicates covering only the same path as other tests) |
| arch | Architecture | Layer violations, dependency direction, circular dependencies, bloated responsibilities, interface design, module cohesion, **backward compatibility** (whether contract changes break existing callers; search for callers and report counts), **asymmetry of counterparts** (invariants, type strictness, or accessors present on only one side of pairs like read/write) |
| meta | Approach validity | YAGNI violations, simpler alternatives, scope, incremental approach, existing assets, technology choice |
| spec | Spec consistency | Consistency with Jira/Confluence/PRD/design docs linked from the PR body, whether the implementation satisfies spec requirements, coverage of edge cases/acceptance criteria mentioned in the spec, validity of the spec itself (contradictions, gaps, wrong premises) |

## Phase 0: Preparation

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
- If **no spec documents are found at all**, set `$SPEC_DOCS = "(no linked spec documents)"` and instruct the spec reviewer to "evaluate whether the intent is self-evident from the implementation, or whether the PR body alone suffices"

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

## Rules Common to All Reviewers

Include all of the following in each reviewer's prompt along with the perspective-specific checklist.

### Require Evidence

**Only raise findings you can support by quoting the applicable convention document, or by measuring the majority pattern in existing code (search counts plus representative files).** Do not raise what you cannot support either way. Without an evidence requirement, design/naming/architecture perspectives can produce endless generic "should" arguments.

- When you count, write the breakdown. Not "5 places" but "5 places (4 in `foo.ts` and `bar.ts:52`)". Trying to write the breakdown exposes miscounts
- Do not use "seems like ..." or "in general ..." as evidence
- Write "what breaks if left as is". Do not stop at "maintainability decreases". Write it all the way to "the same check must be fixed in two places, and forgetting one skews the amounts"

### False-Positive Catalog (Do Not Raise, or Drop to Lowest Severity, Anything on These Lines)

1. **Pre-existing issues** (not introduced by this change) -> drop to LOW and note "not caused by this PR"
2. **Issues on unchanged lines** -> same as above
3. **Things a linter / type checker / compiler / CI would catch** (missing imports, type errors, formatting, test failures) -> do not raise. Do not run builds, type checks, or tests yourself
4. **Rules already enforced mechanically by CI** -> do not raise. First check `pyproject.toml` / `.pre-commit-config.yaml` / CI definitions for contracts on import order, naming, types, and formatting. Manually flagging enforced areas is pointless
5. **Unfounded taste** (comment style, line breaks, rename proposals based only on feel) -> do not raise
6. **Changes that read as intentional**, or changes naturally accompanying a broader change -> but do not drop them on "looks intentional" alone. Verify the intent is documented and consistent with existing patterns
7. **Generic test-coverage / documentation complaints** ("should add more tests" alone) -> LOW. But if you can show a concrete mutation where "breaking this change still passes the tests, so the regression is undetectable", that is not generic and may be MEDIUM or higher
8. **Design variance that reads as mid-migration** (old and new approaches coexisting in the same directory, with this PR mid-transition) -> report as LOW information, not a finding
9. **Leftover `fixup!` / `squash!` commits** -> ignore entirely. They are working commits squashed at merge time, not review topics
10. **Points already flagged or resolved in existing review comments** -> do not raise (cross-check against `$EXISTING_COMMENTS`)

### Always Return an Inventory Table (Mandatory Even with Zero Findings)

**Merely declaring "I checked" cannot distinguish "looked and found nothing" from "never looked".** Over-suppression of the catalog is only visible through this table.

Every reviewer appends the following table at the end of the response, however many findings there are.

```
CHECKLIST
| Checklist item | What was examined | Result |
|---|---|---|
| <each of your perspective's checklist items, one per row, all of them> | <searched terms and counts, files read> | N findings / no issues / not applicable (reason) |
```

- **Fill every row.** No blanks. Items you did not look at must say "not examined" (do not silently drop them)
- **"Not applicable" needs a reason** (e.g. "no persistence involved", "no change touching public contracts"). If you cannot write a reason, it is "not examined yet"
- Perspectives excluded by light mode are recorded orchestrator-side as "out of scope due to light mode"

With zero findings, return a lone `LGTM` line plus the `CHECKLIST`. **Returning only the table without stating whether there are findings is not allowed**.

## Phase 1: Parallel Detail Review

Launch reviewer subagents for the mode-selected perspectives **in parallel** (10 including meta in standard/heavy mode, 6-7 in light mode). `meta` and `spec` use dedicated prompts but launch in the same single message.

Start each subagent as `<perspective> review round $ROUND` with this prompt:

```
You are a code reviewer specializing in <perspective>. Review the following change from the <perspective> perspective only.
Do not raise findings belonging to other perspectives (e.g. anything outside <perspective> such as security, quality, or performance).

Checklist: <checklist from the Reviewers table above>

<Paste here the full text of the 3 sections under "Rules Common to All Reviewers" (require evidence / false-positive catalog / inventory table)>

If there are findings, return each one separated as follows:
---
FINDING: <finding title>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
FILE: <file path>
LINE: <line number (if known)>
EVIDENCE: <quote from the convention document (with file name and applicable lines), or measured existing-code evidence (search terms, counts, representative files)>
DESCRIPTION: <problem description, concretely what breaks and how if left as is>
SUGGESTION: <concrete fix proposal>
---

Whether or not there are findings, always append the CHECKLIST table at the end of your response.
If there are no findings, return a lone "LGTM" line plus the CHECKLIST.

Change intent: $PURPOSE
Changed files: $FILES
Target diff: $DIFF_PATH (read this file yourself; also read the target file bodies as needed)
Convention document paths: <path list found in 0.4, or the fact that none was found>
Existing review comments: $EXISTING_COMMENTS
Permalink format: <format from 0.8>
```

Parallel launch notes:

- Launch all target perspectives **together in parallel**. Avoid launching them one by one in sequence (it serializes and slows down)
- Each subagent has an independent context, so include shared premises explicitly in the prompt
- Additionally include in the `naming` prompt: "actually search the codebase for similar names to confirm collisions or confusion with other existing features/roles", "do not flag camelCase/snake_case-style casing convention violations", and "cross-check naming against the counterpart $SYMMETRY member by member"
- Additionally include in the `arch` prompt the "counterpart cross-check" below
- Additionally include in the `comment` prompt the "comment reviewer criteria" below
- Additionally include in the `test` prompt the "mutation check procedure" below

### Counterpart Cross-Check (naming / arch, only when a counterpart exists)

```
Counterpart: $SYMMETRY

For changes with a counterpart implementation, place them side by side and compare member by member.
Do not stop at "good because symmetric"; that is exactly how you miss the asymmetry itself. Fill a table over these 5 axes.

| Axis | What to look at |
|---|---|
| Class/attribute names | Whether the same role uses the same nouns (e.g. Issue vs Violation mixed) |
| Type strictness | Whether one side uses Literal / Enum while the other is a bare string |
| Invariants | Why one side has frozen / validators the other side lacks |
| Accessors | Whether one side hides internals behind a property while the other touches them directly |
| Docstring self-claims | Whether a property one side explicitly claims is silently missing on the other |

When you find a difference, check primary sources (in-code comments, design docs, tickets) for whether it is intentional.
Only unexplained differences are finding candidates.
```

### Comment Reviewer Criteria

Delegate the criteria to the [[trim-comments]] skill. In addition to the shared template, include the following in the prompt:

```
Only evaluate comment/docstring/README/PR-body prose; do not raise findings about logic, identifier names, or signatures.

Follow the [[trim-comments]] skill (the `SKILL.md` in the same skill store as yourself), its "2. Collect and classify comments" (keep / cut / shorten / move-and-consolidate) and "3. Things not to touch". Only if you could not read it, judge yourself by the principle "do not write what the code already shows; write only what cannot be read from the code".

Additional rules for this review:
- Do not edit files; return findings only
- You may also flag places missing information that belongs in "keep" (Why, constraints, external factors, pitfalls)
- Flag meta-comments narrating edit history ("added ...", "changed to ...", "in the old implementation ...", "per request ...") as cut candidates
- Cap findings on existing comments untouched by this diff at LOW
- In SUGGESTION, write the replacement comment text (write "delete" if it should be removed)

[Statement-vs-reality consistency]
Verify whether facts claimed by prose hold in the current code. Stale prose left after renames or deletions is the classic case.
- A docstring claims "the two never drift" but the implementation drifts
- A module header says "read model tests" but there is not a single read test
- Error-code or field names in the PR body differ from the implementation
Show both the claim and the counter-evidence with quotes. Match quotes against the original character for character (a summary is not a quote).
Demote to LOW things where a misunderstanding breaks nothing (e.g. stale line-number references).
```

### Mutation Check Procedure (test reviewer)

```
Do not raise generic "should add more tests" findings. Instead, work backward from how it breaks.

For each changed logic unit, consider concrete mutations and check whether existing tests would fail:
- If this line's condition were inverted
- If this set operation were flipped
- If one member were dropped from this union / enum
- If this default value were changed to another value

If tests still pass, that is a finding with a concrete mutation shown (may be MEDIUM or higher).
Findings must always state "which mutation lets which tests pass without failing".
If the mutation fails tests, write that in the CHECKLIST as the basis for "no issues".
```

### spec Reviewer Dedicated Prompt

`spec` does not use the shared template. Launch it as `spec review round $ROUND` with the following dedicated prompt:

```
You are a spec-consistency reviewer. Evaluate consistency between the implementation and the spec documents linked from the PR body (Jira/Confluence/PRD/design docs etc.), and also evaluate the validity of the specs themselves.

Evaluation axes:
A. Spec <-> implementation consistency
   1. Is every feature/requirement demanded by the spec implemented (nothing missing)
   2. Was any unrequested feature added on your own (scope creep)
   3. Are the acceptance criteria, edge cases, and error specs defined in the spec satisfied
   4. Do data models, API signatures, screen elements, naming, etc. match the spec
   5. Is there any conflict with non-functional requirements defined in the spec (performance, security, compatibility, etc.)

B. Validity of the spec itself (you may also flag that the spec may be wrong)
   1. Any contradictions, ambiguities, or gaps within the spec
   2. Any conflict between spec premises and the current system/codebase/operations
   3. Any logical breakage in UX / business flow
   4. Any security/privacy/compliance problems in the spec itself
   5. Whether the approach chosen in the spec is inferior to a better alternative

Match spec quotes against the original character for character (a summary is not a quote).

<Paste here the full text of the 3 sections under "Rules Common to All Reviewers">

If there are findings, return each one separated as follows:
---
FINDING: <finding title>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
CATEGORY: SPEC_MISMATCH|SPEC_MISSING_IMPL|SPEC_SCOPE_CREEP|SPEC_FLAW|SPEC_AMBIGUOUS|SPEC_OUTDATED
SPEC_REF: <applicable spec document's title/URL/verbatim quote of the relevant passage>
FILE: <file path (may be empty for findings against the spec itself)>
LINE: <line number (if any)>
DESCRIPTION: <problem description, stating explicitly whether the spec or the implementation is at fault>
SUGGESTION: <fix proposal, stating explicitly whether the spec or the implementation should be fixed>
---

If no spec document could be fetched, evaluate whether the PR body alone makes the implementation intent self-evident, and flag as MEDIUM if it is unclear.
Whether or not there are findings, always append the CHECKLIST table at the end of your response.
If there are no issues, return a lone "LGTM Spec and implementation are consistent" line plus the CHECKLIST.

Change intent (from PR body): $PURPOSE
Changed files: $FILES
Linked spec documents: $SPEC_DOCS
Target diff: $DIFF_PATH
```

### meta Reviewer Dedicated Prompt

`meta` may also run in parallel with the others, but its prompt differs. Launch it as `meta review round $ROUND`.

```
You are a meta-reviewer evaluating the approach itself. Do not review code details; ask "whether this approach is appropriate".

Change intent/purpose: $PURPOSE

Evaluate along these 6 axes:
1. Over-engineering (YAGNI violations) — abstractions not needed now, designs only for the future
2. Simpler alternatives — whether the same goal is achievable via libraries, existing features, or simplified patterns
3. Scope validity — whether changes belonging in a separate PR/task are mixed in
4. Incremental approach — whether anything could ship in split releases instead of one full implementation
5. Overlooked existing assets — whether equivalent functionality already exists in the project (verify by searching the codebase)
6. Technology choice validity — whether the library/framework/pattern fits the scale and use case

<Paste here the full text of the 3 sections under "Rules Common to All Reviewers">

If there are findings, return as follows:
---
FINDING: <finding title>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
CATEGORY: YAGNI|SIMPLER_ALTERNATIVE|SCOPE_CREEP|INCREMENTAL|REINVENTION|TECH_CHOICE
EVIDENCE: <measured existing assets/patterns, or quotes from convention documents>
DESCRIPTION: <problem description>
SUGGESTION: <alternative approach proposal>
---

Whether or not there are findings, always append the CHECKLIST table at the end of your response.
If there are no issues, return "LGTM Approach is sound" plus the CHECKLIST.

Changed files: $FILES
Target diff: $DIFF_PATH
```

## Phase 2: Collect & Aggregate

**Critical**: do not proceed to the next phase until **all** launched subagents are done. Advancing to Phase 3 or later while any reviewer is still outstanding is prohibited. The orchestrator withholds judgment until all results are in.

Once all results are in:

1. Parse each reviewer's reply, extracting `FINDING` blocks and the `CHECKLIST` table
2. **Merge the inventory tables** — combine all reviewers' CHECKLIST rows into one table and keep it. Present it to the user in Phase 3b-1
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
   - Up to 10 parallel: `judge-security`, `judge-quality`, `judge-naming`, `judge-comment`, `judge-perf`, `judge-a11y`, `judge-test`, `judge-arch`, `judge-spec`, `judge-meta` (round down to max 4 parallel in light mode)
   - Do not launch judges whose label has 0 findings
   - Each judge examines only its own perspective's findings, so it is easy to focus on which code to read
2. **Split by finding count (N > 24, or 10+ findings concentrated on one perspective)** — chunk the findings:
   - Aim for 5-8 findings per chunk (keep findings on the same file in the same chunk)
   - Up to 8 parallel chunks. For N > 64, assign across 8 parallel judges with ceil(N/8) findings each
   - Even when chunking, keep `spec` and `meta` in independent chunks, never mixed with other perspectives (different evaluation axes)
3. **Cross-check (optional, for high-importance PRs)** — additionally pass all findings to one meta-judge and compare against the perspective judges. Findings where they disagree are shown separately at user-presentation time as "findings where judges disagreed"

Right after aggregating findings in Phase 2, the orchestrator computes N, picks a split policy from the above, and **logs which policy was adopted in Japanese** (e.g. `ジャッジ分割: 観点別（N=XX）` / `ジャッジ分割: 件数分割（N=XX、Xチャンク）`).

### Judge Prompt Template

Launch each judge as `judge <perspective or chunk#> round $ROUND` with the following prompt.

```
You are a judge scrutinizing code review findings. For your assigned group of findings, always follow these steps.

[Mandatory steps — no skipping]
1. For each finding, **always open the real file** at the `FILE` and `LINE` indicated. Never judge from the finding text alone
2. Also read surrounding code (about 30 lines around, plus callers, type definitions, related modules as needed). Verify whether the finding's premise holds in the current codebase
3. For spec findings, additionally re-read the applicable passage of the provided spec document body and verify the divergence is real
4. For meta findings, search the codebase for "equivalent existing implementations" and "past similar approaches" before judging
5. If you judged without reading code, or could not locate the referenced spot, always append `EVIDENCE: UNVERIFIED` right after the VERDICT line

[Verification per claim type — minimum bar for claiming VERIFIED]
Split claims inside findings by type and verify each as follows. Never conclude from "types, inheritance, or looks" alone.

| Claim type | How to verify | Pitfall |
|---|---|---|
| Numbers ("N places", "N files", "N tests") | Count yourself. First define what counts | Padding the count with unrelated usages |
| Quotes (quoted docstring/convention text) | Match against the original character for character. A summary is not a quote | Paraphrasing from memory |
| Existence/absence ("no ...", "unused") | Confirm exhaustively by search. Count layers (domain / adapters etc.) separately | Looking at one layer and claiming "unused" |
| Reachability ("returns ...", "breaks on this path") | Trace raise / call sites. If none, write "not yet reachable" | Judging "it returns" from type inheritance alone |
| Behavior (language/library semantics) | Actually run a small read-only experiment (do not build or test the target repo) | Writing "probably behaves like ..." |

When you verify a number, also write its breakdown in EVIDENCE_NOTES. Trying to write it exposes miscounts.

[False-positive catalog — rule INVALID or drop to lowest severity on these lines]
1. Pre-existing issues (not introduced by this change) / issues on unchanged lines -> drop severity to LOW and note "not caused by this PR"
2. Things a linter / type checker / compiler / CI would catch (missing imports, type errors, formatting, test failures) -> INVALID
3. Rules already enforced mechanically by CI (import order, naming, formatting, types — check config files and CI definitions) -> INVALID
4. Unfounded taste (comment style, line breaks, rename proposals based only on feel) -> INVALID
5. Generic test-coverage / documentation complaints (without a concrete mutation shown) -> LOW
6. Design variance that reads as mid-migration, with this PR mid-transition -> LOW
7. Leftover fixup! / squash! commits -> INVALID
8. Points already flagged or resolved in existing review comments -> INVALID

But **do not over-apply the catalog**. Never drop something merely because "the author explained it".
Dropping is allowed only when the decision is documented and its rationale does not contradict existing patterns or contracts.
If the rationale conflicts with existing patterns, the explanation's existence itself supports the finding.

[Verdict criteria]
- VALID: reading the real code confirmed the finding actually holds
- INVALID: reading the real code showed a false positive, wrong premise, already addressed, or a catalog hit, so it does not hold
- DUPLICATE: effectively identical to another finding (show the merge target in the DUPLICATE_OF line)

[Output format] For each finding:
---
VERDICT: VALID|INVALID|DUPLICATE
ORIGINAL_FINDING: <original finding title>
REVIEWER: <security|quality|naming|comment|perf|a11y|test|arch|spec|meta>
FIX_TARGET: <CODE|SPEC|EITHER|N/A>  # spec findings only
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
FILE: <file path>
LINE: <line number>
EVIDENCE: VERIFIED|UNVERIFIED  # always state explicitly whether you read real code/spec text to judge
EVIDENCE_NOTES: <files and line ranges read, key quoted code points, in 1-3 lines. Breakdowns for numeric claims>
REASON: <verdict reason, concretely which code structure makes it VALID/INVALID>
SUGGESTION: <fix proposal for VALID findings>
DUPLICATE_OF: <merge target ORIGINAL_FINDING, only for DUPLICATE>
---

If all assigned findings are INVALID, return a lone "ALL_CLEAR" line.

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
- **Spec document fetch failure**: on permission failure/bad URL/unconnected MCP, state "link fetch failed, URLs only" in the prompt to the spec reviewer and continue. Demote spec findings to MEDIUM or lower
- **No links at all in the PR body**: the spec reviewer runs in "no spec links. Evaluate whether the PR body alone conveys the intent" mode. Flag as MEDIUM if the implementation intent is unclear
