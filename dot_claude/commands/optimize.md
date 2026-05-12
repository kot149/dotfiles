Analyze the following target for performance issues and apply safe optimizations directly. For larger or riskier changes, provide detailed suggestions instead of modifying code.

**Target**: $ARGUMENTS (if not specified, analyze the current file or the most recently discussed code)

---

## Analysis Scope

Examine the target across these dimensions:

**Algorithmic Efficiency**
- Time complexity: identify O(n²) or worse loops that could be reduced
- Redundant computations inside loops (hoist invariants)
- Unnecessary repeated work (memoization / caching opportunities)
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
- Sequential async calls that can be parallelized (Promise.all, etc.)
- Blocking operations on the main thread / hot path
- Unnecessary serialization / deserialization
- N+1 query patterns in database or API access

**Language / Runtime Specifics**
- Inefficient string concatenation in loops
- Type coercions or unnecessary boxing/unboxing
- Missed compiler/interpreter hints (type annotations, frozen objects, etc.)
- Suboptimal use of standard-library functions vs. hand-rolled equivalents

---

## Decision Criteria

**Apply the change directly** when:
- The fix is localized to a single function or a few lines
- Behavior is clearly equivalent (pure refactor, no interface change)
- No new dependencies are introduced
- Risk of regression is low

**Propose the change (do not modify code)** when:
- The refactor spans multiple files or modules
- The fix requires changing a public API or data schema
- A new library or significant architectural shift is involved
- The performance gain is speculative and requires profiling to confirm

---

## Output Format

1. **Summary** — one-sentence overall assessment
2. **Issues found** — bullet list ordered by estimated impact (high → low); each item states the problem, root cause, and expected improvement
3. **Applied changes** — diff or description of every change made directly
4. **Suggestions** — proposed changes not applied, with enough detail to implement independently
5. **Measurement advice** — how to verify the improvement (benchmark, profiler, metric to watch)
