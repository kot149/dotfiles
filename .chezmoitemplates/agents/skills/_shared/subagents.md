A **subagent** is a child agent with its own context that cannot see this conversation. Map it onto whatever the running agent provides.

- Claude Code: the `Agent` tool. Use `subagent_type: "Explore"` for a role that only reads, and `general-purpose` for a role that has to run commands. Put several `Agent` calls in one message to run them in parallel
- Codex CLI: issue as many `spawn_agent` calls as needed, then `wait` (requires `features.multi_agent`; pick the role from `[agents]` in `config.toml`, a read-only one wherever the role only reads)

Whatever the mechanism, all of the following must hold.

- The subagent starts from a **fresh context**. Pass it the facts it needs rather than assuming it saw anything from this conversation
- A role that only reads is **read-only**. Where the agent cannot enforce that, state the prohibition in the prompt and make every edit yourself
- **Do not pass conversation context**, meaning narratives from the ongoing work such as "I wrote it this way with such intent". Passing it lets the subagent reuse it as a reason not to flag something. The only things you may pass are primary sources: the PR body, tickets, convention documents, in-code comments
- Where a step says to run several subagents in parallel, use the agent's parallel mechanism. Where it has none, run them sequentially and say so in the final report
