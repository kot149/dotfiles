---
name: double-check
description: Double-check something before acting on it or handing it over, instead of taking it at face value. Covers review feedback (human reviewers, Codex/deep-review, GitHub PR comments, lint bots), investigation results (an answer, root-cause analysis or research summary, including one produced earlier in this session), and drafts (PR bodies, docs, replies, plans, reports). Breaks the target into checkable items, has fresh subagents with no conversation context judge each one from primary sources (code, files, command output, docs, tickets), judges them again with the conversation context when the session has any, and reconciles the two. The point is to remove both the source's assumptions and the author's hindsight bias without losing what only the context knows. Use when the user asks "double-check this", "is this finding valid?", "verify these review comments", "is this investigation right?", "fact-check this draft", "don't just accept it, check it", 「ダブルチェックして」「この指摘は妥当か確認して」「レビューコメントを検証して」「この調査結果が正しいか確かめて」「このドラフトの内容が合っているか確認して」「鵜呑みにせず確かめて」, any similar phrasing in English or Japanese, or before acting on findings from Codex/deep-review/GitHub PR reviews. Judges only by default; pass `--fix` to also apply the result (fix the code for review findings, correct the text for investigation results and drafts), or `--post` to post valid PR review findings as pending review comments.
argument-hint: "[target: PR number/URL/file/text] [--fix|--post]"
---

# double-check

Verify a target item by item with two judgments, one without conversation context (independent subagents) and one with it (you), and reconcile them.

## Target

If the request contains a PR number/URL, file path, or text, treat that as the target. If it only points back at the conversation ("double-check that", "check your answer"), the target is the most recent review, investigation result or draft in this session. If it is still unclear, identify the source per step 1.

The target falls into one of these kinds. It decides how items are extracted (step 1) and what `--fix` does (step 5):

| Kind | Examples | An item is |
| --- | --- | --- |
| Review findings | PR review comments, deep-review/codex-review output, lint bot comments | A claimed problem or requested change |
| Investigation result | An answer to a question, root-cause analysis, research summary, survey of a codebase | A factual claim the conclusion rests on |
| Draft | PR body, commit message, doc, issue, reply, plan, report | A factual claim the draft makes, plus coverage against its source material |

Only what can be settled against a source is in scope. Style, tone and wording of a draft are not; leave them to the writing skills.

## Flags

- `--fix`: after presenting the verdicts, apply the VALID / PARTIALLY_VALID items (step 5). Without it, stop at the verdicts.
- `--post`: after presenting the verdicts, post the VALID / PARTIALLY_VALID findings as pending PR review comments (step 4b). Only valid when the target is review findings on a GitHub PR; for any other target, warn that `--post` is invalid, ignore it, and stop at the verdicts as usual.

Strip the flag out of the request before using the rest as the target. A plain-language equivalent in the request ("fix the valid ones", "verify and fix", "correct the draft") counts as `--fix`; ("post them as PR comments", "post as pending review") counts as `--post`. If both `--fix` and `--post` are given (or the user asks for both), run step 4b (post) then step 5 (fix), in that order.

## Subagents

{{ includeTemplate "agents/skills/_shared/subagents.md" . }}

The judging subagent is a read-only role, so every edit is made by the orchestrator in step 5. It may run read-only commands (`git log`, `--help`, test listings) and read docs or web pages to check a claim, so pick a read-only role that can still run commands where the agent distinguishes them.

## Why two judgments

Whoever receives the target (the author of the code or text, or an agent that has already read the surrounding context) is prone to these biases:

- Trusting the source (a human, an AI review tool, its own earlier investigation) unconditionally and agreeing without scrutiny
- Conversely, unconsciously dismissing findings against code or text they wrote themselves
- Knowing the conversation history (why the code was written that way, how the conclusion was reached) and therefore assuming that reasoning was correct to begin with

To avoid this, the **context-free judgment** is done by fresh subagents with no conversation history. Pass only the item text and pointers to primary sources (file paths, URLs, ticket keys, commands to run); never pass background such as "why it was written this way", "how we reached this conclusion" or "who wrote it". Their verdict rests solely on the sources they check themselves.

The context itself also carries facts the sources do not show: requirements and decisions the user stated, specs and tickets read earlier, constraints found while working. A judgment without them can wrongly accept an item that contradicts a deliberate decision, or wrongly reject one whose impact only the context reveals. So when this session has such context, you (the orchestrator) also make a **context-aware judgment** of every item (step 3b), and step 4 reconciles the two.

### When you have no context to begin with

Then there is no context-aware judgment to make, and only the context-free judgment is run. That applies only when all of the following hold:

- You did not write or edit the code or text under check in this conversation
- You have not seen the reasoning behind the target in this conversation (no design discussion, no review or investigation you ran yourself)
- The target came from outside (pasted text, a GitHub PR, a file), not from something produced earlier in this session

In that case you hold none of the biasing context either, so you may make the context-free judgment yourself instead of delegating it to subagents. Follow the same required steps and verdict criteria as the judging prompt in step 3, always check the real sources instead of judging from the item text, and skip step 3b and the reconciliation in step 4. Do not mention in the report that subagents were skipped.

If any of the conditions fails (deep-review/codex-review ran earlier in this session, you made the changes, you produced the investigation or draft, the user explained the intent), run both judgments.

## Steps

### 1. Collect the items to verify

Fetch the target according to its source:

- Text pasted directly into the chat: use as-is
- A file (draft, report, notes): read it
- GitHub PR review comments: different comment kinds live behind different APIs, so do not grab the wrong one
  - Inline comments (anchored to file/line): `gh api repos/{owner}/{repo}/pulls/{number}/comments`
  - Review bodies (overall summary): `gh api repos/{owner}/{repo}/pulls/{number}/reviews`
  - PR-level comments not anchored to a line (including lint bots): `gh pr view {number} --comments`
- A GitHub PR body as a draft: `gh pr view {number} --json title,body`, with the diff (`gh pr diff {number}`) as its source material
- Output produced earlier in this session (a deep-review/codex-review finding list, an investigation answer, a draft): reuse it verbatim
- Ask the user only when the source is ambiguous

Then break the target into items per its kind:

- Review findings: one item per point. If one comment mixes several points, split it
- Investigation result: one item per atomic factual claim the conclusion depends on ("X calls Y", "this flag defaults to Z", "the bug starts at commit abc"). Skip opinions and recommendations themselves, but extract the facts they rest on. Keep any source the result cites as the item's pointer
- Draft: one item per factual claim (behavior, numbers, names, links, commands, "this PR changes A and B"). When the draft summarizes known source material (a diff, a ticket, meeting notes, an investigation), add one coverage item per source: "the draft omits nothing important from and contradicts nothing in `<source>`"

Record each item as `{id, claim, source: file[:line] / URL / ticket / command (if any), suggestion: proposed change (if any)}`.

Always assign `id` as `F1`, `F2`, ... . It is the only key for matching a judging subagent's output back to the original item; never match by summary text.

### 2. Split the judging subagents into batches

Skip this step and step 3's delegation when you have no context (see above); judge the items yourself and go to step 4.

Decide in this order; earlier rules win over later ones.

1. Multiple items about the same file/location or the same fact must go in the same batch (so duplicate judgments stay consistent). Never split that group
2. Keeping those groups intact, aim for about 5 items per batch. A coverage item gets a batch of its own, since it means reading the whole source
3. If that still fits in fewer than 6 batches (i.e. the rest are all standalone items), a standalone item may get its own subagent
4. Cap parallelism at 8. If it does not fit in 8 batches, raise the per-batch count to pack into 8 parallel subagents (never go to 9+ batches)

If there are more than 40 items, each subagent's share grows and judgments get shallow, so first ask the user whether to narrow the set (by severity, source or section) or run the whole set across several passes.

Launch all batches **in parallel** using the mechanism in "Subagents". Never one batch at a time when parallelism is available.

### 3. Ask for the verdicts

Launch one read-only subagent per batch, described as `double-check batch #<N>`. Pass only the item text and source pointers in the prompt; say nothing about the history, the reasoning behind the target, or who produced it. Use this prompt:

```
Judge independently whether each of the following items holds, by checking the primary sources yourself. You are given no background about who wrote them or why. That is intentional: base your verdict solely on what the sources actually say now.

You are read-only. Never edit files or run commands that change state. You may read files, search the repository, run read-only commands (git log/show/blame, --help, listing commands), and read documentation or web pages.

[Required steps]
1. Always open and check each item's SOURCE. Never judge from the item text alone
2. For a file location, read around it (roughly 30 lines either side), and if needed the callers, type definitions, and related files. For a URL, ticket or command, fetch it or run it and read the result
3. Check whether the target of the item still exists. If it was already changed/removed after the item was written and the target is gone, mark it STALE
4. For items with no SOURCE (design-level points, claims with no citation, findings not anchored to a line), locate the relevant source yourself by searching the repository or the documentation, then judge. Only if you cannot locate it, mark UNVERIFIABLE and write in REASON what you searched for and did not find
5. For a coverage item, read the whole source material and list what the text omits or contradicts. Minor details the text reasonably left out do not count

[Verdict criteria] VERDICT is exclusive. When torn, apply this priority order
- STALE: the thing the item points at has been changed/removed and no longer exists
- INVALID: the target exists but the item does not hold (false positive, wrong premise, misread spec, implementation or doc)
- PARTIALLY_VALID: only part of the item holds (state clearly which part does and which does not)
- VALID: the item actually holds against the current sources
- UNVERIFIABLE: judging requires knowledge or access you do not have and cannot be settled from the sources

[Output format] For each item, write the ID exactly as given in the input on the ID line. Never rewrite an ID or replace it with a summary:
---
ID: <the ID given in the input, e.g. F1>
VERDICT: VALID|INVALID|PARTIALLY_VALID|STALE|UNVERIFIABLE
CLAIM: <summary of the item>
SOURCE: <file:line, URL, ticket or command you checked. If not in the item and you located it yourself, that. N/A if not located>
EVIDENCE: <quotes/line ranges/output from the sources you checked. UNREAD if you could not check any>
REASON: <why you judged this way, citing the concrete content of the sources>
CORRECTION: <for INVALID / PARTIALLY_VALID claims of fact, what the sources actually say; for a coverage item, the omissions and contradictions. N/A otherwise>
---

Output every item assigned to you without exception. Items you could not judge must still be emitted as UNVERIFIABLE; never silently drop one.

Items:
<paste this batch's items here, listing id/claim/source/suggestion verbatim>
```

### 3b. Make the context-aware judgment

Skip this step when you have no context (see above).

Once the subagents of step 3 are launched, judge every item yourself, using what this conversation knows. Finish and record all of your verdicts **before reading any subagent output**, so the two judgments stay independent.

- Follow the same required steps, verdict criteria and output format as the prompt in step 3. Check the real sources; the context adds to the source check and never replaces it
- Add one line per item, `CONTEXT: <the fact from this conversation the verdict depends on, and where it came from (user's statement, spec, ticket, earlier finding)>`, or `CONTEXT: NONE` when the verdict rests on the sources alone
- Your own reasons for having written the code or text a certain way, or for having reached a conclusion, are not a fact. Treat them as the bias this skill exists to remove, and do not cite them in CONTEXT

### 4. Aggregate and present to the user

Aggregate only after every subagent has returned. Match each output back to the original item by `ID`, and check that every input ID came back. Include any missing ID in the list as UNVERIFIABLE, stating explicitly that no verdict was returned.

When step 3b ran, reconcile the two verdicts per ID into one final verdict:

1. Same verdict: adopt it
2. Different verdicts: re-check the sources at both EVIDENCE locations. If one side misread a source (quote does not match, wrong location, missed caller or guard, outdated doc), adopt the other side
3. Otherwise, if the context-aware verdict has a CONTEXT that the sources cannot show (a requirement or decision the user stated, a spec, a ticket), adopt it and cite that source in the reason
4. Anything still split is DISPUTED: keep both verdicts and reasons and leave the call to the user

Present as plain Markdown text, grouped by final verdict:

1. VALID / PARTIALLY_VALID items (id, source, claim, evidence, reason)
2. INVALID items with the reason and the correction
3. STALE items (noting they are already handled or out of date)
4. UNVERIFIABLE items (what could not be determined)
5. DISPUTED items (both verdicts and what each rests on)

Wording follows the kind: for review findings, VALID means "the problem exists"; for investigation results and drafts, INVALID means "this claim is wrong" and is usually the group the user cares about most, so put it first for those kinds. For a coverage item, list the omissions and contradictions found.

For items settled by rule 2 or 3, state which judgment was adopted and why. DISPUTED items are outside the scope of steps 4b and 5.

Without `--fix` or `--post`, **stop here and do not proceed further**, leaving the decision to act to the user. With `--fix` and/or `--post`, present this list first and then continue to step 4b and/or step 5 in the same turn.

### 4b. Post pending PR review comments (`--post` only)

Only run this when `--post` was given and the target is review findings on a GitHub PR. Skip it entirely otherwise (per the Flags section above).

Delegate the actual posting procedure to the [[pending-review-comments]] skill; that skill owns the pending-state rules, dedupe against existing comments, and error handling. Prepare its input as follows:

- Scope: VALID findings, plus the parts of PARTIALLY_VALID findings that the judge said hold. Never pass INVALID, STALE, or UNVERIFIABLE findings
- Pass each finding with `SOURCE` / `CLAIM` / `EVIDENCE` / `REASON` aligned to that skill's expected input (file path, line, and body at minimum)
- For each finding, pass `<kind>` as the finding's own category or perspective where the source review supplied one, and `<grade>` as the verdict (`VALID` / `PARTIALLY_VALID`). Where the source review supplied no category, pass `<grade>` only and let the label line carry the verdict alone. Never pass the skill name as `<kind>`; the comment head format belongs to [[pending-review-comments]]
- Include the evidence quotes in the comment body where available

After posting, report the result (posted / skipped / excluded as duplicates, per that skill's report format). If `--fix` was also given, continue to step 5 next in the same turn; otherwise finish here.

### 5. Apply the result (`--fix` only)

Only run this when `--fix` was given. Skip it entirely otherwise.

What gets changed depends on the kind:

- Review findings: fix the code for VALID findings and the holding parts of PARTIALLY_VALID ones
- Investigation result: rewrite the result with every INVALID / PARTIALLY_VALID claim replaced by its CORRECTION, and re-check whether the conclusion still follows. If it no longer does, say so plainly rather than patching around it
- Draft: edit the draft (the file, or the text in chat if it only lives there) so every INVALID / PARTIALLY_VALID claim matches its CORRECTION, and add or fix what a coverage item reported. For a draft that is already posted (a PR body, an issue), present the corrected text and leave updating it to the user's approval

Rules for every kind:

1. **Never act on INVALID findings, STALE, or UNVERIFIABLE items**, which is the whole point of having verified them. If you believe an INVALID finding is worth fixing anyway, say so in the report and leave the code alone. UNVERIFIABLE claims in an investigation result or draft stay as they are, but name them in the report so the user can decide whether to soften or drop them
2. Make the edits yourself. Never delegate the edit to a subagent
3. Apply the substance, not the source's wording: `suggestion` is a proposal, and where the surrounding code or text implies a better fix, take that and note the difference. Keep each change to the smallest one that resolves the item; do not fold in unrelated refactoring or rewording
4. If two items on the same location conflict, do not apply both. Report the conflict and apply only the one supported by the stronger evidence
5. If a change turns out to need a decision the user has not made (API change, behavior change, dependency addition, a different conclusion), stop that one item, leave it unchanged, and report why. Keep applying the rest
6. Verify what you changed: for code, run the project's tests/lint/typecheck if they exist and are cheap to run, otherwise re-read the edited region; for text, re-read the edited parts against the EVIDENCE. Report failures verbatim; never claim a change is verified when it is not

Then report per item id: changed / skipped (with reason) / needs a decision, followed by the verification result. If nothing was verified by a test run, say so explicitly.

## Notes

- Never include steering information in the judging prompt, such as "the reviewer is trustworthy", "this came from an AI review tool" or "I investigated this carefully". Pass only the item text and source pointers
- Judging subagents **never write**. Changes are made by the orchestrator (you)
- Never assign the same item to more than one judging subagent (batch so that items do not overlap). The context-aware judgment in step 3b covers every item on top of that
- If an item is too coarse (one comment or sentence mixing several points), split it per point before assigning

## Error Handling

- **Output format not followed**: extract by matching the `VERDICT:` line loosely. A verdict with no recoverable ID cannot be tied back to an item, so do not adopt it; present that item as UNVERIFIABLE
- **An item got no verdict**: include the missing ID as UNVERIFIABLE. Never fabricate a verdict or silently drop the item
- **The subagent call itself failed**: re-run that batch once. If the retry also fails, present its items explicitly as "could not be judged". Never discard the other batches' results
- **A verdict with EVIDENCE: UNREAD**: it was produced without checking any source, so do not adopt it as-is; present it marked "unverified". Re-submit any VALID-but-UNREAD item on its own to another subagent for a second judgment (at most once)
- **Target file does not exist**: it may have been renamed/moved, so look for it by searching the repository; if still not found, mark STALE
