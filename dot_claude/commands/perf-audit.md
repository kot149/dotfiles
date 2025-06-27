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
### Algorithm & Data Structure
- Time complexity (O(n), O(n²), etc.)
- Space complexity and memory usage
- Inefficient loops and nested operations
- Suboptimal data structure choices

### Database Performance
- N+1 query problems
- Missing indexes
- Inefficient joins and subqueries
- Excessive data fetching

### Frontend Performance
- Bundle size and code splitting
- Unnecessary re-renders
- Large image/asset sizes
- Blocking JavaScript execution
- CSS and layout thrashing

### Backend Performance
- API response times
- Caching opportunities
- Async/await usage
- Resource pooling
- Memory leaks and garbage collection

### Network Performance
- HTTP request optimization
- Compression and minification
- CDN usage
- Lazy loading opportunities

## Deliverables:
1. **Performance report**: Detailed analysis of identified issues
2. **Priority recommendations**: Ranked list of optimizations by impact
3. **Code examples**: Before/after examples of key optimizations
4. **Measurement suggestions**: How to measure improvement after changes
5. **Implementation roadmap**: Step-by-step plan for applying optimizations

Focus on changes that provide the highest performance impact with reasonable implementation effort.