## Repository purpose

Personal dotfiles with [mise](https://mise.jdx.dev) as the source of truth for files in `$HOME` (via `mise bootstrap`) and [Nix Home Manager](https://github.com/nix-community/home-manager) for the declarative package set. On macOS, **nix-darwin** is also used for system-level settings (source: `templates/nix-darwin/`, applied by `mise run apply-nix-darwin`). The repo targets macOS, Linux (including WSL), and Windows from a single source tree.

## Layout

| Path | Role |
| --- | --- |
| `.miserc.toml` | Early-init setting (`auto_env = true`): auto-loads `mise.unix.toml` + `mise.{macos,linux,windows}.toml` for the current platform |
| `mise.toml` | Common `[vars]`, cross-platform `[dotfiles]`, all `[tasks]` |
| `mise.unix.toml` | macOS+Linux `[dotfiles]` (loaded with `mise.macos.toml` / `mise.linux.toml`) |
| `mise.macos.toml` / `mise.linux.toml` / `mise.windows.toml` | OS-specific `[dotfiles]`; Windows also holds `[bootstrap.repos]` |
| `mise.local.toml` (gitignored) | Per-machine `[vars]` overrides; generate with `mise run setup` |
| `mise.local.toml.example` | Template for the above |
| `dotfiles/` | Static file sources, mirrored 1:1 to `$HOME` (e.g. `dotfiles/.zshrc` → `~/.zshrc`) |
| `templates/` | `*.tera` templates (`mode = "template"`) plus static merge specs (`codex/`, `vscode/`, `macos/`, `pnpm/`, `tuicr/`) |
| `templates/agents/` | Single-source hook scripts (`hooks/`) and skill bodies (`skills/`, `keychain-cred.sh`), mapped to every agent store |
| `generated/` | Checked-in outputs of `scripts/generate-agent-files.py`; never hand-edit |
| `scripts/` | Task implementations (`apply-*.sh`/`.ps1`, `merge-*.py`, `setup.*`, `sync-agent-skills.ts`) |
| `config/` | Structured inputs: `agent-permissions.toml`, `agent-skills.toml`, `nix-binary-caches.toml` |

OS layers load automatically via `auto_env` (`.miserc.toml`, an early-init setting that must live outside `mise.toml`). Explicit `MISE_ENV` / `-E` still works and takes precedence over the platform layers.

Files at the repo root that are not referenced by any `[dotfiles]` (`AGENTS.md`, `CLAUDE.md`, `README.md`, `mise.*.toml`, `scripts/`, `templates/`, `config/`, `tests/`) live only in this repository. Edits to them take effect immediately with no apply step.

## Applying changes after editing files (MANDATORY for agents)

Editing a source file here does **not** change anything in `$HOME`. If you (the agent) edit a managed file, apply it yourself in the same turn. Do not tell the user to run it; do not end the turn with "now run apply". The edit-then-apply pair is one atomic action.

Rules:

- Prefer a targeted apply. `mise bootstrap dotfiles apply` accepts target paths: `mise bootstrap dotfiles apply ~/.zshrc`.
- Symlink entries apply instantly; `template` entries re-render on apply.
- After editing task inputs (`templates/vscode/*`, `templates/codex/*`, `generated/antigravity-settings.json`, nix files, plist specs, `karabiner.edn`, herdr plugins), run the matching task yourself in the same turn: `mise run apply-vscode-settings`, `mise run apply-codex-config`, `mise run apply-home-manager` + Home Manager switch is inside the task, `mise run apply-nix-darwin` (needs sudo, may prompt), `mise run import-rectangle`, `mise run configure-alttab`, `mise run apply-herdr-plugins` (+ `herdr server reload-config` is inside the task).
- After editing `config/agent-permissions.toml`, `config/nix-binary-caches.toml`, or `templates/*/*.skel`, run `mise run generate-agent-files` and then apply the affected targets.
- Full converge: `mise bootstrap` (repos + dotfiles, then the `bootstrap` task which depends on every apply task). Tasks declare `sources`, so unchanged inputs are skipped.
- Never run `mise bootstrap dotfiles unapply`, `mise bootstrap *--force*`, or `chezmoi apply --force` (all are denied patterns for a reason).

## Common commands

```sh
mise bootstrap dotfiles status    # what would change (add --missing for CI gate)
mise bootstrap dotfiles apply [TARGET]...
mise bootstrap plan               # dry-run of declarative bootstrap parts
mise run <tab>                    # list tasks (or: mise tasks ls)
mise run -n <task>                # print without running
mise run setup                    # (re)generate mise.local.toml interactively
bun scripts/sync-agent-skills.ts --list   # preview third-party skill sync
mise run check-generated          # fail if generated/ is stale
mise run check-agent-skills       # fail if a pinned skill is missing from its store
mise run refresh-externals        # update git repos + re-download skills (no auto timer; run periodically)
bun run tests/textlint-rule-ja-ai-phrasing.js
```

Home Manager (also runs automatically via `mise run apply-home-manager` on non-Windows):

```sh
nix run home-manager/master -- switch --flake "$HOME/.config/home-manager#default"
```

nix-darwin (macOS system settings; also runs via `mise run apply-nix-darwin` with sudo):

```sh
cd ~/.config/nix-darwin && sudo -H nix run github:LnL7/nix-darwin#darwin-rebuild -- switch --flake .#"$(hostname -s)"
```

Windows package list lives in `dotfiles/winget.json` (applied to `~/winget.json`): `winget export -o ~/winget.json` / `winget import ~/winget.json`.

## Configuration layering (important)

1. `mise.toml [vars]` — repo-wide defaults (git identity, `linux_gui`, `git_safe_directories` as comma-separated string).
2. `mise.local.toml [vars]` — per-machine overrides (created by `mise run setup`); wins over `mise.toml`.
3. `~/.config/git/config.machine` (rendered from `templates/git/config.machine.tera`) — included by `~/.gitconfig` for per-host git settings.

`[vars]` values are strings only. Lists live in `config/*.toml` and are consumed by `scripts/generate-agent-files.py` (permissions, nix caches) or `scripts/sync-agent-skills.ts` (skill pins), never inlined into templates. When adding new tunable values, prefer `mise.toml [vars]` + `mise.local.toml`, not hardcoding.

Machine-resolved values (`whoami`, `hostname -s`, `uname -r` for WSL detection, `arch()` for nix systems) are computed inside templates via `exec()`/`env`/`os()`/`arch()` at render time, so they need no per-machine config.

## generated/ (do not hand-edit)

`generated/claude-settings.json`, `generated/codex-rules`, `generated/opencode.json`, `generated/antigravity-settings.json`, and `generated/nix-substituters-{urls,keys}.nix` are produced by `scripts/generate-agent-files.py` (stdlib only) from `config/agent-permissions.toml`, `config/nix-binary-caches.toml`, and the `templates/*/*.skel` skeletons. The expansion logic (JS script/bin cross products, `rtk`/`rtk proxy`/`corepack`/absolute-path variants, Codex `prefix_rule` patterns) lives exactly once in that script. Regenerate after any input change and commit the result; `mise run check-generated` verifies sync.

## Agent permission lists

`config/agent-permissions.toml` defines `agent_plain_allow`, `agent_shell_allow`, `agent_shell_allow_js_scripts`, `agent_shell_allow_js_bins`, `agent_shell_allow_no_rtk`, and `agent_shell_deny`, consumed by the generator (see above). Add new always-allowed read-only commands to `agent_shell_allow`; destructive patterns belong in `agent_shell_deny`. Read-only introspection commands for this repo live there too (`mise tasks ls*`, `mise bootstrap dotfiles status*`, `mise bootstrap plan*`, `mise run --dry-run *`), alongside the equivalent `chezmoi` entries, which are kept until the migration settles.

## Agent hooks

Single-source hook scripts live in `templates/agents/hooks/` and are mapped to each agent's hooks directory directly from `mise.toml`/`mise.*.toml` (one source, multiple targets — no wrapper files):

- `check-force-push.sh`, `check-github-api-write.sh`, `check-package-manager.sh` (+ `.ps1` Windows port), `check-commit-sha-links.sh`, `check-cargo-install.sh` (bash + python3) → `~/.claude/hooks/` and `~/.codex/hooks/`
- `check-writing-style.js` (Bun + textlint, imports `./textlint-rules/` next to it) → both hooks dirs

Registration differs per agent: Claude Code uses `hooks.PreToolUse` with the static `generated/claude-settings.json`; Codex CLI uses `templates/codex/hooks.json.tera` → `~/.codex/hooks.json` with `command` (macOS/Linux) + `commandWindows` (Windows) side by side. Codex file edits arrive as `apply_patch`, which `check-writing-style.js` parses; `textlint-rules/` is materialized next to each copy.

`tests/` holds tests for the hooks that carry enough logic to regress (plain Bun scripts, not `bun test` files, because `bun test` cannot resolve the versioned import specifiers the hooks pin).

Two Codex-specific details:

- **Blocking** requires JSON on stdout with `hookSpecificOutput.permissionDecision = "deny"` plus a non-empty `permissionDecisionReason`, and exit status 0. A non-zero exit only marks the hook as failed.
- **Trust**: Codex will not run a user-level hook until it is trusted (`~/.codex/config.toml` `[hooks.state.*]`). Any edit to `hooks.json` requires re-trusting. This state is per-machine and is not managed here.

## Agent skills

Skills live in two stores. `~/.agents/skills` is the shared store (Codex CLI, opencode, Cursor, Gemini CLI, Amp). `~/.claude/skills` exists for Claude Code, which has no `.agents/` awareness. Nothing here writes to `~/.codex/skills`.

Both stores are generated from single sources, never hand-synced: self-authored bodies live once under `templates/agents/skills/` and each store gets a `[dotfiles]` mapping to the same source; skill scripts map the same way (`templates/agents/keychain-cred.sh` → both `keychain-credentials/scripts/` dirs); Codex TUI metadata (`agents/openai.yaml`) sits next to the `.agents` copy only.

The base-branch / merge-base procedure that used to be a shared include is inlined into `autosquash.md`, `fixup.md`, and `reorganize-commits.md` (mise templates have no cross-file render include, so a nested include cannot survive as such). If you change that procedure, edit all three bodies identically.

Skills come from three places:

1. **Self-authored, single agent** — under `dotfiles/.agents/skills/<name>/` only. Currently unused; prefer shared (case 2).
2. **Self-authored, shared** — body in `templates/agents/skills/<name>.md`, mapped to both stores. The default for everything self-authored. Capability mapping (ask-the-user UI, subagents per agent, MCP/file/search tools, skill-relative paths) is documented once at the top of each body; do not hardcode one agent's tool names inline.
3. **Third-party** — declared in `config/agent-skills.toml` as `[[agent_skills]]` and synced by `mise run sync-agent-skills` (`scripts/sync-agent-skills.ts`, Bun + system `tar`), which downloads the pinned GitHub tarball, extracts `prefix/name` (or `prefix` when `flat = true`), and places it in every listed store.

Adding a third-party skill:

```toml
[[agent_skills]]
repo = "owner/name"
rev = "<commit SHA>"      # gh api repos/owner/name/commits/HEAD --jq .sha
prefix = "skills"         # directory inside the repo holding the skills
names = ["skill-name"]    # one entry per skill dir under prefix
agents = ["claude", "agents"]
```

For a repo that keeps `SKILL.md` directly under `prefix` (or at the repo root, with `prefix = ""`), add `flat = true`; `names` then holds the single target directory name. Then `mise run sync-agent-skills`. Updating a skill means bumping `rev`.

Two things not managed here:

- **Claude Code plugins** supply their own skills. The enabled `cloudflare@cloudflare` marketplace covers the whole `cloudflare/skills` set for Claude, so those are declared for `agents = ["agents"]` only (Codex has no Claude Code plugin mechanism and gets them via sync).
- The **`skills` CLI** (`npx skills add`) installs into `~/.agents/skills` too. Use it to *discover* skills, then transcribe the pick into `config/agent-skills.toml`. Do not leave a skill installed that way: it is per-machine, invisible to `mise bootstrap dotfiles status`, and collides with synced directories.

## User-level agent instructions

Per-agent global instruction files live under each agent's config directory and are distinct from this repo-level `AGENTS.md`:

- `dotfiles/.claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (Claude Code, applies to *all* projects)
- `dotfiles/.codex/AGENTS.md` → `~/.codex/AGENTS.md` (Codex CLI, applies to *all* projects)

Edit those files to change user-global agent behavior; edit this file (`AGENTS.md` / `CLAUDE.md` stub) for repo-specific guidance.
