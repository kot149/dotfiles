---
name: lint-fix
description: Detect and fix linting, formatting, and static-analysis issues in a project. Use when the user asks to fix lint errors, run formatters, resolve clippy/ruff/eslint/prettier issues, or clean style violations in a file, directory, or whole repository.
---

# Lint Fix

If the user provides a target, restrict work to that file or directory where tooling allows. Otherwise target the project.

## Workflow

1. Inspect the repository for lint and format configuration such as `package.json`, `.eslintrc`, `eslint.config.*`, `.prettierrc`, `pyproject.toml`, `.ruff.toml`, `Cargo.toml`, `go.mod`, `Makefile`, or CI configuration.
2. Identify the package manager or language toolchain from lockfiles and existing scripts.
3. Run available auto-fix commands first, such as `eslint --fix`, `prettier --write`, `ruff check --fix`, `cargo fmt`, `cargo clippy --fix`, `gofmt`, or project-specific scripts.
4. Re-run linters to find remaining issues.
5. Apply manual fixes for remaining lint failures while preserving behavior.
6. Report what was fixed and list any remaining issues that need user attention.

## Guardrails

- Prefer project-defined scripts over inventing commands.
- Keep formatting-only churn scoped to the requested target when possible.
- Do not make unrelated refactors while fixing lint.
