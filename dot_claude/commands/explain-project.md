# Explain project high-level architecture

Use multiple subagents to analyze the repository. Do not run the project; only read and inspect it.

## Goal

Produce a thorough explanation of how this project works and its high-level architecture.
If `$ARGUMENTS` is provided (e.g. a specific subsystem, component, or perspective), focus the analysis accordingly while still covering the broader context as needed.

## Steps

Step 1. Analyse the repository to capture:
   - project name & purpose
   - runtime entry points
   - primary modules/services
   - data flow
   - external dependencies
   - infrastructure
   - deployment specifics
   - if `$ARGUMENTS` is given, pay particular attention to that area

Step 2. Output Markdown only — no commentary outside the sections — with these sections exactly in order. Keep writing purposeful; avoid fluff. **Always write in Japanese.**

   1. Project Name – bold text
   2. Overview – concise paragraph (≤ 160 words)
   3. Architecture Diagram – Mermaid `graph TD` block covering major components and their interactions
   4. Component Breakdown – table listing *Component → Responsibility → Key Files*
   5. Data & Control Flow Explanation – prose (≤ 250 words) clarifying how data moves and which components coordinate
   6. Tech Stacks – bullets providing a tech stack overview (build tools, languages, frameworks, infrastructure)
