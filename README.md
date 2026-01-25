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

## Applying dotfiles

```sh
chezmoi init --apply kot149
```

or with nix:

```sh
nix --extra-experimental-features "flakes nix-command" run nixpkgs#chezmoi -- init --apply kot149 --branch feat/nix
```

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).


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

## Managing Homebrew packages

Export:
```sh
brew bundle dump --global --force && chezmoi add ~/.Brewfile
```

Import:
```sh
chezmoi apply
```
```sh
brew bundle --global
```

## Managing `.plist` files
- To re-add Rectangle.plist, use the following command:
  ```sh
  defaults export com.knollsoft.Rectangle - > ~/.local/share/chezmoi/.chezmoitemplates/rectangle.plist.tmpl
  ```
- `chezmoi apply` uses [`run_onchange_import_rectangle.sh.tmpl`](run_onchange_import_rectangle.sh.tmpl) to automatically apply Rectangle's plist.
