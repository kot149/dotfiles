## Language and response style

- Think in English. Use 日本語 when talking to the user (chat replies, questions, status updates). Exceptions where English output is fine: translation-to-English tasks, and edits to files that are already written in English (code comments, docs, commit messages, PR descriptions in English-language repos, etc.), match the surrounding language.
- Do not insert unnecessary spaces between Japanese text and English words or identifiers. Use natural Japanese spacing, for example: `Claude Codeの設定`, `GitHub Actionsのジョブ`, `APIレスポンス`, `ユーザーID`. Exception: always put spaces before and after links and file paths so they do not get merged into surrounding text and break.
- Do not generate text containing em dashes (`—`) in principle. Use commas, parentheses, or separate sentences instead. This applies to all generated content including code comments, commit messages, PR descriptions, documentation, and chat responses.
- Avoid writing excessively long text in code (comments, docstrings) and commit messages. Keep them concise and focused on the necessary information only.

## Tools

- Use GitHub CLI (`gh` command) to interact with GitHub.
- Use `jq` or `yq` to parse JSON, YAML, TOML, XML, CSV or other structured data formats when needed.
- When adding a package or changing a package version in manifests like `package.json`, `pyproject.toml`, or `Cargo.toml`, prefer running the package manager's command (e.g. `npm install`, `uv add`, `cargo add`) over editing the file directly. When initializing a project, use the `init` command or a `create-xxx-app` scaffolder instead of hand-creating files.
- Do not install packages using system package managers (`brew`, `winget`, `apt`, `apt-get`, `dnf`, `yum`, `pacman`, `choco`, `scoop`, etc.) on your own. Always ask the user for confirmation before running such install commands. The user prefers Nix (`nix profile install`, Home Manager, etc.) over `apt`, `brew`, and other system package managers, so prioritize Nix-based approaches when suggesting how to install something.

## Git

- Do not add co-authored-by lines to commit messages without the user's permission.
- Do not include issue numbers in branch names (e.g. `issue-20`, `fix-123`) in principle. Use a short descriptive slug instead (e.g. `fix-login-redirect`). Exception: when the project rules require it, or when there is a clear reason to include it (existing convention in the repo, tooling that keys off the number, etc.).

## Code editing

- Finalize process: Remove ALL meta-comments about your changes, such as `// Added XXX`, `# Removed XXX`, `// XXX has been moved to...` from the code you newly wrote or modified before applying the changes. Do NOT remove or alter comments that already existed in the codebase.

## Claude Code specific

- Never emit user-facing text that must be read (review findings, context for a choice, a diff summary to confirm, etc.) in the same turn as an `AskUserQuestion` call. Known Claude Code bugs (anthropics/claude-code#23862, #74260) cause preceding text to be hidden by the question UI overlay, or dropped entirely from both the display and the session JSONL when the message shape is `thinking → text → thinking → tool_use`. Inserting a dummy tool call (e.g. `Bash true`) between the text and `AskUserQuestion` does NOT help, same-turn text remains at risk. Correct procedure: (1) output the important text as normal Markdown and end the turn with zero tool calls. (2) On the next turn after the user responds, call `AskUserQuestion`. If the user's response already specifies a direction, skip `AskUserQuestion` and act on that instruction directly.
