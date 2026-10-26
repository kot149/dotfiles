---
name: commit-delegate
description: Delegate the entire commit workflow to one lightweight subagent, including Git inspection, message selection, staging and committing. Use when asked for commit-delegate, a lightweight/delegated commit, or to save the main agent's commit-related context. For this explicit workflow, use this skill instead of commit in the main agent.
---

# Delegate commits

Keep Git output and commit reasoning out of the main conversation. The main agent coordinates; one lightweight worker owns the entire workflow. Do not load the `commit` skill, inspect Git, read diffs, or generate messages in the main agent.

## Start one lightweight worker

- Claude Code: use a fresh general-purpose subagent with `model: "haiku"` (not Explore; the worker must stage and commit).
- GPT/Codex: use a fresh write-capable subagent configured for `gpt-6-luna`, or the runtime's registered lightweight Luna model/role. Inspect the available agent/model interface before choosing; do not invent a `model` parameter for an interface that does not expose one.
- Other runtimes: explicitly select an available lightweight, write-capable model through their subagent interface.
- Never silently inherit the main model or substitute a larger model. If a lightweight worker cannot be selected, report the missing capability without running the Git workflow in the main agent.
- Use the same working directory and working tree, not a separate worktree. Do not forward conversation history. Pass only the repository path, the user's commit request, explicitly known session-touched paths (or “unknown”), and any explicit message/scope constraints. Do not discover paths with Git in the main agent.

Give the worker this assignment, with the concrete inputs substituted:

> Read `references/worker.md` under this skill's installed directory, then execute it in the supplied repository. You own status, all diffs, history, candidates, user confirmation, staging and commit. Do not delegate further. Keep raw Git output in your context. Return only the compact protocol defined there. Inputs: repository, user request, session-touched paths or unknown, constraints.

Pass the installed skill's absolute directory so the worker can locate the reference regardless of repository cwd. Only the worker reads that reference and the existing `commit` skill.

## Relay confirmation, not investigation

If the worker can interact with the user, let it handle message selection and wait for its final result. Otherwise:

1. Receive only `CHOICE`: three messages, short rationales, recommended index, and any scope warning. No diff or file listing unless needed for a scope decision.
2. Present those candidates via the runtime's selection UI, with full message labels, one selection, and the question `どのコミットメッセージを使いますか？`. Without a selection UI, ask using a numbered list. Do not choose on the user's behalf.
3. Resume the **same worker** with the selected message verbatim, custom text, or cancellation. Do not start a fresh worker or run Git yourself. Strip only the UI's recommendation suffix, never alter custom text.
4. If the worker reports changed scope/content and needs renewed approval, relay its new choice; previous approval is not valid for a changed payload.

On completion, relay only the worker's commit hash/subject and essential warnings, or its cancellation/no-changes/blocker notice, in Japanese. Never request its transcript, full analysis or raw Git output. This reduces main-context use; coordination and user-choice messages still consume tokens.
