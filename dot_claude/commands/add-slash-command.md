# Add Slash Command

You are tasked with creating a new slash command for Claude Code. Follow these steps:

1. **Ask for command details**: Request the command name and its purpose from the user
2. **Create the command file**: Create a new markdown file at ~/.claude/commands/{command-name}.md
3. **Write effective instructions**: Compose clear, specific instructions in English that will help Claude understand and execute the command effectively
4. **Include examples**: Provide usage examples when appropriate to clarify the command's behavior
5. **Follow best practices**: 
   - Use imperative language ("Do X", "Create Y")
   - Be specific about expected inputs and outputs
   - Include any necessary context or constraints
   - Make instructions actionable and unambiguous

6. **Handle command arguments**: If the command needs to accept arguments, use `$ARGUMENTS` in the markdown file to reference them:
   - `$ARGUMENTS` contains all arguments passed to the command
   - For single argument commands, use `$ARGUMENTS` directly
   - Document what arguments are expected and how they should be used
   - Include examples showing argument usage

The resulting command file should contain instructions that are optimized for AI comprehension and execution, ensuring the slash command works reliably when invoked.

## Examples

### Command without arguments:
```markdown
# My Command
Do something specific without needing user input.
```

### Command with arguments:
```markdown
# My Command
Process the input provided as `$ARGUMENTS`. For example, if the user runs `/my-command 123`, then `$ARGUMENTS` will contain "123".

Use `$ARGUMENTS` to:
- Reference the issue number: `gh issue view $ARGUMENTS`
- Create files with the argument as name: `touch file-$ARGUMENTS.txt`
```