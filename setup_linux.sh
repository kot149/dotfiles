#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Install zsh
sudo apt install zsh -y
chsh -s $(which zsh)

# Setup git
git config --global init.defaultBranch main

# Setup git
sudo apt install gh
gh auth login

# Install shelcon
curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin

# INstall oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install oh-my-posh
curl -s https://ohmyposh.dev/install.sh | bash -s

# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
./.local/bin/chezmoi init --apply kot149

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
