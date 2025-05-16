my dotfiles maneged by chezmoi

To apply:
1. [install chezmoi](https://www.chezmoi.io/install/)
   - Linux:
     ```sh
     sh -c "$(curl -fsLS https://get.chezmoi.io)"
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
