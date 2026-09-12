# Lint Fix

Detect and fix linting issues in the codebase. If `$ARGUMENTS` is provided, restrict the scope to that file or directory; otherwise target the entire project.

## Steps

1. Inspect the project root for linting configuration files (e.g., `.eslintrc`, `pyproject.toml`, `.ruff.toml`, `Cargo.toml`) to determine which tools are available.
2. Run linting commands with auto-fix flags for all detected tools (e.g., `eslint --fix`, `prettier --write`, `ruff check --fix`, `cargo fmt && cargo clippy --fix`).
3. Re-run the linters to check for remaining issues.
4. For any issues that could not be fixed automatically, apply manual fixes while preserving existing functionality.
5. Report a summary of what was fixed and note any issues that require further attention.

Follow the project's established style guidelines throughout.
