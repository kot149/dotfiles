---
name: meta-review
description: Verify review feedback (from human reviewers, AI reviews such as Codex/deep-review, GitHub PR comments, lint bots) instead of taking it at face value, by having fresh subagents with no conversation context judge each finding from the real code, judging it again with the conversation context when the session has any, and reconciling the two. The point is to remove both the reviewer's assumptions and the author's hindsight bias without losing what only the context knows. Use when the user asks "is this finding valid?", "verify these review comments", "should I really fix this?", "don't just accept the feedback, check it", 「この指摘は妥当か確認して」「レビューコメントを検証して」「鵜呑みにせず確かめて」, any similar phrasing in English or Japanese, or before acting on findings from Codex/deep-review/GitHub PR reviews. Judges validity only by default; pass `--fix` to also apply the findings that were judged valid, or `--post` to post them as pending PR review comments instead.
argument-hint: "[target: PR number/URL/text] [--fix|--post]"
---

# meta-review

Verify review findings with two judgments, one without conversation context (independent subagents) and one with it (you), and reconcile them.

## Target

If the request contains a PR number/URL, file path, or finding text, treat that as the verification target. If empty, identify the source per step 1.

## Flags

- `--fix`: after presenting the verdicts, apply the VALID / PARTIALLY_VALID findings (step 5). Without it, stop at the verdicts.
- `--post`: after presenting the verdicts, post the VALID / PARTIALLY_VALID findings as pending PR review comments (step 4b) instead of fixing. Only valid when the target is a GitHub PR; for any other target, warn that `--post` is invalid, ignore it, and stop at the verdicts as usual.

Strip the flag out of the request before using the rest as the target. A plain-language equivalent in the request ("fix the valid ones", "verify and fix") counts as `--fix`; ("post them as PR comments", "post as pending review") counts as `--post`. If both `--fix` and `--post` are given (or the user asks for both), run step 4b (post) then step 5 (fix), in that order.

## Subagents

{{ includeTemplate "agents/skills/_shared/subagents.md" . }}

The judging subagent is a read-only role, so every edit is made by the orchestrator in step 5.

## Why two judgments

Whoever receives the feedback (the author of the code, or an agent that has already read the review context) is prone to these biases:

- Trusting the source (human or AI review tool) unconditionally and agreeing without scrutiny
- Conversely, unconsciously dismissing findings against code they wrote themselves
- Knowing the conversation history (why the code was written that way) and therefore assuming that reasoning was correct to begin with

To avoid this, the **context-free judgment** is done by fresh subagents with no conversation history. Pass only the finding text and the target file paths; never pass background such as "why it was written this way" or "who raised it". Their verdict rests solely on reading the actual files.

The context itself also carries facts the code does not show: requirements and decisions the user stated, specs and tickets read earlier, constraints found while working. A judgment without them can wrongly accept a finding that contradicts a deliberate decision, or wrongly reject one whose impact only the context reveals. So when this session has such context, you (the orchestrator) also make a **context-aware judgment** of every finding (step 3b), and step 4 reconciles the two.

### When you have no context to begin with

Then there is no context-aware judgment to make, and only the context-free judgment is run. That applies only when all of the following hold:

- You did not write or edit the code under review in this conversation
- You have not seen the reasoning behind either the code or the review in this conversation (no design discussion, no review you ran yourself)
- The findings came from outside (pasted text, a GitHub PR, a file), not from a review produced earlier in this session

In that case you hold none of the biasing context either, so you may make the context-free judgment yourself instead of delegating it to subagents. Follow the same required steps and verdict criteria as the judging prompt in step 3, always read the real files instead of judging from the finding text, and skip step 3b and the reconciliation in step 4. Do not mention in the report that subagents were skipped.

If any of the conditions fails (deep-review/codex-review ran earlier in this session, you made the changes, the user explained the intent behind the code), run both judgments.

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

Skip this step and step 3's delegation when you have no context (see above); judge the findings yourself and go to step 4.

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

### 3b. Make the context-aware judgment

Skip this step when you have no context (see above).

Once the subagents of step 3 are launched, judge every finding yourself, using what this conversation knows. Finish and record all of your verdicts **before reading any subagent output**, so the two judgments stay independent.

- Follow the same required steps, verdict criteria and output format as the prompt in step 3. Read the real files; the context adds to the code reading and never replaces it
- Add one line per finding, `CONTEXT: <the fact from this conversation the verdict depends on, and where it came from (user's statement, spec, ticket, earlier finding)>`, or `CONTEXT: NONE` when the verdict rests on the code alone
- Your own reasons for having written the code a certain way are not a fact. Treat them as the bias this skill exists to remove, and do not cite them in CONTEXT

### 4. Aggregate and present to the user

Aggregate only after every subagent has returned. Match each output back to the original finding by `ID`, and check that every input ID came back. Include any missing ID in the list as UNVERIFIABLE, stating explicitly that no verdict was returned.

When step 3b ran, reconcile the two verdicts per ID into one final verdict:

1. Same verdict: adopt it
2. Different verdicts: re-read the code at both EVIDENCE locations. If one side misread the code (quote does not match, wrong location, missed caller or guard), adopt the other side
3. Otherwise, if the context-aware verdict has a CONTEXT that the code cannot show (a requirement or decision the user stated, a spec, a ticket), adopt it and cite that source in the reason
4. Anything still split is DISPUTED: keep both verdicts and reasons and leave the call to the user

Present as plain Markdown text, grouped by final verdict:

1. VALID / PARTIALLY_VALID findings (id, file:line, claim, evidence, reason)
2. INVALID findings with the reason for rejection
3. STALE findings (noting they are already handled)
4. UNVERIFIABLE findings (what could not be determined)
5. DISPUTED findings (both verdicts and what each rests on)

For findings settled by rule 2 or 3, state which judgment was adopted and why. DISPUTED findings are outside the scope of steps 4b and 5.

Without `--fix` or `--post`, **stop here and do not proceed further**, leaving the decision to act to the user. With `--fix` and/or `--post`, present this list first and then continue to step 4b and/or step 5 in the same turn.

### 4b. Post pending PR review comments (`--post` only)

Only run this when `--post` was given and the target is a GitHub PR. Skip it entirely otherwise (including when `--post` was given for a non-PR target, per the Flags section above).

Delegate the actual posting procedure to the [[pending-review-comments]] skill; that skill owns the pending-state rules, dedupe against existing comments, and error handling. Prepare its input as follows:

- Scope: VALID findings, plus the parts of PARTIALLY_VALID findings that the judge said hold. Never pass INVALID, STALE, or UNVERIFIABLE findings
- Pass each finding with `FILE` / `LINE` / `CLAIM` / `EVIDENCE` / `REASON` aligned to that skill's expected input (file path, line, and body at minimum)
- For each finding, pass `<kind>` as the finding's own category or perspective where the source review supplied one, and `<grade>` as the verdict (`VALID` / `PARTIALLY_VALID`). Where the source review supplied no category, pass `<grade>` only and let the label line carry the verdict alone. Never pass the skill name as `<kind>`; the comment head format belongs to [[pending-review-comments]]
- Include the evidence quotes in the comment body where available

After posting, report the result (posted / skipped / excluded as duplicates, per that skill's report format). If `--fix` was also given, continue to step 5 next in the same turn; otherwise finish here.

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
- Never assign the same finding to more than one judging subagent (batch so that findings do not overlap). The context-aware judgment in step 3b covers every finding on top of that
- If a finding is too coarse (one comment mixing several points), split it per point before assigning

## Error Handling

- **Output format not followed**: extract by matching the `VERDICT:` line loosely. A verdict with no recoverable ID cannot be tied back to a finding, so do not adopt it; present that finding as UNVERIFIABLE
- **A finding got no verdict**: include the missing ID as UNVERIFIABLE. Never fabricate a verdict or silently drop the finding
- **The subagent call itself failed**: re-run that batch once. If the retry also fails, present its findings explicitly as "could not be judged". Never discard the other batches' results
- **A verdict with EVIDENCE: UNREAD**: it was produced without reading the real code, so do not adopt it as-is; present it marked "unverified". Re-submit any VALID-but-UNREAD finding on its own to another subagent for a second judgment (at most once)
- **Target file does not exist**: it may have been renamed/moved, so look for it by searching the repository; if still not found, mark STALE
