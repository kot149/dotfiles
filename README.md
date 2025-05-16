my dotfiles maneged by chezmoi

To apply:
1. [install chezmoi](https://www.chezmoi.io/install/)
   - Linux:
     ```sh
     sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
     ```
     If fails due to `unable to resolve host address ‘get.chezmoi.io’`, download https://get.chezmoi.io then
     ```sh
      ./install_chezmoi.sh -b $HOME/.local/bin
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
