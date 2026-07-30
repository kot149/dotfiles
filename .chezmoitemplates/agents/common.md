## Language and response style

- Think in English. Use 日本語 when talking to the user (chat replies, questions, status updates). Exceptions where English output is fine: translation-to-English tasks, and edits to files that are already written in English (code comments, docs, commit messages, PR descriptions in English-language repos, etc.), match the surrounding language.
- Do not insert unnecessary spaces between Japanese text and English words or identifiers. Use natural Japanese spacing, for example: `Claude Codeの設定`, `GitHub Actionsのジョブ`, `APIレスポンス`, `ユーザーID`. Exception: always put spaces before and after links and file paths so they do not get merged into surrounding text and break.
- Do not generate text containing em dashes (`—`) in principle. Use commas, parentheses, or separate sentences instead. This applies to all generated content including code comments, commit messages, PR descriptions, documentation, and chat responses.
- Avoid writing excessively long text in code (comments, docstrings) and commit messages. Keep them concise and focused on the necessary information only.

## Tools

- Invoke shell commands by their bare name (`ls`, `find`, `grep`), never by absolute path (`/bin/ls`, `/usr/bin/find`). Absolute paths bypass the permission allowlist and force a manual approval prompt. If a shell alias or function shadows the command, use `command ls` or `\ls` instead. Prefer the dedicated Read, Glob, and Grep tools over shelling out for file reads and searches in the first place.
- Use GitHub CLI (`gh` command) to interact with GitHub.
- Use `jq` or `yq` to parse JSON, YAML, TOML, XML, CSV or other structured data formats when needed.
- When adding a package or changing a package version in manifests like `package.json`, `pyproject.toml`, or `Cargo.toml`, prefer running the package manager's command (e.g. `npm install`, `uv add`, `cargo add`) over editing the file directly. When initializing a project, use the `init` command or a `create-xxx-app` scaffolder instead of hand-creating files.
- Do not install packages using system package managers (`brew`, `winget`, `apt`, `apt-get`, `dnf`, `yum`, `pacman`, `choco`, `scoop`, etc.) on your own. Always ask the user for confirmation before running such install commands. The user prefers Nix (`nix profile install`, Home Manager, etc.) over `apt`, `brew`, and other system package managers, so prioritize Nix-based approaches when suggesting how to install something.

## Git

- Do not add co-authored-by lines to commit messages without the user's permission.
- Do not include issue numbers in branch names (e.g. `issue-20`, `fix-123`) in principle. Use a short descriptive slug instead (e.g. `fix-login-redirect`). Exception: when the project rules require it, or when there is a clear reason to include it (existing convention in the repo, tooling that keys off the number, etc.).

## Documentation

- When writing or updating documents (README, design docs, specs, wiki pages, etc.), keep only the latest correct state. Unless explicitly asked to record history, do not leave change logs, revision notes, or corrections such as "Correction: X was wrong", "Previously we used Y", "Updated on 2026-01-01", or "This section was rewritten". Rewrite the affected part so it simply describes how things are now.
- Exceptions: files whose purpose is history (CHANGELOG, release notes, ADRs, meeting minutes, postmortems) and cases where the user explicitly asks to keep the old content.

## Code editing

- Do not leave meta-comments about the edit itself in code you write or modify. A comment must describe what the code IS or WHY it exists in its final state, never the history of the edit, the diff from a previous version, or the assistant's activity. Before finalizing changes, scan for and remove any comment that only makes sense while reviewing the diff, including but not limited to:
    - Additions and deletions: `// Added foo`, `# Removed old handler`, `// New: retry logic`
    - Rename, move, extraction: `// Renamed from bar`, `// Moved from utils.ts`, `// Extracted into helper()`
    - Comparison with prior code: `// Now uses async`, `// Changed from sync to async`, `// Previously returned null`
    - Replacement or deprecation notes tied to this edit: `// Replaces the old handler`, `// No longer needed`, `// Superseded by X`
    - References to the user's request or conversation: `// As requested`, `// Per feedback`, `// Fix for the bug you mentioned`, `// TODO from the plan above`
    - Narration of the assistant's work: `// Fixed the bug`, `// Refactored for clarity`, `// Cleaned up imports`
  Do NOT remove or alter comments that already existed in the codebase, even if they look like meta-comments; only apply this rule to comments you are about to write or have just written.
