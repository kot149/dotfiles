# Setting up a New Machine

## Linux

### Chezmoi

1. [install chezmoi](https://www.chezmoi.io/install/)
2. Apply chezmoi
    ```sh
    chezmoi init --apply kot149
    ```
    or
   ```sh
   chezmoi init --apply git@github.com:kot149/dotfiles.git
   ```

### Zsh
wip

### sheldon
```sh
curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
    | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
```

### Oh-My-Zsh

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### Oh-My-Posh
wip