These dotfiles are maneged by [chezmoi](https://www.chezmoi.io) and [Nix Home Manager](https://github.com/nix-community/home-manager).

## Prerequisites

### Windows

- git
- chezmoi
  ```pwsh
  winget install twpayne.chezmoi
  ```

### Linux / Mac

- Linux: curl, xz-utils
  ```sh
  apt update && apt install curl xz-utils -y
  ```
- Nix
  ```sh
  sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon --yes
  ```
  ```sh
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  ```
- Or, Nix via Determinate Nix installer:
  ```sh
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install
  ```

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

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).

## Git (shared + per-machine)

Global Git is split so portable settings live in the repo and machine-specific values (account, signing paths, `core.editor`, extra sections you add to the template) stay overridable per host:

- Shared: [`dot_gitconfig.tmpl`](dot_gitconfig.tmpl) (includes `~/.config/git/config.machine`, delta, LFS, optional `safe.directory` from `git_safe_directories` in data).
- Per machine: [`private_dot_config/git/config.machine.tmpl`](private_dot_config/git/config.machine.tmpl) → `~/.config/git/config.machine` (defaults target the **kot149** GitHub profile; override in `~/.config/chezmoi/chezmoi.toml` on work PCs, etc.).

Defaults live in [`.chezmoidata.toml`](.chezmoidata.toml) (**kot149** + GitHub noreply email). If `git_signing_key` / `git_allowed_signers` are left empty, [`config.machine.tmpl`](private_dot_config/git/config.machine.tmpl) falls back to `$HOME/.ssh/id_ed25519_github_kot149.pub` and `$HOME/.ssh/allowed_signers`. **`~/.config/chezmoi/chezmoi.toml`** `[data]` overrides `.chezmoidata.toml`, so a work machine can point at different keys without editing the repo.

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

On a new machine, `chezmoi init` runs [`.chezmoi.toml.tmpl`](.chezmoi.toml.tmpl) and prompts with **kot149-oriented defaults**; answers are written to `~/.config/chezmoi/chezmoi.toml`. To add more machine-only Git snippets, edit `config.machine.tmpl` in this repo (structure only) or override keys via `[data]` as above.

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

## AltTab (macOS)

[`run_onchange_configure_alttab.sh.tmpl`](.chezmoiscripts/run_onchange_configure_alttab.sh.tmpl) sets **Select previous window** to **Shift+Tab** (`previousWindowShortcut` in `com.lwouis.alt-tab-macos`). It runs on `chezmoi apply` when that script changes. To apply once by hand:

```sh
chezmoi execute-template -f .chezmoiscripts/run_onchange_configure_alttab.sh.tmpl | sh
```

Restart AltTab (or log out and back in) if the shortcut does not pick up immediately.
