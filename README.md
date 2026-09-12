These dotfiles are managed by [mise](https://mise.jdx.dev) (`mise bootstrap`) and [Nix Home Manager](https://github.com/nix-community/home-manager).

## Prerequisites

### Windows

- git
- mise
  ```pwsh
  winget install jdx.mise
  ```

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

Clone this repo:

```sh
git clone https://github.com/kot149/dotfiles.git ~/.local/share/chezmoi
cd ~/.local/share/chezmoi
```

On macOS/Linux, enter the Nix environment when working on this repository. It
provides the bootstrap tools before Home Manager is available:

```sh
nix shell nixpkgs#mise nixpkgs#python3 nixpkgs#bun nixpkgs#uv nixpkgs#jq
```

On Windows, use mise to install the tools declared in `mise.windows.toml`:

```pwsh
mise trust
mise install
```

Then converge everything (repos, dotfiles, apply tasks):

```sh
mise trust
mise run setup      # per-machine values (git identity, ...) -> mise.local.toml
mise bootstrap
```

`MISE_ENV` selects additional layers explicitly (`-E`); the OS layer (`unix` + `macos`/`linux`/`windows`) loads automatically via `auto_env` in [`.miserc.toml`](.miserc.toml).

For an existing chezmoi installation, migrate before the first bootstrap:

```sh
mise run migrate-from-chezmoi
mise bootstrap
```

Migration imports missing machine values from `~/.config/chezmoi/chezmoi.toml`
(or `$XDG_CONFIG_HOME/chezmoi/chezmoi.toml`), preserving existing `mise.local.toml`
values, then adopts the dotfiles with backups. `mise run setup` uses the same
legacy values as prompt defaults. For a custom chezmoi config path, import it
first with `uv run --script scripts/setup.py --migrate --chezmoi-config PATH`.

Third-party skills record their installed source and revision in
`.mise-skill-pin.json`. Bootstrap updates missing or changed pins; existing
skills without a marker are downloaded once to verify their contents.

## Managing OS-specific files

OS-specific targets live in `mise.macos.toml`, `mise.linux.toml`, `mise.windows.toml` (plus shared-unix `mise.unix.toml`); cross-platform targets live in `mise.toml`.

## How file placement and post-placement work

This repo has two stages: `[dotfiles]` places files, `[tasks]` runs post-placement processing. Settings live in `mise.toml` plus the OS layers above.

Rough flow for `mise bootstrap`:

1. Converge repos (`[bootstrap.repos]`, currently Windows only).
2. Apply dotfiles from `[dotfiles]`.
3. Install tools from `[tools]`.
4. Run `mise run bootstrap`, which fans out to each apply task.

### If you remember nothing else

```sh
mise bootstrap                  # daily use: just run this
mise bootstrap dotfiles status  # before anything scary: check this first
```

New files: register with a plain `{ source = "..." }` (symlink) and fix it up only if it breaks. One question decides the mode: "is the content identical on every machine?" If yes, keep the symlink. If it varies per machine, use `mode = "template"`. If it is a `.nix` file consumed by a flake, use `mode = "copy"`. If the app rewrites the file itself (e.g. VS Code settings), keep it out of `[dotfiles]` and merge it via an apply task instead.

### Adding a dotfile

Put the source under `dotfiles/` or `templates/`, then register it in the right `[dotfiles]` (`mise.toml` for shared, `mise.linux.toml` etc. for OS-specific):

```toml
[dotfiles]
"~/.config/foo/config.toml" = { source = "dotfiles/.config/foo/config.toml" }
```

Then apply only that target:

```sh
mise bootstrap dotfiles apply ~/.config/foo/config.toml
```

There is no chezmoi-style naming (`dot_`, `executable_`). The target path is the table key, and the executable bit comes from the source file.

Behavior after editing a source depends on its mode:

| Mode | Use for | After editing source |
| --- | --- | --- |
| (default, symlink) | Static config files | Visible immediately through the link |
| `mode = "copy"` | Files Home Manager reads (e.g. `*.nix` under `~/.config/home-manager/`) | Re-copy with `dotfiles apply` |
| `mode = "template"` | Git config, OS-specific settings (`*.tera`) | Re-render with `dotfiles apply` |

Example for a template:

```sh
mise bootstrap dotfiles apply ~/.config/git/config.machine
```

Note: if an app rewrites a symlinked target, the repo source changes too. After files land, some apps still need a restart or config reload.

### Removing a dotfile

Three separate steps:

1. Remove the `[dotfiles]` registration.
2. Remove the now-unneeded source in the repo.
3. If the `$HOME` file or link is also unneeded, check the target and delete it individually.

Removing the registration does not delete the `$HOME` file. Deleting only the source leaves a broken link. To keep the content but stop managing it, replace the link with a regular file. `mise bootstrap dotfiles unapply` is prohibited in this repo.

### Tasks replace `run_onchange_*`

Ordering and change detection come from the task definition, not the script name. Example:

```toml
[tasks.apply-vscode-settings]
run = "sh scripts/apply-vscode-settings.sh"
run_windows = "pwsh -NoProfile -File scripts/apply-vscode-settings.ps1"
sources = [
  "templates/vscode/settings.json",
  "scripts/apply-vscode-settings.sh",
  "scripts/apply-vscode-settings.ps1",
  "scripts/merge-vscode-settings.py",
]
```

- `run`: Unix/macOS implementation.
- `run_windows`: Windows implementation.
- `sources`: inputs used to decide whether to re-run.
- `depends`: tasks that run first.

Nothing watches files continuously. When `mise bootstrap` or `mise run <task>` starts, tasks whose `sources` are unchanged are usually skipped. Explicit `before`/`after` ordering is now `depends`, for example:

```text
apply-nix-linux-conf
  -> apply-nix-custom-conf
    -> apply-home-manager
      -> apply-nix-darwin / apply-tailscaled-launchd / apply-herdr-plugins
```

`apply-karabiner-goku` also runs after `apply-nix-custom-conf`. Independent tasks may run in parallel, so do not rely on the order items are listed in `bootstrap.depends`. `apply-tailscaled-launchd` intentionally has no `sources` and checks the installed binary on every run (including after Home Manager updates).

### Which command to run

| Command | Scope |
| --- | --- |
| `mise bootstrap` | File placement through each apply task |
| `mise bootstrap dotfiles apply` | File placement only, no apply tasks |
| `mise run apply-vscode-settings` | That task plus its dependencies only |
| `mise run bootstrap` | Apply tasks only, no preceding dotfiles placement |

So editing a template is not enough with `mise run apply-home-manager` alone, since the template has not been re-rendered yet. Either run the targeted `dotfiles apply` first or use `mise bootstrap`.

To add a new `run_onchange_*` equivalent: create the script, register the task with `run`/`run_windows` and `sources`, and add it to `bootstrap.depends`.

`generated/` is not part of `bootstrap`. After changing permission or cache inputs, regenerate first:

```sh
mise run generate-agent-files
mise bootstrap
```

Useful checks:

```sh
mise bootstrap dotfiles status
mise bootstrap plan
mise run -n apply-vscode-settings
```

To re-run a task even when `sources` are unchanged, use `mise run --force apply-vscode-settings`. This is task re-execution, not forced file overwrite (that is `dotfiles apply --force`).

## Git (shared + per-machine)

Global Git is split so portable settings live in the repo and machine-specific values stay overridable per host:

- Shared: [`templates/gitconfig.tera`](templates/gitconfig.tera) (includes `~/.config/git/config.machine`, hunk, LFS, optional `safe.directory` from comma-separated `git_safe_directories` in vars).
- Per machine: [`templates/git/config.machine.tera`](templates/git/config.machine.tera) → `~/.config/git/config.machine` (defaults target the **kot149** GitHub profile; override in `mise.local.toml` on work PCs, etc.).

Defaults live in [`mise.toml [vars]`](mise.toml) (**kot149** + GitHub noreply email). If `git_signing_key` / `git_allowed_signers` are left empty, `config.machine.tera` falls back to `$HOME/.ssh/id_ed25519_github_kot149.pub` and `$HOME/.ssh/allowed_signers`. **`mise.local.toml`** `[vars]` overrides `mise.toml`, so a work machine can point at different keys without editing the repo.

Example override for a work machine:

```toml
[vars]
git_user_name = "Your Work Name"
git_user_email = "you@company.example"
git_signing_key = "C:/Users/you/.ssh/id_ed25519_work.pub"
git_allowed_signers = "C:/Users/you/.ssh/allowed_signers_work"
git_editor = "code --wait"
git_commit_gpgsign = "true"
git_safe_directories = ""
```

On a new machine, `mise run setup` prompts with **kot149-oriented defaults**; answers are written to `mise.local.toml`. Re-running setup preserves other settings and comments. To add more machine-only Git snippets, edit `config.machine.tera` in this repo (structure only) or override keys via `[vars]` as above.

## Managing Winget packages

Export:

```sh
winget export -o ~/winget.json
```

Import:

```sh
winget import ~/winget.json
```

The list is managed at `dotfiles/winget.json` (applied to `~/winget.json` on Windows).

## Managing `.plist` files
- To re-add Rectangle.plist, use the following command:
  ```sh
  defaults export com.knollsoft.Rectangle - > ~/.local/share/chezmoi/templates/macos/rectangle.plist
  ```
- `mise run import-rectangle` (part of `mise bootstrap`) imports it via `scripts/import-rectangle.sh`. To apply once by hand:
  ```sh
  mise run import-rectangle
  ```
- To re-add DockDoor.plist, use the following command:
  ```sh
  defaults export com.ethanbills.DockDoor - > ~/.local/share/chezmoi/templates/macos/dockdoor.plist
  ```
  Then strip transient keys (`SUHasLaunchedBefore`, `SULastCheckTime`, `launched`, `lastKnownScreenRecordingPermission`, `persistedWindowOrder`) before committing.
- `mise run import-dockdoor` (part of `mise bootstrap`) imports it via `scripts/import-dockdoor.sh`. To apply once by hand:
  ```sh
  mise run import-dockdoor
  ```

## AltTab (macOS)

`mise run configure-alttab` (part of `mise bootstrap`) sets **Select previous window** to **Shift+Tab** (`previousWindowShortcut` in `com.lwouis.alt-tab-macos`).

Restart AltTab (or log out and back in) if the shortcut does not pick up immediately.
