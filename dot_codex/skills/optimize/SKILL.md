---
name: optimize
description: Analyze a specified target for performance issues and apply safe localized optimizations directly. Use when the user asks to optimize code, improve performance, reduce memory use, speed up a hot path, or review a specific file/function for efficient implementation.
---

# Optimize

Apply safe optimizations directly for low-risk localized changes. For larger, speculative, or API-changing work, provide recommendations instead of editing.

## Analysis Scope

Inspect the target for:

- algorithmic inefficiency, especially avoidable O(n^2) or worse behavior
- redundant computation inside loops
- unnecessary allocations, copies, or large intermediate structures
- avoidable linear scans where sets or maps fit
- sequential async work that can safely run concurrently
- blocking I/O on hot paths
- N+1 database or API access patterns
- inefficient string handling or runtime-specific anti-patterns

## Decision Criteria

Apply changes directly when:

- the fix is localized to one function or a few lines
- behavior is clearly equivalent
- no new dependency is needed
- regression risk is low

Only propose changes when:

- the refactor spans multiple modules
- public APIs, schemas, or contracts would change
- a new library or architecture change is required
- the expected gain is speculative without profiling

## Output

Report:

1. one-sentence summary
2. issues found, ordered by estimated impact
3. changes applied
4. suggestions not applied
5. measurement advice, such as benchmarks, profiler steps, or metrics to watch
