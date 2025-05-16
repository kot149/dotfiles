#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Setup git
sudo apt install gh
gh auth login

# Install oh-my-posh
curl -s https://ohmyposh.dev/install.sh | bash -s

# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin
./.local/bin/chezmoi init --apply kot149
