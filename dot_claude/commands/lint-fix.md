# Lint Fix

Automatically detect and fix linting issues in the codebase using available linters and formatters. If `$ARGUMENTS` is provided, focus on the specific file or directory mentioned.

## Tasks to perform:
1. **Detect linting tools**: Identify available linters (ESLint, Prettier, Ruff, Pylint, etc.) from project configuration
2. **Run linting checks**: Execute linting commands to identify issues
3. **Apply automatic fixes**: Use auto-fix capabilities where available (`--fix`, `--write`, etc.)
4. **Manual fixes**: Address remaining issues that require manual intervention
5. **Verify fixes**: Run linting again to ensure all issues are resolved

## Examples:
- `/lint-fix` - Fix linting issues across the entire project
- `/lint-fix src/components/` - Fix linting issues in specific directory
- `/lint-fix app.js` - Fix linting issues in specific file
- `/lint-fix --staged` - Fix linting issues only in staged files

## Common linting tools and commands:
- **JavaScript/TypeScript**: `npm run lint --fix`, `eslint --fix`, `prettier --write`
- **Python**: `ruff check --fix`, `black .`, `pylint`
- **Go**: `go fmt`, `golint`, `goimports`
- **Rust**: `cargo fmt`, `cargo clippy --fix`
- **CSS/SCSS**: `stylelint --fix`

## Fix categories:
- Code formatting (indentation, spacing, line breaks)
- Import organization and unused imports
- Variable naming conventions
- Semicolon usage
- Quote style consistency
- Trailing whitespace and newlines
- Dead code removal

## Process:
1. Check for project-specific linting configuration files
2. Run appropriate linting commands with auto-fix flags
3. Address any remaining manual fixes needed
4. Report summary of fixes applied
5. Suggest any additional improvements if needed

Always preserve code functionality while applying fixes and follow the project's established style guidelines.