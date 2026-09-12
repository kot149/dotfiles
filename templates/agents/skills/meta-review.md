---
name: meta-review
description: Verify review feedback (from human reviewers, AI reviews such as Codex/deep-review, GitHub PR comments, lint bots) instead of taking it at face value, by handing each finding to a fresh subagent that has no conversation context and must judge it from the real code. The point is to remove both the reviewer's assumptions and the author's hindsight bias. Use when the user asks "is this finding valid?", "verify these review comments", "should I really fix this?", "don't just accept the feedback, check it", or before acting on findings from Codex/deep-review/GitHub PR reviews. Judges validity only by default; pass `--fix` to also apply the findings that were judged valid.
---

# meta-review

Verify review findings with independent subagents dedicated to judging whether each finding actually holds.

## Target

$ARGUMENTS

If `$ARGUMENTS` contains a PR number/URL, file path, or finding text, treat that as the verification target. If empty, identify the source per step 1.

## Flags

- `--fix`: after presenting the verdicts, apply the VALID / PARTIALLY_VALID findings (step 5). Without it, stop at the verdicts.

Strip the flag out of `$ARGUMENTS` before using the rest as the target. A plain-language equivalent in the request ("fix the valid ones", "verify and fix") counts as `--fix`.

## Subagents

This skill delegates judging to **subagents**: child agents with their own context that cannot see this conversation. Map them onto whatever the running agent provides:

- Claude Code: the `Agent` tool with `subagent_type: "Explore"` (read-only). Put several `Agent` calls in one message to run them in parallel.
- Codex CLI: `spawn_agent` per batch, then `wait` on all of them (requires `features.multi_agent`; pick a read-only role from `[agents]` in `config.toml`).

Whatever the mechanism, these requirements must hold:

- The judging subagent starts from a **fresh context** and does not inherit this conversation.
- It is **read-only**. If the agent cannot enforce that, state it in the prompt and make every edit yourself in step 5.
- Where a step says to run batches in parallel, use the agent's parallel mechanism. If it has none, run them sequentially and say so in the final report.

## Why an independent subagent is required

Whoever receives the feedback (the author of the code, or an agent that has already read the review context) is prone to these biases:

- Trusting the source (human or AI review tool) unconditionally and agreeing without scrutiny
- Conversely, unconsciously dismissing findings against code they wrote themselves
- Knowing the conversation history (why the code was written that way) and therefore assuming that reasoning was correct to begin with

To avoid this, judging is done by a **fresh subagent with no conversation history**. Pass only the finding text and the target file paths; never pass background such as "why it was written this way" or "who raised it". The verdict must rest solely on reading the actual files.

### Exception: when you have no context to begin with

What is required is a judgment free of those biases, not the subagent mechanism itself. If you (the orchestrator) genuinely hold none of the biasing context, you may judge the findings yourself and skip the subagents. That applies only when all of the following hold:

- You did not write or edit the code under review in this conversation
- You have not seen the reasoning behind either the code or the review in this conversation (no design discussion, no review you ran yourself)
- The findings came from outside (pasted text, a GitHub PR, a file), not from a review produced earlier in this session

If any of them fails (deep-review/codex-review ran earlier in this session, you made the changes, the user explained the intent behind the code), delegate to subagents as described. When judging yourself, follow the same required steps and verdict criteria as the judging prompt in step 3, always read the real files instead of judging from the finding text, and state in the final report that the verdicts were made in-context without subagents.

## Steps

### 1. Collect the findings to verify

Fetch according to the source:

- Text pasted directly into the chat: use as-is
- GitHub PR: different comment kinds live behind different APIs, so do not grab the wrong one
  - Inline comments (anchored to file/line): `gh api repos/{owner}/{repo}/pulls/{number}/comments`
  - Review bodies (overall summary): `gh api repos/{owner}/{repo}/pulls/{number}/reviews`
  - PR-level comments not anchored to a line (including lint bots): `gh pr view {number} --comments`
- Output from deep-review/codex-review earlier in this session: reuse the existing finding list
- Ask the user only when the source is ambiguous

Break each finding down into: `{id: sequence number, claim: what is claimed, file: target file (if any), line: line number (if any), suggestion: proposed change (if any)}`

Always assign `id` as `F1`, `F2`, ... . It is the only key for matching a judging subagent's output back to the original finding; never match by summary text. If one comment mixes several points, split it per point and give each its own id.

### 2. Split the judging subagents into batches

Skip this step and step 3's delegation when the exception above applies; judge the findings yourself and go to step 4.

Decide in this order; earlier rules win over later ones.

1. Multiple findings on the same file/same location must go in the same batch (so duplicate judgments stay consistent). Never split that group
2. Keeping those groups intact, aim for about 5 findings per batch
3. If that still fits in fewer than 6 batches (i.e. the rest are all standalone findings), a standalone finding may get its own subagent
4. Cap parallelism at 8. If it does not fit in 8 batches, raise the per-batch count to pack into 8 parallel subagents (never go to 9+ batches)

If there are more than 40 findings, each subagent's share grows and judgments get shallow, so first ask the user whether to narrow by severity/source or run the whole set across several passes.

Launch all batches **in parallel** using the mechanism in "Subagents". Never one batch at a time when parallelism is available.

### 3. Ask for the verdicts

Launch one read-only subagent per batch, described as `verify feedback batch #<N>`. Pass only the finding text and target file paths in the prompt; say nothing about the history or who raised it. Use this prompt:

```
Judge independently whether each of the following findings holds, by reading the real code. You are given no background about who raised them or why. That is intentional: base your verdict solely on the current contents of the actual files.

[Required steps]
1. Always open and read each finding's FILE. Never judge from the finding text alone
2. Read around LINE (roughly 30 lines either side), and if needed the callers, type definitions, and related files
3. Check whether the target of the finding still exists in the current code. If it was already fixed/removed after the finding was written and the target is gone, mark it STALE
4. For findings with no FILE (design/approach/spec-level points, or comments not anchored to a line), locate the likely implementation yourself by searching the repository and then judge. Only if you cannot locate it, mark UNVERIFIABLE and write in REASON what you searched for and did not find

[Verdict criteria] VERDICT is exclusive. When torn, apply this priority order
- STALE: the code the finding points at has been changed/removed and its target no longer exists
- INVALID: the target exists but the finding does not hold (false positive, wrong premise, misread spec or implementation)
- PARTIALLY_VALID: only part of the finding holds (state clearly which part does and which does not)
- VALID: the finding actually holds against the current code
- UNVERIFIABLE: judging requires external specs or domain knowledge and cannot be settled by reading code

[Output format] For each finding, write the ID exactly as given in the input on the ID line. Never rewrite an ID or replace it with a summary:
---
ID: <the ID given in the input, e.g. F1>
VERDICT: VALID|INVALID|PARTIALLY_VALID|STALE|UNVERIFIABLE
CLAIM: <summary of the finding>
FILE: <file path. If not in the finding and you located it yourself, that path. N/A if not located>
LINE: <line number, or N/A>
EVIDENCE: <quotes/line ranges from the real code you read. UNREAD if you could not read it>
REASON: <why you judged this way, citing the concrete structure in the real code>
---

Output every finding assigned to you without exception. Findings you could not judge must still be emitted as UNVERIFIABLE; never silently drop one.

Findings:
<paste this batch's findings here, listing id/claim/file/line/suggestion verbatim>
```

### 4. Aggregate and present to the user

Aggregate only after every subagent has returned. Match each output back to the original finding by `ID`, and check that every input ID came back. Include any missing ID in the list as UNVERIFIABLE, stating explicitly that no verdict was returned.

Present as plain Markdown text, grouped by VERDICT:

1. VALID / PARTIALLY_VALID findings (id, file:line, claim, evidence, reason)
2. INVALID findings with the reason for rejection
3. STALE findings (noting they are already handled)
4. UNVERIFIABLE findings (what could not be determined)

Without `--fix`, **stop here and do not proceed to fixes**, leaving the decision to act to the user. With `--fix`, present this list first and then continue to step 5 in the same turn.

### 5. Apply the valid findings (`--fix` only)

Only run this when `--fix` was given. Skip it entirely otherwise.

1. Scope: VALID findings, plus the parts of PARTIALLY_VALID findings that the judge said hold. **Never touch INVALID, STALE, or UNVERIFIABLE findings**, which is the whole point of having verified them. If you believe an INVALID finding is worth fixing anyway, say so in the report and leave the code alone
2. Make the edits yourself. Never delegate the edit to a subagent
3. Apply the finding, not the reviewer's wording: `suggestion` is a proposal, and where the surrounding code implies a better fix, take that and note the difference. Keep each fix to the smallest change that resolves the finding; do not fold in unrelated refactoring
4. If two findings on the same location conflict, do not fix both. Report the conflict and apply only the one supported by the stronger evidence
5. If a fix turns out to need a design decision the user has not made (API change, behavior change, dependency addition), stop that one finding, leave it unfixed, and report why. Keep fixing the rest
6. Verify what you changed: run the project's tests/lint/typecheck if they exist and are cheap to run, otherwise re-read the edited region. Report failures verbatim; never claim a fix is verified when it is not

Then report per finding id: fixed / skipped (with reason) / needs a decision, followed by the verification result. If nothing was verified by a test run, say so explicitly.

## Notes

- Never include steering information in the judging prompt, such as "the reviewer is trustworthy" or "this came from an AI review tool". Pass only the finding text and target file paths
- Judging subagents **never write**. Fixes are made by the orchestrator (you)
- Never assign the same finding to more than one judging subagent (batch so that findings do not overlap)
- If a finding is too coarse (one comment mixing several points), split it per point before assigning

## Error Handling

- **Output format not followed**: extract by matching the `VERDICT:` line loosely. A verdict with no recoverable ID cannot be tied back to a finding, so do not adopt it; present that finding as UNVERIFIABLE
- **A finding got no verdict**: include the missing ID as UNVERIFIABLE. Never fabricate a verdict or silently drop the finding
- **The subagent call itself failed**: re-run that batch once. If the retry also fails, present its findings explicitly as "could not be judged". Never discard the other batches' results
- **A verdict with EVIDENCE: UNREAD**: it was produced without reading the real code, so do not adopt it as-is; present it marked "unverified". Re-submit any VALID-but-UNREAD finding on its own to another subagent for a second judgment (at most once)
- **Target file does not exist**: it may have been renamed/moved, so look for it by searching the repository; if still not found, mark STALE
