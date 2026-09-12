# Test Generation

Generate comprehensive unit tests for the specified code. If `$ARGUMENTS` is provided, focus on testing the specific file, function, or class mentioned. If no arguments are provided, identify recently modified files using `git diff --name-only HEAD` or `git status` and generate tests for those files.

## Tasks to perform:
1. **Identify target code**: If `$ARGUMENTS` is given, use it as the target. Otherwise, run `git diff --name-only HEAD` (or `git status` for untracked files) to find recently modified files and use them as targets.
2. **Analyze the target code**: Understand the functionality, inputs, outputs, and edge cases
3. **Identify test framework**: Detect existing test setup (Jest, Mocha, pytest, etc.) and follow project conventions
4. **Generate test cases**: Create tests covering:
   - Happy path scenarios
   - Edge cases and boundary conditions
   - Error handling and validation
   - Mocking external dependencies
5. **Follow testing best practices**: Use descriptive test names, arrange-act-assert pattern, proper assertions
6. **Ensure test coverage**: Aim for comprehensive coverage of the target functionality
7. **Run the tests**: Execute the generated tests with the project's test runner and verify they pass

## Examples:
- `/test-gen` - Generate tests for recently modified files (identified via `git diff` or `git status`)
- `/test-gen src/utils.js` - Generate tests for specific file
- `/test-gen calculateTotal` - Generate tests for specific function
- `/test-gen UserService` - Generate tests for specific class

## Test types to consider:
- Unit tests for individual functions
- Integration tests for component interactions
- Property-based tests for complex logic
- Parameterized tests for multiple input scenarios
- Mock tests for external dependencies

## Output:
- Create test files following project naming conventions (e.g., `.test.js`, `.spec.ts`, `_test.py`)
- Include necessary imports, setup, and teardown
- Ensure tests are runnable with existing test commands

Always run the generated tests with the project's test runner and confirm they pass before finishing.
