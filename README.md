These dotfiles are maneged by [chezmoi](https://www.chezmoi.io).

## Prerequisites
- Install Git
- Install [chezmoi](https://www.chezmoi.io/install/)
   - Linux:
     ```sh
     sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
     ```
   - Window:
     ```pwsh
     winget install twpayne.chezmoi
     ```
   - macOS:
     ```sh
     brew install chezmoi
     ```
     
## Applying dotfiles

```sh
chezmoi init --apply kot149
```

or with nix:

```sh
nix run nixpkgs#chezmoi -- init --apply kot149
```

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).

## Managing `.plist` files
- To re-add Rectangle.plist, use the following command:
  ```sh
  defaults export com.knollsoft.Rectangle - > ~/.local/share/chezmoi/.chezmoitemplates/rectangle.plist.tmpl
  ```
- `chezmoi apply` uses [`run_onchange_import_rectangle.sh.tmpl`](run_onchange_import_rectangle.sh.tmpl) to automatically apply Rectangle's plist.
