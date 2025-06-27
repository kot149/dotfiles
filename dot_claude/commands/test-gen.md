# Test Generation

Generate comprehensive unit tests for the specified code. If `$ARGUMENTS` is provided, focus on testing the specific file, function, or class mentioned.

## Tasks to perform:
1. **Analyze the target code**: Understand the functionality, inputs, outputs, and edge cases
2. **Identify test framework**: Detect existing test setup (Jest, Mocha, pytest, etc.) and follow project conventions
3. **Generate test cases**: Create tests covering:
   - Happy path scenarios
   - Edge cases and boundary conditions
   - Error handling and validation
   - Mocking external dependencies
4. **Follow testing best practices**: Use descriptive test names, arrange-act-assert pattern, proper assertions
5. **Ensure test coverage**: Aim for comprehensive coverage of the target functionality

## Examples:
- `/test-gen` - Generate tests for recently modified files
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
- Add clear test descriptions and comments
- Ensure tests are runnable with existing test commands

Always verify that generated tests can be executed successfully with the project's test runner.