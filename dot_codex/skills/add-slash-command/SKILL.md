---
name: add-slash-command
description: Create a reusable Codex skill from a user-described workflow, especially when the user asks to add a custom slash-command-like workflow, migrate a Claude Code command, or define a repeatable command for Codex. Use when the user asks for a new command, skill, workflow shortcut, or dotfile-managed Codex capability.
---

# Add Slash Command

Codex CLI does not currently support arbitrary user-defined slash commands in the same way Claude Code command files do. Implement repeatable workflows as skills instead.

## Workflow

1. Gather the skill name, purpose, trigger conditions, expected inputs, and expected output. If any of these are missing, ask before writing files.
2. Confirm the save location. Prefer `~/.codex/skills/<skill-name>` for immediate local use. In this chezmoi-managed dotfiles repository, prefer `dot_codex/skills/<skill-name>` so it applies to `~/.codex/skills/<skill-name>` after chezmoi apply.
3. Draft the proposed `SKILL.md` content and get confirmation before writing if the user did not already ask you to implement directly.
4. Create one directory named with lowercase hyphen-case and a required `SKILL.md`.
5. Add `agents/openai.yaml` when practical so the skill has readable UI metadata.
6. Validate the skill with `quick_validate.py`.

## Writing Rules

- Use YAML frontmatter with only `name` and `description`.
- Put all trigger conditions in `description`; the body is loaded only after the skill triggers.
- Keep instructions concise, imperative, and actionable.
- Convert slash-command arguments into normal prompt context. Do not mention `$ARGUMENTS` unless preserving compatibility with a migrated Claude command is necessary.
- Use `scripts/`, `references/`, or `assets/` only when they directly support the workflow.
