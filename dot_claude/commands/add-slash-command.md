# Add Slash Command

You are tasked with creating a new slash command for Claude Code. Follow these steps:

1. **Gather command details**: Ask the user for the command name and its purpose before doing anything else.

2. **Confirm the save location**: Ask the user where to save the command file. Present these options:
   - `~/.claude/commands/{command-name}.md` — applies immediately to the current user
   - `/home/ku0143/.local/share/chezmoi/dot_claude/commands/{command-name}.md` — use this if the user manages dotfiles with chezmoi, so the file is version-controlled and synced across machines

3. **Draft and confirm**: Show the user the proposed file content before writing it, and ask for confirmation.

4. **Create the command file**: Write the markdown file to the confirmed path.

## Writing effective command instructions

- Use imperative language ("Do X", "Create Y")
- Be specific about expected inputs, outputs, and constraints
- Include usage examples when the behavior might be ambiguous
- Keep instructions concise and actionable

## Handling arguments

If the command accepts arguments, use `$ARGUMENTS` to reference them in the file:

- `$ARGUMENTS` contains everything passed after the command name
- Document what arguments are expected and their format
- Show examples of how `$ARGUMENTS` is used

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
- View an issue: `gh issue view $ARGUMENTS`
- Create a file: `touch file-$ARGUMENTS.txt`
```
