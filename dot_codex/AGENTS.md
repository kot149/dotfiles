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

- Do not leave meta-comments about the edit itself in code you write or modify. A comment must describe what the code IS or WHY it exists in its final state, never the history of the edit, the diff from a previous version, or the assistant's activity. Before finalizing changes, scan for and remove any comment that only makes sense while reviewing the diff, including but not limited to:
    - Additions and deletions: `// Added foo`, `# Removed old handler`, `// New: retry logic`
    - Rename, move, extraction: `// Renamed from bar`, `// Moved from utils.ts`, `// Extracted into helper()`
    - Comparison with prior code: `// Now uses async`, `// Changed from sync to async`, `// Previously returned null`
    - Replacement or deprecation notes tied to this edit: `// Replaces the old handler`, `// No longer needed`, `// Superseded by X`
    - References to the user's request or conversation: `// As requested`, `// Per feedback`, `// Fix for the bug you mentioned`, `// TODO from the plan above`
    - Narration of the assistant's work: `// Fixed the bug`, `// Refactored for clarity`, `// Cleaned up imports`
  Do NOT remove or alter comments that already existed in the codebase, even if they look like meta-comments; only apply this rule to comments you are about to write or have just written.

@~/.codex/RTK.md
