## Repository purpose

These are personal dotfiles managed by **chezmoi** (source of truth for files in `$HOME`) and **Nix Home Manager** (declarative package set). The repo targets macOS, Linux (including WSL), and Windows from a single source tree.

## How files map to `$HOME`

chezmoi rewrites filenames on apply. Key prefixes used in this repo:

- `dot_foo` → `~/.foo` (e.g. `dot_zshrc` → `~/.zshrc`, `dot_claude/` → `~/.claude/`)
- `private_foo` → `~/foo` with mode `0600`
- `readonly_foo` → read-only on apply
- `executable_foo` → `+x`
- `*.tmpl` → rendered through chezmoi's Go template engine (`.chezmoi.os`, `.chezmoi.arch`, `.chezmoi.username`, etc.); the `.tmpl` suffix is stripped
- `.chezmoiscripts/run_onchange_*` → re-run when their content hash changes (hashes of dependencies are embedded as comments at the top, e.g. `run_onchange_after_00_home-manager.sh.tmpl`, so editing a referenced file re-triggers the script)
- `.chezmoitemplates/` → shared template snippets included via `{{ include "..." }}`

Per-OS file selection is controlled by `.chezmoiignore.tmpl` (gates `Library/**`, `AppData/**`, `winget.json`, etc. on `.chezmoi.os`).

Files **not** managed by chezmoi (no `dot_`/`private_`/etc. prefix, listed in `.chezmoiignore.tmpl`, or sitting at the repo root as plain docs) live only inside this repository and are never copied to `$HOME`. Notable examples:

- `./AGENTS.md` and `./CLAUDE.md` (this file and its stub) — repo-level agent guidance, read directly from the repo by tools like Codex CLI / Claude Code. Edits take effect immediately; **do not** run `chezmoi apply` for them (it will say "not managed").
- `./README.md`, `./LICENSE`, `.chezmoiignore.tmpl`, `.chezmoidata.toml`, `.chezmoiscripts/`, `.chezmoitemplates/` — chezmoi metadata / repo docs, not targets.

To check whether a given file is a chezmoi target, run `chezmoi target-path <source>` (prints the destination) or `chezmoi managed | grep <name>`.

## Applying changes after editing files (MANDATORY for agents)

Editing a managed file in this repo does **not** change anything in `$HOME` — chezmoi only syncs on `apply`. If you (the agent) edit a managed file here, you **must run `chezmoi apply -v <target>` yourself in the same turn**. Do not tell the user to run it; do not end the turn with "now run apply". The edit-then-apply pair is one atomic action. (Unmanaged files like `./AGENTS.md` / `./CLAUDE.md` skip this step — they are read straight from the repo.)

Rules:

- Always pass a target path. **Never** run a bare `chezmoi apply` — it may overwrite unrelated files.
- The target is the **destination path in `$HOME`**, not the source path in the repo. Translate the chezmoi filename prefixes to get it:
  - `dot_zshrc` → `chezmoi apply -v ~/.zshrc`
  - `dot_claude/settings.json` → `chezmoi apply -v ~/.claude/settings.json`
  - `private_dot_config/zellij/config.kdl` → `chezmoi apply -v ~/.config/zellij/config.kdl`
  - `dot_local/bin/executable_zjdev` → `chezmoi apply -v ~/.local/bin/zjdev`
  - `foo.tmpl` → target is `foo` (drop the `.tmpl` suffix)
- If unsure of the target path, run `chezmoi target-path <source-path>` to resolve it before applying.
- If multiple files were edited, run `chezmoi apply -v` once per target path (not a single bare apply).
- After applying, mention any runtime step the user still needs (e.g. restart zellij, reload shell) — but only the parts that genuinely require the user, not the apply itself.

## Common commands

Apply / diff / status (from anywhere):

```sh
chezmoi diff           # preview changes
chezmoi apply -v       # apply to $HOME (runs run_onchange_* scripts)
chezmoi status
chezmoi cd             # cd into this repo
chezmoi execute-template < file.tmpl   # render a template ad-hoc
```

Home Manager (invoked automatically by `.chezmoiscripts/run_onchange_after_00_home-manager.sh.tmpl` on non-Windows):

```sh
nix run home-manager/master -- switch --flake "$HOME/.config/home-manager#default"
```

The Home Manager flake lives at `private_dot_config/home-manager/` (rendered to `~/.config/home-manager/`). Edit `common.nix.tmpl` to change cross-platform packages; `linux-*.nix`, `darwin.nix`, `wsl.nix` for OS-specific bits. `local.nix` (gitignored, not in repo) is auto-included if present and can set `localDeny.packages = [ ... ]` to remove packages from the common set.

macOS-specific re-apply helpers (see README for full list):

```sh
chezmoi execute-template -f .chezmoiscripts/run_onchange_import_rectangle.sh.tmpl | sh
chezmoi execute-template -f .chezmoiscripts/run_onchange_configure_alttab.sh.tmpl | sh
```

Windows package list lives in `winget.json`: `winget export -o winget.json` / `winget import winget.json`.

## Configuration layering (important)

1. `.chezmoidata.toml` — repo-wide defaults (git identity, agent allow/deny lists, etc.)
2. `~/.config/chezmoi/chezmoi.toml` — per-machine overrides (created by `.chezmoi.toml.tmpl` on `chezmoi init`); `[data]` here wins
3. `private_dot_config/git/config.machine.tmpl` → `~/.config/git/config.machine` — included by the shared `dot_gitconfig.tmpl` for per-host git settings (signing key paths, work email, `safe.directory`, etc.)

When adding new tunable values, prefer threading them through `.chezmoidata.toml` + chezmoi template prompts rather than hardcoding.

## Agent permission lists

`.chezmoidata.toml` defines `agent_plain_allow`, `agent_shell_allow`, and `agent_shell_deny` arrays consumed by AI-agent settings templates (e.g. `dot_claude/settings.json.tmpl`, `dot_codex/...`). Add new always-allowed read-only commands to `agent_shell_allow`; destructive patterns belong in `agent_shell_deny`.

## User-level agent instructions

Per-agent global instruction files live under each agent's config directory and are distinct from this repo-level `AGENTS.md`:

- `dot_claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (Claude Code, applies to *all* projects)
- `dot_codex/private_AGENTS.md` → `~/.codex/AGENTS.md` (Codex CLI, applies to *all* projects)

Edit those files to change user-global agent behavior; edit this file (`AGENTS.md` / `CLAUDE.md` stub) for repo-specific guidance.
