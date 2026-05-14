---
name: refactor
description: Refactor scoped code to improve readability, maintainability, structure, and naming while preserving behavior. Use when the user asks to refactor a file, function, class, module, directory, or specific code smell. If no scope is provided, ask the user to narrow the target before editing.
---

# Refactor

Improve code quality while preserving existing behavior.

## Scope Handling

If the user provides a specific file, function, class, module, or directory, proceed within that scope.

If no scope is provided, do not start broad repository refactoring. Ask the user to choose a module, directory, or concern.

## Workflow

1. Identify code smells, duplication, excessive complexity, unclear names, dead code, and misplaced responsibilities.
2. Match existing project architecture, naming, and style.
3. Apply behavior-preserving refactors such as extracting helpers, simplifying conditionals, reducing nesting, clarifying names, reorganizing imports, and removing dead code.
4. Avoid public API changes unless the user explicitly approves them.
5. Run relevant tests or checks. Detect likely commands from `package.json`, `Makefile`, language conventions, README, or project docs.
6. Report what changed and why it improves maintainability.

## Guardrails

- Keep edits scoped.
- Do not combine refactoring with feature changes.
- If no test command is available, say that verification could not be run and describe the remaining risk.
