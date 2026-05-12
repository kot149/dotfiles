# Refactor

Analyze and refactor the codebase to improve code quality, readability, and maintainability.

## Behavior based on `$ARGUMENTS`:

### When `$ARGUMENTS` is provided
Focus refactoring on the specific file, function, class, or directory specified.

### When `$ARGUMENTS` is NOT provided (entire codebase)
**Do NOT start refactoring immediately.** The scope is too broad and risky. Instead:
1. Ask the user to clarify the scope or specific area they want to refactor
2. Suggest narrowing down to a specific module, directory, or concern
3. Only proceed after the user confirms the intended scope

## Tasks to perform:
1. **Identify refactoring opportunities**: Look for code smells, duplicated code, overly complex functions, and areas that violate SOLID principles
2. **Apply refactoring techniques**: Extract methods, rename variables for clarity, simplify complex expressions, reduce nesting levels
3. **Improve code structure**: Reorganize imports, group related functionality, separate concerns
4. **Maintain functionality**: Ensure all refactoring preserves existing behavior - run tests after changes (see below)
5. **Follow project conventions**: Maintain existing code style, naming patterns, and architectural decisions

## Running tests after refactoring:
Auto-detect the available test command by checking in this order:
- `package.json` scripts: look for `test`, `test:unit`, `test:ci` entries and run with the appropriate package manager (`npm`/`yarn`/`pnpm`/`bun`)
- `Makefile`: look for a `test` target and run `make test`
- Language-specific conventions: `pytest`, `go test ./...`, `cargo test`, `rspec`, etc.
- `CLAUDE.md` or `README.md`: check for documented test instructions

Run the detected test command and report results. If no test command is found, note that tests could not be run and recommend the user verify behavior manually.

## Examples:
- `/refactor` - **Caution**: Will ask for confirmation before proceeding, as the scope is the entire codebase
- `/refactor src/utils.js` - Refactor a specific file
- `/refactor UserService` - Refactor a specific class or function
- `/refactor src/components/` - Refactor a specific directory

## Focus areas:
- Extract duplicate code into reusable functions
- Simplify complex conditional logic
- Improve variable and function naming
- Reduce function complexity and length
- Remove dead code and unused imports
- Optimize data structures and algorithms where appropriate

Always explain the refactoring changes made and why they improve the code.
