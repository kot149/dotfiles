---
name: retcon-plan
description: Rewrite a plan (implementation plan or design document) end-to-end as if its final design had been the plan from the start. Produces a document a new reader with zero knowledge of the conversation history can follow, stripping out leftover deliberation debris like "we decided not to do X" or "originally we did X, but". Use when the user asks to rewrite a plan, clean up a plan, or remove the history from a plan.
---

# retcon-plan

Plans accumulate deliberation debris as they go through rounds of discussion: "we considered X but decided against it", "originally it was X, but now it's Y". This makes sense to the person who lived through the discussion, but is either meaningless or pure noise to a reader who wasn't there.

## Steps

1. Identify the target plan. If the user hasn't specified one, use the plan document being edited in the immediately preceding conversation.
2. Rewrite the plan completely using this framing:

> Rewrite the final design end-to-end as if it had been planned this way from the start.
>
> The reader is a new participant with zero knowledge of this conversation's history. Do not leave any sentence that only makes sense with that history.

3. Specifically remove the following during the rewrite:

- References to options that were considered but not adopted ("we're not doing X"), unless mentioning the rejected option is necessary to understand the final design
- Chronological / change-history narration ("originally", "at first it was X, but", "revised to", "after the change")
- References to the conversation itself ("per the user's feedback", "based on the review comment")
- The deliberation process itself (comparison logs, the back-and-forth that led to the conclusion)

4. Describe only the final design, steps, and rationale (why), written as if it had always been decided that way. Be concrete wherever concreteness matters: file layout, naming conventions, dependencies, etc.
5. Present the rewritten plan and confirm with the user before moving to the next step.
