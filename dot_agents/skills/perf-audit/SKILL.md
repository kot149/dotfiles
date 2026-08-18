---
name: perf-audit
description: Audit code performance and produce prioritized optimization recommendations without necessarily editing code. Use when the user asks for a performance audit, bottleneck analysis, bundle review, database performance review, API latency review, or memory/performance recommendations.
---

# Performance Audit

Analyze performance and identify optimization opportunities. If the user provides a target, focus on that file, function, directory, subsystem, or performance aspect.

## Audit Areas

- Algorithm and data structure complexity
- Memory leaks, excessive allocations, and inefficient data structures
- Database queries, indexes, joins, ORM behavior, and N+1 patterns
- Frontend bundle size, rendering, layout thrashing, and user experience metrics
- Backend response paths, caching, async usage, and resource management
- Network behavior, compression, lazy loading, and request fan-out

## Deliverables

1. Priority recommendations ranked by impact and implementation effort.
2. Concrete evidence with file and line references where possible.
3. Before/after examples for key optimizations when useful.
4. Measurement suggestions for verifying improvements.

## Guardrails

- Prefer recommendations over code edits unless the user explicitly asks for implementation.
- Distinguish measured findings from inferred risks.
- Avoid broad rewrites without profiling evidence.
