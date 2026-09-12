---
name: test-gen
description: Generate and run tests for specified code or recently modified files. Use when the user asks to add tests, generate unit tests, improve test coverage, write regression tests, or test a specific file, function, class, or recent change.
---

# Test Generation

Generate tests following the project's existing conventions.

## Target Selection

If the user provides a target, use it. If not, identify recently modified files with `git diff --name-only HEAD`, `git status --short`, and the current conversation context.

## Workflow

1. Analyze the target code for behavior, inputs, outputs, dependencies, and edge cases.
2. Detect the test framework and naming conventions from existing tests and configuration.
3. Create tests covering happy paths, edge cases, error handling, validation, and external dependency behavior.
4. Use descriptive test names and the project’s preferred structure.
5. Mock external dependencies consistently with existing tests.
6. Run the relevant test command and fix test failures caused by the new tests.
7. Report created test files and verification results.

## Test Types

Consider unit tests, integration tests, parameterized tests, property-based tests, and regression tests when they fit the existing codebase.

## Guardrails

- Prefer focused tests over broad fragile coverage.
- Do not introduce a new test framework unless the user approves.
- If tests cannot be run, state why and provide the exact command that should be run manually.
