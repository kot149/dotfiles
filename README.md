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
- macOS / Linux: on Determinate Nix, writes `/etc/nix/nix.custom.conf` (`sudo`), then runs the Home Manager switch. The first switch builds the whole package set and takes minutes;
- macOS: also runs the nix-darwin switch (prompts for the `sudo` password) and installs the tailscaled LaunchDaemon (`sudo`) when tailscaled is installed;
- Linux: on Nix installs without `nix.custom.conf`, edits `/etc/nix/nix.conf` (`sudo`);
- Windows: no Nix step; clones the PowerShell / AutoHotkey libraries.

To preview first, clone without applying and check the diff:

```sh
chezmoi init kot149
chezmoi diff
```

Then run `chezmoi apply -v`.

## Maintenance

The `dots` alias runs the repo [`justfile`](justfile) from anywhere.

| Command | What it does |
|---|---|
| `dots` | List the tasks |
| `dots update` | Pull the repo and apply it |
| `dots update --all` | Also update agent skills, Nix, tools and global packages for the current OS |
| `dots skills-update` | Review and bump third-party agent skill revs, then install them |
| `dots doctor` | Report stale ignore entries, missing tools, untrusted Codex hooks and unmanaged skills |
| `dots test` | Run the repo checks |

`dots` also lists the other tasks (`hm-switch`, `nix-clean`, `pkgs-update`, `winget-upgrade`, ...).

## AI agent configuration

The hooks, permission lists and skills for Claude Code, Codex CLI, opencode and Antigravity are generated from single sources under [`.chezmoitemplates/`](.chezmoitemplates) and [`.chezmoidata/`](.chezmoidata). [`AGENTS.md`](AGENTS.md) documents the layout and the rules.

### Customizing third-party skills

Third-party skills are pinned in [`.chezmoidata/agent-skills.toml`](.chezmoidata/agent-skills.toml). To change one, put a unified diff against the pinned rev in [`scripts/agent-skill-patches/`](scripts/agent-skill-patches) as `<skill-name>.patch` (paths relative to the skill root, e.g. `a/SKILL.md`), then run `dots skills-install`. Do not edit the installed copies.

If a patch no longer applies, the installer and `dots skills-update` fail for that repo and leave its installed skills and pins unchanged. Adapt the patch to the new upstream and retry.

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).

## Git config

- Shared: [`dot_gitconfig.tmpl`](dot_gitconfig.tmpl), which includes `~/.config/git/config.machine`.
- Per-machine: [`private_dot_config/git/create_config.machine.tmpl`](private_dot_config/git/create_config.machine.tmpl) creates `~/.config/git/config.machine` only when it is absent. Edit that local file afterwards to change machine-only settings.

Defaults live in [`.chezmoidata/git.toml`](.chezmoidata/git.toml) (**kot149** + GitHub noreply email; signing key `$HOME/.ssh/id_ed25519_github_kot149.pub`). `chezmoi init` prompts for the values and writes them to `~/.config/chezmoi/chezmoi.toml`, whose `[data]` overrides the defaults. Example for a work machine:

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

## Development

Install the commit hooks after cloning:

```sh
just hooks-install
```

The hook formats staged Python and Nix files and runs `just lint`. Restage the formatting changes and retry the commit.

`just test` runs every check (also run by CI on Ubuntu, macOS and Windows). While editing, run one part:

```sh
just test-hooks
just test-permissions
just lint --only python
just lint private_dot_config/opencode/plugins/
```
