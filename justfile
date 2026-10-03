# Maintenance tasks for these dotfiles. Run from anywhere through the `dots`
# shell alias, which points just at this file; recipes run in this directory.

set windows-shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

python := if os_family() == "windows" { "python" } else { "python3" }

# List the tasks
default:
    @just --justfile '{{ justfile() }}' --list

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[macos]
update: pull skills-update hm-update darwin-update sheldon-update mise-upgrade gh-ext-upgrade

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[linux]
update: pull skills-update hm-update sheldon-update mise-upgrade gh-ext-upgrade

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[windows]
update: pull skills-update gh-ext-upgrade

# Apply the source state to $HOME (extra args go to chezmoi apply)
[group('chezmoi')]
apply *args:
    chezmoi apply {{ args }}

# Pull the dotfiles repo and apply it
[group('chezmoi')]
pull:
    chezmoi update

# Show what apply would change
[group('chezmoi')]
diff *args:
    chezmoi diff {{ args }}

# List targets that differ from the source state
[group('chezmoi')]
status:
    chezmoi status

# Report third-party agent skills whose pinned rev is behind upstream
[group('skills')]
skills-check:
    {{ python }} scripts/update_agent_skills.py --check

# Review and bump third-party agent skill revs, then install them
[group('skills')]
skills-update *args:
    {{ python }} scripts/update_agent_skills.py {{ args }}
    chezmoi apply ~/.claude/skills ~/.agents/skills

# Rebuild the Home Manager generation without updating flake inputs
[group('nix')]
[unix]
hm-switch:
    nh home switch ~/.config/home-manager/ -c default

# Update the Home Manager flake inputs and rebuild
[group('nix')]
[unix]
hm-update:
    nh home switch ~/.config/home-manager/ -c default -u

# Update the nix-darwin flake inputs and rebuild
[group('nix')]
[macos]
darwin-update:
    cd ~/.config/nix-darwin && nix flake update
    cd ~/.config/nix-darwin && sudo -H nix --extra-experimental-features 'nix-command flakes' run github:LnL7/nix-darwin#darwin-rebuild -- switch --flake ".#$(hostname -s)"

# Delete Nix generations older than 30 days, keeping the latest one
[group('nix')]
[unix]
nix-clean:
    nh clean all --keep-since 30d --keep-one

# Update zsh plugins (through the sheldon wrapper in .zshrc)
[group('tools')]
[unix]
sheldon-update:
    zsh -ic 'sheldon lock --update'

# Upgrade the tools in the global mise config
[group('tools')]
[unix]
mise-upgrade:
    mise upgrade

# Upgrade gh CLI extensions
[group('tools')]
gh-ext-upgrade:
    gh extension upgrade --all

# Upgrade winget packages (run by hand; not part of update)
[group('tools')]
[windows]
winget-upgrade:
    winget upgrade --all

# Run the hook tests
[group('dev')]
test:
    bun run tests/textlint-rule-ja-ai-phrasing.js
