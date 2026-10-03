---
name: explain-project
description: Explain a repository's high-level architecture in Japanese. Use when the user asks how a project works, requests an architecture overview, wants a Mermaid diagram, or asks to understand a specific subsystem, component, runtime path, or data flow.
---

# Explain Project High-Level Architecture

Read and inspect the repository. Do not run the project unless the user explicitly asks or inspection requires generated metadata.

Decide on subagents by the size of the repository: read a large one through several subagents in parallel, one per area, and inspect a small one directly.

## Analysis

Capture:

- project name and purpose
- runtime entry points
- primary modules or services
- data flow and control flow
- external dependencies
- infrastructure and deployment details
- any user-specified focus area

## Output

Write Markdown only, with no commentary outside the sections, in Japanese, with these sections in this order:

1. **Project Name**: bold text
2. **Overview**: concise paragraph, 160 words or less
3. **Architecture Diagram**: Mermaid `graph TD` block covering major components and interactions
4. **Component Breakdown**: table with `Component`, `Responsibility`, and `Key Files`
5. **Data & Control Flow Explanation**: prose, 250 words or less
6. **Tech Stacks**: bullets covering languages, frameworks, build tools, and infrastructure

Avoid filler and avoid implementation changes.
