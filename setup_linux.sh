#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# sudo apt install build-essential -y

# Install zsh
sudo apt install zsh -y
chsh -s $(which zsh)

# Setup git
git config --global init.defaultBranch main

# Install gh
(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y

# Install shelcon
curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install oh-my-posh
# curl -s https://ohmyposh.dev/install.sh | bash -s

# Install Starship
curl -sS https://starship.rs/install.sh | sh

# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
~/.local/bin/chezmoi init --apply kot149

# Install bat
sudo apt install bat -y

# Install fzf
# nix profile install nixpkgs#fzf

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
