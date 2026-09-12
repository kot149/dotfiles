---
name: bugfix
description: Reproduce, diagnose, fix, and verify a reported bug. Use when the user asks to fix a bug, investigate an error, resolve a regression, debug failing behavior, or apply a minimal code change for a concrete defect.
---

# Fix Bug

## Goal

Reproduce the reported bug, identify the root cause, apply the minimal fix, and verify the fix.

Treat the user's prompt as the bug description. Preserve unrelated worktree changes.

## Steps

1. Reproduce: Understand the report and set up the smallest reproduction. Confirm the bug is reproducible before changing code when feasible.
2. Diagnose: Trace the relevant code path and identify the root cause. For UI or browser behavior, use the available browser automation skill or local browser tooling when applicable. Browse official or primary documentation when current framework behavior matters.
3. Fix: Apply the smallest behavior-preserving change that addresses the root cause. Avoid unrelated refactors.
4. Test: Run existing targeted tests. Add or update a focused regression test when the codebase has a clear test pattern.
5. Repeat: If verification surfaces a new failure, restart from reproduction for the new symptom.
6. Report: Summarize the root cause, the fix, and verification results.

## Output

Keep the final answer concise. Include changed files, root cause, and tests run. If something could not be reproduced or verified, state that plainly.
