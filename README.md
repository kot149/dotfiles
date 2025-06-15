These dotfiles are maneged by [chezmoi](https://www.chezmoi.io).

To apply:
1. [install chezmoi](https://www.chezmoi.io/install/)
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
2. run:
    ```sh
    chezmoi init --apply kot149
    ```
    or
   ```sh
   chezmoi init --apply git@github.com:kot149/dotfiles.git
   ```
