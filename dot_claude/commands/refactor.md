# Refactor

Analyze and refactor the codebase to improve code quality, readability, and maintainability. If `$ARGUMENTS` is provided, focus on the specific file, function, or directory mentioned.

## Tasks to perform:
1. **Identify refactoring opportunities**: Look for code smells, duplicated code, overly complex functions, and areas that violate SOLID principles
2. **Apply refactoring techniques**: Extract methods, rename variables for clarity, simplify complex expressions, reduce nesting levels
3. **Improve code structure**: Reorganize imports, group related functionality, separate concerns
4. **Maintain functionality**: Ensure all refactoring preserves existing behavior - run tests if available
5. **Follow project conventions**: Maintain existing code style, naming patterns, and architectural decisions

## Examples:
- `/refactor` - Refactor the entire project
- `/refactor src/utils.js` - Refactor specific file
- `/refactor UserService` - Refactor specific class or function
- `/refactor src/components/` - Refactor specific directory

## Focus areas:
- Extract duplicate code into reusable functions
- Simplify complex conditional logic
- Improve variable and function naming
- Reduce function complexity and length
- Remove dead code and unused imports
- Optimize data structures and algorithms where appropriate

Always explain the refactoring changes made and why they improve the code.