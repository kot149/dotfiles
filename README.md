These dotfiles are managed by [chezmoi](https://www.chezmoi.io) and [Nix Home Manager](https://github.com/nix-community/home-manager).

## Prerequisites

### Windows

- Git for Windows. Its Git Bash (default `C:/Program Files/Git/bin/bash.exe`, overridable per machine via `git_bash_path` in `~/.config/chezmoi/chezmoi.toml`) runs the Claude Code and Codex shell hooks.
  ```pwsh
  winget install Git.Git
  ```
- chezmoi
  ```pwsh
  winget install twpayne.chezmoi
  ```
- just, for `dots`
  ```pwsh
  winget install Casey.Just
  ```
- uv, used by the Python hooks, the Python parsers inside the bash hooks and the `just` recipes. None of them download Python, so run `uv python install` once.
  ```pwsh
  winget install astral-sh.uv
  ```
- jq, for the bash hooks
  ```pwsh
  winget install jqlang.jq
  ```
- bun, for the writing-style hook and `just test`
  ```pwsh
  winget install Oven-sh.Bun
  ```
- rtk, for the agent command rewrite hooks
  ```pwsh
  winget install rtk-ai.rtk
  ```

`winget import winget.json` (run from the repo, see [Managing Winget packages](#managing-winget-packages)) installs all of them.

### Linux / Mac

- Linux: curl, xz-utils
  ```sh
  apt update && apt install curl xz-utils -y
  ```
- Nix via [nix-installer](https://github.com/NixOS/nix-installer):
  ```sh
  curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
  ```
  ```sh
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  ```
- Or, Nix via Determinate Nix installer:
  ```sh
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install
  ```

Everything else (`just`, `uv`, `bun`, `rtk`, `nh`, ...) is installed by Home Manager on the first apply.

#### Linux with no root

Use nix-portable

```sh
cd ~/.local/bin
curl -L https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m) > ./nix-portable
chmod +x ./nix-portable
ln -s nix-portable nix
ln -s nix-portable nix-build
ln -s nix-portable nix-channel
ln -s nix-portable nix-collect-garbage
ln -s nix-portable nix-copy-closure
ln -s nix-portable nix-daemon
ln -s nix-portable nix-env
ln -s nix-portable nix-hash
ln -s nix-portable nix-instantiate
ln -s nix-portable nix-prefetch-url
ln -s nix-portable nix-shell
ln -s nix-portable nix-store
```

and add this to the `~/.bashrc`
```sh
if [ -z "$NP_RUNTIME" ] && [ -t 0 ]; then
    export NP_RUNTIME=bwrap
    export PATH="$HOME/.nix-profile/bin:$PATH"
    exec nix-portable nix shell nixpkgs#zsh nixpkgs#bashInteractive -c zsh
fi
```

## Applying dotfiles

```sh
chezmoi init --apply kot149
```

or with nix:

```sh
nix --extra-experimental-features "flakes nix-command" run nixpkgs#chezmoi -- init --apply kot149
```

Besides rendering the managed files into `$HOME`, the first apply:

- downloads the pinned third-party agent skills into `~/.claude/skills` and `~/.agents/skills` (every OS);
- macOS / Linux: on Determinate Nix, writes `/etc/nix/nix.custom.conf` (`sudo`), then runs the Home Manager switch through `nh home switch` (falls back to `nix run home-manager/master` when `nh` is not installed yet, as on the very first apply). The first switch builds the whole package set and takes minutes;
- macOS: also runs the nix-darwin switch (`nh darwin switch`, or `nix run github:nix-darwin/nix-darwin#darwin-rebuild` before `nh` exists; prompts for the `sudo` password) and the Karabiner / Rectangle / DockDoor / AltTab scripts, and installs the tailscaled LaunchDaemon (`sudo`) when tailscaled is installed;
- Linux: on Nix installs without `nix.custom.conf`, edits `/etc/nix/nix.conf` (`sudo`);
- Windows: no Nix step; clones the PowerShell / AutoHotkey libraries.

To preview first, clone without applying and check the diff (`chezmoi apply --dry-run -v` prints the same without changing anything):

```sh
chezmoi init kot149
chezmoi diff
```

Then run `chezmoi apply -v`.

## Maintenance (`dots`)

The `dots` alias ([`dot_zshrc`](dot_zshrc), and a function in the [PowerShell profile](readonly_Documents/PowerShell/Microsoft.PowerShell_profile.ps1)) runs the repo [`justfile`](justfile) from anywhere. `dots` alone lists the tasks, `dots update` pulls the repo, applies it and updates everything for the current OS, and `dots test` runs the repo checks.

| Task | What it does |
|---|---|
| `update` | Pull the dotfiles repo, apply it, then update everything this machine uses (the task list differs per OS) |
| `apply *args` | Apply the source state to `$HOME` (extra args go to `chezmoi apply`) |
| `pull` | Pull the dotfiles repo and apply it |
| `diff *args` | Show what apply would change |
| `status` | List targets that differ from the source state |
| `skills-check` | Report third-party agent skills whose pinned rev is behind upstream |
| `skills-update *args` | Review, bump and commit third-party agent skill revs, then install them |
| `skills-lint` | Check the agent-skill tree: wrappers, store parity, frontmatter, `agent_skills` |
| `skills-drift` | Report skill directories in `~/.claude/skills` and `~/.agents/skills` that this repo does not manage |
| `hm-switch` (macOS / Linux) | Rebuild the Home Manager generation without updating flake inputs |
| `hm-update` (macOS / Linux) | Update the Home Manager flake inputs and rebuild |
| `darwin-update` (macOS) | Update the nix-darwin flake inputs and rebuild |
| `nix-clean` (macOS / Linux) | Delete Nix generations older than 30 days, keeping the latest one |
| `sheldon-update` (macOS / Linux) | Update zsh plugins |
| `mise-upgrade` (macOS / Linux) | Upgrade the tools in the global mise config |
| `pkgs-list *managers` | List globally installed bun / npm / pnpm / uv / cargo / go packages |
| `pkgs-update *managers` | Update globally installed bun / npm / pnpm / uv / cargo / go packages |
| `pkgs-dupes` | Find commands installed by both bun / npm / pnpm / uv / cargo / go and Nix / winget / others |
| `gh-ext-upgrade` | Upgrade gh CLI extensions |
| `winget-upgrade` (Windows) | Upgrade winget packages (run by hand; not part of `update`) |
| `render-check` | Render the agent config templates and check that the output parses |
| `lint` | Run shellcheck, ruff, nixfmt and oxlint over the repo |
| `doctor *args` | Report stale ignore entries, missing Nix hash globs, missing tools, Codex hooks with no trust entry or possibly stale trust, and unmanaged skill directories (run last by `update`; `--no-home` skips the `$HOME` checks) |
| `ci-render *args` | Apply the source tree into a scratch directory without scripts and externals, then parse the agent configs (extra args go to `chezmoi`) |
| `hooks-lint` | Check `.chezmoidata/agent-hooks.toml` against the hook files in `dot_claude/hooks` and `dot_codex/hooks` |
| `test` | Run `skills-lint`, `hooks-lint`, `render-check`, `lint` and the tests under [`tests/`](tests) |

Every push to `main` and every pull request runs [`.github/workflows/check.yml`](.github/workflows/check.yml), which runs `ci-render`, `test` and `doctor --no-home` on Ubuntu, macOS and Windows.

## AI agent configuration

The hooks, permission lists and skills for Claude Code, Codex CLI, opencode and Antigravity live in this repo ([`dot_claude/`](dot_claude), [`dot_codex/`](dot_codex), [`dot_agents/`](dot_agents), [`private_dot_config/opencode/`](private_dot_config/opencode), [`dot_gemini/`](dot_gemini)) and are generated from single sources under [`.chezmoitemplates/`](.chezmoitemplates) and [`.chezmoidata/`](.chezmoidata). [`AGENTS.md`](AGENTS.md) documents the layout and the rules.

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).

## Git (shared + per-machine)

Global Git is split so portable settings live in the repo and machine-specific values (account, signing paths, `core.editor`, extra sections you add to the template) stay overridable per host:

- Shared: [`dot_gitconfig.tmpl`](dot_gitconfig.tmpl) (includes `~/.config/git/config.machine`, hunk, LFS, optional `safe.directory` from `git_safe_directories` in data).
- Bootstrap: [`private_dot_config/git/create_config.machine.tmpl`](private_dot_config/git/create_config.machine.tmpl) creates `~/.config/git/config.machine` only when the target is absent. Existing local files are preserved. The template defaults target the **kot149** GitHub profile; override the initial values in `~/.config/chezmoi/chezmoi.toml` on work PCs, etc.

Defaults live in [`.chezmoidata/git.toml`](.chezmoidata/git.toml) (**kot149** + GitHub noreply email). If `git_signing_key` / `git_allowed_signers` are left empty, [`create_config.machine.tmpl`](private_dot_config/git/create_config.machine.tmpl) falls back to `$HOME/.ssh/id_ed25519_github_kot149.pub` and `$HOME/.ssh/allowed_signers`. **`~/.config/chezmoi/chezmoi.toml`** `[data]` overrides `.chezmoidata/git.toml`, so a work machine can point at different keys without editing the repo.

Example override for a work machine:

```toml
[data]
git_user_name = "Your Work Name"
git_user_email = "you@company.example"
git_signing_key = "C:/Users/you/.ssh/id_ed25519_work.pub"
git_allowed_signers = "C:/Users/you/.ssh/allowed_signers_work"
git_editor = "code --wait"
git_commit_gpgsign = true
git_safe_directories = [
  '%(prefix)///wsl.localhost/Ubuntu-24.04/home/you/.local/share/chezmoi',
]
```

On a new machine, `chezmoi init` runs [`.chezmoi.toml.tmpl`](.chezmoi.toml.tmpl) and prompts with **kot149-oriented defaults**; answers are written to `~/.config/chezmoi/chezmoi.toml`. To change machine-only Git settings after initial creation, edit local `~/.config/git/config.machine`; changes to the source template affect only the bootstrap content.

## Managing Winget packages

Export:
```sh
chezmoi cd
```
```sh
winget export -o winget.json
```

Import:
```sh
winget import winget.json
```

## Managing `.plist` files
- To re-add Rectangle.plist, use the following command:
  ```sh
  defaults export com.knollsoft.Rectangle - > ~/.local/share/chezmoi/.chezmoitemplates/rectangle.plist.tmpl
  ```
- `chezmoi apply` uses [`run_onchange_import_rectangle.sh.tmpl`](.chezmoiscripts/run_onchange_import_rectangle.sh.tmpl) to automatically apply Rectangle's plist. To manually apply the plist, use the following command:
  ```sh
  chezmoi execute-template -f .chezmoiscripts/run_onchange_import_rectangle.sh.tmpl | sh
  ```
- To re-add DockDoor.plist, use the following command:
  ```sh
  defaults export com.ethanbills.DockDoor - > ~/.local/share/chezmoi/.chezmoitemplates/dockdoor.plist.tmpl
  ```
  Then strip transient keys (`SUHasLaunchedBefore`, `SULastCheckTime`, `launched`, `lastKnownScreenRecordingPermission`, `persistedWindowOrder`) before committing.
- `chezmoi apply` uses [`run_onchange_import_dockdoor.sh.tmpl`](.chezmoiscripts/run_onchange_import_dockdoor.sh.tmpl) to automatically apply DockDoor's plist. To manually apply the plist, use the following command:
  ```sh
  chezmoi execute-template -f .chezmoiscripts/run_onchange_import_dockdoor.sh.tmpl | sh
  ```

## AltTab (macOS)

[`run_onchange_configure_alttab.sh.tmpl`](.chezmoiscripts/run_onchange_configure_alttab.sh.tmpl) sets **Select previous window** to **Shift+Tab** (`previousWindowShortcut` in `com.lwouis.alt-tab-macos`). It runs on `chezmoi apply` when that script changes. To apply once by hand:

```sh
chezmoi execute-template -f .chezmoiscripts/run_onchange_configure_alttab.sh.tmpl | sh
```

Restart AltTab (or log out and back in) if the shortcut does not pick up immediately.
