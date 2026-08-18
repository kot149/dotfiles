## Repository purpose

These are personal dotfiles managed by **chezmoi** (source of truth for files in `$HOME`) and **Nix Home Manager** (declarative package set). On macOS, **nix-darwin** is also used for system-level settings (source: `private_dot_config/nix-darwin/`, applied by `.chezmoiscripts/run_onchange_after_nix-darwin.sh.tmpl`). The repo targets macOS, Linux (including WSL), and Windows from a single source tree.

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

Nix files need an extra switch step: a targeted `chezmoi apply -v <target>` does **not** run the `run_onchange_*` scripts, so after editing Home Manager files (`private_dot_config/home-manager/`, e.g. `common.nix.tmpl`) or nix-darwin files (`private_dot_config/nix-darwin/`), apply the target and then run the corresponding switch yourself in the same turn:

```sh
# Home Manager (after applying ~/.config/home-manager/<file>)
nix run home-manager/master -- switch --flake "$HOME/.config/home-manager#default"

# nix-darwin (after applying ~/.config/nix-darwin/<file>; needs sudo, may prompt the user)
cd ~/.config/nix-darwin && sudo -H nix run github:LnL7/nix-darwin#darwin-rebuild -- switch --flake .#"$(hostname -s)"
```

herdr config needs a reload: after applying `~/.config/herdr/config.toml`, run the reload yourself in the same turn so the running session picks it up (no restart needed):

```sh
herdr server reload-config
```

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

nix-darwin (macOS system-level settings; invoked automatically by `.chezmoiscripts/run_onchange_after_nix-darwin.sh.tmpl`):

```sh
cd ~/.config/nix-darwin && sudo -H nix run github:LnL7/nix-darwin#darwin-rebuild -- switch --flake .#"$(hostname -s)"
```

The nix-darwin flake lives at `private_dot_config/nix-darwin/` (rendered to `~/.config/nix-darwin/`). Edit `darwin-configuration.nix.tmpl` for macOS system settings (`system.defaults.*`, `system.startup.*`, etc.). Note the split: **Home Manager** owns packages and user-level dotfile programs, **nix-darwin** owns macOS system settings — do not assume the repo is "Home Manager only".

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

`.chezmoidata.toml` defines `agent_plain_allow`, `agent_shell_allow`, `agent_shell_allow_no_rtk`, and `agent_shell_deny` arrays consumed by AI-agent settings templates (e.g. `dot_claude/settings.json.tmpl`, `dot_codex/...`). Add new always-allowed read-only commands to `agent_shell_allow`; destructive patterns belong in `agent_shell_deny`. Entries in `agent_shell_allow` are emitted both bare and with an auto-generated `rtk <cmd>` variant — put commands that should be allowed **without** the `rtk` wrapper (e.g. `rtk` itself) in `agent_shell_allow_no_rtk`, which emits only the bare form.

## Agent hooks

Hook scripts shared by more than one agent live in `.chezmoitemplates/agents/` and are pulled into each agent's config directory by a one-line `{{ include ... }}` wrapper, so there is a single implementation per script:

- `check-package-manager.sh` (bash + python3) → `~/.claude/hooks/` and `~/.codex/hooks/`
- `check-package-manager.ps1` (pwsh port, Windows only) → `~/.codex/hooks/`

Registration differs per agent:

- Claude Code: `hooks.PreToolUse` in `dot_claude/settings.json.tmpl`, always the bash script.
- Codex CLI: `dot_codex/hooks.json.tmpl` → `~/.codex/hooks.json`. A handler takes `command` (used on macOS/Linux) and `commandWindows` (used on Windows), so the bash and pwsh variants are registered side by side.

Two Codex-specific details:

- **Blocking** requires JSON on stdout with `hookSpecificOutput.permissionDecision = "deny"` plus a non-empty `permissionDecisionReason`, and exit status 0. A non-zero exit only marks the hook as failed; it does not stop the tool call. Claude Code accepts the same JSON, which is why the shared scripts use it instead of `exit 2`.
- **Trust**: Codex will not run a user-level hook until it is trusted. The TUI prompts "Hooks need review" on the next launch and records the decision in `~/.codex/config.toml` as `[hooks.state."<hooks.json path>:<event>:<group>:<index>"]` with `trusted_hash`. The hash covers the handler definition, so **any edit to `hooks.json` requires re-trusting** (a `codex exec` run silently skips untrusted hooks). This state is per-machine and is not managed by chezmoi.

## Agent skills

Skills live in two stores. `~/.agents/skills` is the shared store: Codex CLI reads it natively (alongside its own deprecated `~/.codex/skills`), as do opencode, Cursor, Gemini CLI and Amp. `~/.claude/skills` exists because Claude Code is the one agent with no `.agents/` awareness and no setting for extra skill roots, so anything Claude Code should see has to be materialized there as well. Nothing in this repo writes to `~/.codex/skills` any more.

Both stores are generated, never hand-synced and never symlinked together: a skill is declared or written **once** and the same definition materializes into every store that needs it. For self-authored skills the single source is the body under `.chezmoitemplates/agents/skills/`; for third-party skills it is the `[[agent_skills]]` entry, whose `agents` list names the target stores.

Skills come from three places, and which one a skill belongs to decides where you edit it:

1. **Self-authored, single agent** — checked in under `dot_claude/skills/<name>/SKILL.md` (Claude Code) or `dot_agents/skills/<name>/SKILL.md` (shared store). Skills in the shared store additionally carry `agents/openai.yaml`, which supplies Codex's TUI interface metadata and is ignored by agents that do not know it. Scripts shipped with a skill need the `executable_` prefix. Every self-authored skill is currently shared (case 2), so this layout is only for a skill that genuinely cannot be made agent-neutral.
2. **Self-authored, shared between agents** — body lives in `.chezmoitemplates/agents/skills/<name>.md` and each agent gets a one-line `{{ include ... }}` wrapper named `SKILL.md.tmpl`, same pattern as the shared hooks. Scripts shipped with a shared skill follow the same pattern: body in `.chezmoitemplates/agents/<script>`, and each agent gets an `executable_<script>.tmpl` wrapper (e.g. `keychain-cred.sh`). This is the default for every self-authored skill in the repo.

   A shared body must not hardcode one agent's tool names or call syntax. The repo settles this by naming the capability and mapping it onto each agent once, near the top of the body:

   - **User choice** — the body says "選択提示" / "ask the user to choose" and defines it once: use a selection UI tool (`AskUserQuestion` and similar) where the agent has one, otherwise present the same options as a numbered plain-text list. Never call the tool by name inline.
   - **Subagents** — the body says "サブエージェント" and defines the mapping once: Claude Code's `Agent` tool (`subagent_type: "Explore"` for read-only roles, several calls in one message for parallelism) vs Codex CLI's `spawn_agent`/`wait` (gated by `features.multi_agent`, roles from `[agents]` in `config.toml`), plus the invariants that must hold either way (fresh context, read-only, fall back to sequential when there is no parallel mechanism). `deep-review`, `meta-review`, and `pr-review-brief` are shared this way.
   - **MCP tools** — refer to the server and the kind of operation ("Atlassian MCP のissue取得ツール"), not the tool id, since names differ per agent and some agents load tool schemas lazily.
   - **File and search tools** — say "read the file" / "search the repository", not `Read`/`Grep`/`Glob`/`Edit`.
   - **Paths into the skill's own directory** — write them relative to the skill root of whichever store the copy lives in (`~/.claude/skills` vs `~/.agents/skills`), never hardcode one.
3. **Third-party** — declared in `.chezmoidata.toml` as `[[agent_skills]]` and materialized by `.chezmoiexternal.toml.tmpl` as `type = "archive"` externals pulled from a pinned GitHub tarball. This is the cross-platform path: it works on Windows as-is (no symlinks, no Nix), unlike Home Manager, which is non-Windows only.

Adding a third-party skill:

```toml
[[agent_skills]]
repo = "owner/name"
rev = "<commit SHA>"      # gh api repos/owner/name/commits/HEAD --jq .sha
prefix = "skills"         # directory inside the repo holding the skills
names = ["skill-name"]    # one entry per skill dir under prefix
agents = ["claude", "agents"]   # one entry per target store; "claude" ->
                                # ~/.claude/skills, "agents" -> ~/.agents/skills
```

For a repo that keeps `SKILL.md` directly under `prefix` (or at the repo root, with `prefix = ""`) instead of in a per-skill subdirectory, add `flat = true`; `names` then holds the single target directory name.

Then `chezmoi apply -v ~/.claude/skills` (and/or `~/.agents/skills`). The template derives `include` and `stripComponents` from `prefix`, so each skill lands with `SKILL.md` at the root of its target directory. Updating a skill means bumping `rev`; `refreshPeriod = "168h"` only controls re-download of the pinned tarball, never which commit is used.

Two things not managed here:

- **Claude Code plugins** supply their own skills. The enabled `cloudflare@cloudflare` marketplace covers the whole `cloudflare/skills` set for Claude, so those are the one exception to listing both stores: they are declared for `agents = ["agents"]` only, which keeps them from showing up twice for Claude Code (once as `cloudflare:<name>` from the plugin, once as `<name>` from the store). Codex has its own plugin system (`codex plugin add/list`, `codex plugin marketplace`) but it does not consume Claude Code marketplaces, so Codex gets those skills through `[[agent_skills]]` instead.
- The **`skills` CLI** (`npx skills add`, vercel-labs) installs into `~/.agents/skills` too, tracked in a per-machine `~/.agents/.skill-lock.json`, and symlinks the non-`.agents` agent directories (Claude Code) at it. Use it to *discover* skills, then transcribe the pick into `[[agent_skills]]`. Do not leave a skill installed that way: the copy is per-machine, invisible to `chezmoi status`, pinned by a separate lock file, and it writes to the same directory names this repo manages.

## User-level agent instructions

Per-agent global instruction files live under each agent's config directory and are distinct from this repo-level `AGENTS.md`:

- `dot_claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (Claude Code, applies to *all* projects)
- `dot_codex/private_AGENTS.md` → `~/.codex/AGENTS.md` (Codex CLI, applies to *all* projects)

Edit those files to change user-global agent behavior; edit this file (`AGENTS.md` / `CLAUDE.md` stub) for repo-specific guidance.
