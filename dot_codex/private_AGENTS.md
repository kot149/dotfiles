- Think in English, respond in 日本語
- Use GitHub CLI (`gh` command) to interact with GitHub
- Use `jq` or `yq` to parse JSON, YAML, TOML, XML, CSV or other structured data formats when needed
- Do not add co-authored-by lines to commit messages without the user's perrmission
- Do not insert unnecessary spaces between Japanese text and English words or identifiers. Use natural Japanese spacing, for example: `Claude Codeの設定`, `GitHub Actionsのジョブ`, `APIレスポンス`, `ユーザーID`. Exception: always put spaces before and after links and file paths so they do not get merged into surrounding text and break.
- Finalize process: Remove ALL meta-comments about your changes, such as "// Added..." or "// Removed...", "// XXX has been moved to..." from the generated code before applying the changes
- When adding a package or changing a package version in manifests like `package.json`, `pyproject.toml`, or `Cargo.toml`, prefer running the package manager's command (e.g. `npm install`, `uv add`, `cargo add`) over editing the file directly. When initializing a project, use the `init` command or a `create-xxx-app` scaffolder instead of hand-creating files.

@~/.codex/RTK.md
