---
name: add-slash-command
description: Create a reusable Codex skill from a user-described workflow, especially when the user asks to add a custom slash-command-like workflow, migrate a Claude Code command, or define a repeatable command for Codex. Use when the user asks for a new command, skill, workflow shortcut, or dotfile-managed Codex capability.
---

# Add Slash Command

Codex CLI does not currently support arbitrary user-defined slash commands in the same way Claude Code command files do. Implement repeatable workflows as skills instead.

## Workflow

1. Gather the skill name, purpose, trigger conditions, expected inputs, and expected output. If any of these are missing, ask before writing files.
2. Confirm the save location. Prefer `~/.agents/skills/<skill-name>` for immediate local use, the shared store Codex reads. In this chezmoi-managed dotfiles repository, prefer `dot_agents/skills/<skill-name>` so it applies to `~/.agents/skills/<skill-name>` after chezmoi apply.
3. Show the proposed `SKILL.md` content, then write it.
4. Create one directory named with lowercase hyphen-case and a required `SKILL.md`.
5. Add `agents/openai.yaml` when practical so the skill has readable UI metadata.
6. Validate the result by hand:
   - the frontmatter parses and holds only `name` and `description`
   - `name` matches the directory name, lowercase with hyphens
   - `description` is non-empty and names the trigger conditions
   - in this chezmoi repository, `just skills-lint` checks the same things across the whole tree

## Writing Rules

- Use YAML frontmatter with only `name` and `description`.
- Put all trigger conditions in `description`; the body is loaded only after the skill triggers.
- Keep instructions concise, imperative, and actionable.
- Convert slash-command arguments into normal prompt context. Do not mention `$ARGUMENTS` unless preserving compatibility with a migrated Claude command is necessary.
- Use `scripts/`, `references/`, or `assets/` only when they directly support the workflow.
