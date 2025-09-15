These dotfiles are maneged by [chezmoi](https://www.chezmoi.io).

## Prerequisites
- Git installed
- [chezmoi](https://www.chezmoi.io/install/) installed
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

Run
```sh
chezmoi init --apply kot149
```

## (Re-)Addding dotfiles

- Run `chezmoi add`.
  ```sh
  chezmoi add <path_to_file_to_add>
  ```

## Managing OS-specific files

Edit `.chezmoiignore.tmpl`.

## Managing `.plist` files
- To re-add Rectangle.plist, use the following command:
  ```sh
  defaults export com.knollsoft.Rectangle - > ~/.local/share/chezmoi/.chezmoitemplates/rectangle.plist.tmpl
  ```
- `chezmoi apply` uses `run_onchange_import_rectangle.sh.tmpl` to automatically apply Rectangle's plist.
