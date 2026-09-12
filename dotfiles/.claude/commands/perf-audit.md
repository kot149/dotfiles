# Performance Audit

Analyze code performance and identify optimization opportunities. If `$ARGUMENTS` is provided, focus on the specific file, function, or performance aspect mentioned.

## Tasks to perform:
1. **Analyze code performance**: Identify bottlenecks, inefficient algorithms, and resource-intensive operations
2. **Memory usage review**: Look for memory leaks, excessive object creation, and inefficient data structures
3. **Algorithm optimization**: Suggest more efficient algorithms and data structures
4. **Database performance**: Review queries, indexing, and ORM usage patterns
5. **Frontend performance**: Analyze bundle size, rendering performance, and user experience metrics
6. **Provide actionable recommendations**: Give specific, implementable suggestions with expected impact

## Examples:
- `/perf-audit` - Audit performance across the entire project
- `/perf-audit src/api/` - Audit API performance
- `/perf-audit database queries` - Focus on database performance
- `/perf-audit bundle size` - Analyze frontend bundle performance

## Performance areas to analyze:
- **Algorithm & Data Structure**: Time/space complexity, inefficient loops, suboptimal data structures
- **Database Performance**: N+1 queries, missing indexes, inefficient joins, excessive data fetching
- **Frontend Performance**: Bundle size, unnecessary re-renders, blocking scripts, layout thrashing
- **Backend Performance**: API response times, caching opportunities, async usage, memory leaks
- **Network Performance**: HTTP optimization, compression, lazy loading

## Deliverables:
1. **Priority recommendations**: Ranked list of optimizations by impact
2. **Code examples**: Before/after examples of key optimizations
3. **Measurement suggestions**: How to verify improvement after changes

Focus on changes that provide the highest performance impact with reasonable implementation effort.
