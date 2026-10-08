# Maintenance tasks for these dotfiles. Run from anywhere through the `dots`
# shell alias, which points just at this file; recipes run in this directory.

set windows-shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

uv_script := "uv run --no-python-downloads --script"

# List the tasks
default:
    @just --justfile '{{ justfile() }}' --list

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[macos]
update: pull skills-update hm-update darwin-update sheldon-update mise-upgrade pkgs-update gh-ext-upgrade

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[linux]
update: pull skills-update hm-update sheldon-update mise-upgrade pkgs-update gh-ext-upgrade

# Pull the dotfiles repo, apply it, then update everything this machine uses
[group('all')]
[windows]
update: pull skills-update pkgs-update gh-ext-upgrade

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
    {{ uv_script }} scripts/update_agent_skills.py --check

# Review, bump and commit third-party agent skill revs, then install them
[group('skills')]
skills-update *args:
    {{ uv_script }} scripts/update_agent_skills.py {{ args }}
    chezmoi apply ~/.claude/skills ~/.agents/skills

# Check the agent-skill tree: wrappers, store parity, frontmatter, agent_skills
[group('skills')]
skills-lint:
    {{ uv_script }} scripts/check_agent_skills.py

# Report skill directories in ~/.claude/skills and ~/.agents/skills that this repo does not manage
[group('skills')]
skills-drift:
    {{ uv_script }} scripts/check_agent_skills.py --home

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
    nh darwin switch ~/.config/nix-darwin -H "$(hostname -s)" -u

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

# List globally installed bun / npm / pnpm / uv / cargo / go packages
[group('tools')]
pkgs-list *managers:
    {{ uv_script }} scripts/global_packages.py list {{ managers }}

# Update globally installed bun / npm / pnpm / uv / cargo / go packages
[group('tools')]
pkgs-update *managers:
    {{ uv_script }} scripts/global_packages.py update {{ managers }}

# Find commands installed by both bun / npm / pnpm / uv / cargo / go and Nix / winget / others
[group('tools')]
pkgs-dupes:
    {{ uv_script }} scripts/duplicate_packages.py

# Upgrade gh CLI extensions
[group('tools')]
gh-ext-upgrade:
    gh extension upgrade --all

# Upgrade winget packages (run by hand; not part of update)
[group('tools')]
[windows]
winget-upgrade:
    winget upgrade --all

# Render the agent config templates and check that the output parses
[group('dev')]
render-check:
    {{ uv_script }} scripts/render_check.py

# Run the textlint rule test, the repo-only skill-tree check and the template render check
[group('dev')]
test:
    #!/usr/bin/env bash
    status=0
    '{{ just_executable() }}' --justfile '{{ justfile() }}' skills-lint || status=1
    '{{ just_executable() }}' --justfile '{{ justfile() }}' render-check || status=1
    bun run tests/textlint-rule-ja-ai-phrasing.js || status=1
    {{ uv_script }} tests/update_agent_skills.py || status=1
    bash tests/writing-style.sh || status=1
    {{ uv_script }} tests/hooks.py || status=1
    {{ uv_script }} tests/merge_config.py || status=1
    {{ uv_script }} tests/permissions.py || status=1
    exit $status
