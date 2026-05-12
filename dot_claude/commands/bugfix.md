# Fix Bug

## Goal

Reproduce the reported bug, identify the root cause, apply a fix, and verify the fix.

## Bug Description

$ARGUMENTS

## Steps (obey strictly)

Step 1: **Reproduce** — Understand the bug description. Set up conditions to reproduce the issue. Confirm the bug is reproducible before proceeding.

Step 2: **Identify root cause** — Analyze the code path involved in the bug. Use the agent-browse skill or the `Playwright` MCP tool to inspect browser behavior if the bug involves UI or browser interactions. Use web search to find similar issues or relevant documentation.

Step 3: **Fix** — Apply the minimal change needed to resolve the root cause. Avoid unrelated changes.

Step 4: **Verify** — Run existing tests and any relevant test commands to confirm the fix works and no regressions were introduced. If no tests exist for the bug, write one.

Step 5: **Repeat if needed** — If a new error surfaces after the fix, restart from Step 1 with the new error.

Step 6: **Report** — Summarize the root cause and the solution applied.
