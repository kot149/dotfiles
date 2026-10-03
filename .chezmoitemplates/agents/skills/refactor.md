---
name: refactor
description: Refactor scoped code to improve readability, maintainability, structure, and naming while preserving behavior. Use when the user asks to refactor a file, function, class, module, directory, or specific code smell. The target is readability and structure, not performance; for performance work use optimize or perf-audit. If no scope is provided, ask the user to narrow the target before editing.
---

# Refactor

Improve code quality while preserving existing behavior.

## Scope Handling

If the user provides a specific file, function, class, module, or directory, proceed within that scope.

If no scope is provided, do not start broad repository refactoring. Ask the user to choose a module, directory, or concern.

## Workflow

1. Identify code smells, duplication, excessive complexity, unclear names, dead code, misplaced responsibilities, and violations of the SOLID principles.
2. Match existing project architecture, naming, and style.
3. Apply behavior-preserving refactors such as extracting helpers, simplifying conditionals, reducing nesting, clarifying names, reorganizing imports, and removing dead code.
4. Avoid public API changes unless the user explicitly approves them.
5. Run the project's tests. Detect the command by checking in this order:
   - `package.json` scripts: `test`, `test:unit`, `test:ci`, run with the package manager the lockfile indicates (`npm` / `yarn` / `pnpm` / `bun`)
   - `Makefile`: a `test` target, run as `make test`
   - Language conventions: `pytest`, `go test ./...`, `cargo test`, `rspec`
   - `CLAUDE.md` / `AGENTS.md` / `README.md`: a documented test command

   Report the result. Where no command is found, say that verification could not be run and describe the remaining risk.
6. Report what changed and why it improves maintainability.

## Guardrails

- Keep edits scoped.
- Do not combine refactoring with feature changes.
- If no test command is available, say that verification could not be run and describe the remaining risk.
