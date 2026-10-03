---
name: optimize
description: Analyze a single file or function for performance issues and apply the fix directly. Use when the user asks to optimize code, improve performance, reduce memory use, speed up a hot path, or review a specific file/function for efficient implementation. For a report across a subsystem with no edits, use perf-audit instead.
---

# Optimize

Apply safe optimizations directly for low-risk localized changes. For larger, speculative, or API-changing work, provide recommendations instead of editing.

When the user names a target, work within it. When they do not, work on the file currently under discussion, or the code from the most recent exchange. Say which one you picked before making any change.

## Analysis Scope

Examine the target across these dimensions.

**Algorithmic Efficiency**

- Time complexity: O(n^2) or worse loops that could be reduced
- Redundant computations inside loops (hoist invariants)
- Repeated work that memoization or caching would avoid
- Early-exit conditions that are missing

**Memory Usage**

- Large intermediate allocations that can be avoided or reused
- Data copied when a reference or view would suffice
- Objects or buffers allocated in hot paths that should be pre-allocated
- Memory leaks: resources or event listeners not released

**Data Structures**

- Linear scans (array/list) where a set or map lookup would be O(1)
- Sorted structures used where a heap or priority queue fits better
- Frequent resizing of arrays/lists that could use a pre-sized container

**I/O and Concurrency**

- Sequential async calls that can run concurrently
- Blocking operations on the main thread or a hot path
- Unnecessary serialization / deserialization
- N+1 query patterns in database or API access

**Language / Runtime Specifics**

- Inefficient string concatenation in loops
- Type coercions or unnecessary boxing/unboxing
- Missed compiler/interpreter hints (type annotations, frozen objects, etc.)
- Suboptimal use of standard-library functions vs. hand-rolled equivalents

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
2. issues found, ordered by estimated impact; each states the problem, root cause, and expected improvement
3. changes applied
4. suggestions not applied, with enough detail to implement independently
5. measurement advice, such as benchmarks, profiler steps, or metrics to watch
