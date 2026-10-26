These dotfiles are managed by [chezmoi](https://www.chezmoi.io) and [Nix Home Manager](https://github.com/nix-community/home-manager).

## Development

Install the commit hooks after cloning:

```sh
just hooks-install
```

The hooks autoformat staged Python and Nix files, then run `just lint`.
Restage formatting changes and retry the commit. Nix templates are checked
after rendering by `just lint`; format their source manually.
The hooks use `ruff`, `nixfmt`, `shellcheck`, `oxlint`, `chezmoi`, `uv` and
`just` from PATH. `just lint` skips unavailable linters.

The installed POSIX hook also works when the global `core.hooksPath` hook
delegates to `.git/hooks/pre-commit` using `sh`.

### Focused checks

Use focused checks while editing; reserve `just test` for the full check before
finishing. With no arguments, `just test` still runs all checks sequentially and
collects failures; `just lint` still checks the whole repository.

```sh
just test-hooks
just test-permissions
just test-merge-config
just lint --only python
just lint scripts/lint.py tests/lint.py
just lint --only js private_dot_config/opencode/plugins/
```

`just --list` lists every `test-*` recipe. Each runs one test script without
the full-suite lint/render prerequisites. `just skills-lint`, `just hooks-lint`
and `just render-check` also remain independently runnable.

Lint accepts source files or directories relative to the repository root (or
absolute paths inside it), including `.tmpl` source paths. Selected templates
are still rendered for both macOS and Linux, with identical output checked once.
Use `--only shell|python|nix|js` to select a language; repeat `--only` to combine
languages. A missing path or a path with no matching lint sources is an error,
not a successful no-op. Linters that are not installed are still skipped.

## Prerequisites

### Windows

- Git for Windows. Its Git Bash (default `C:/Program Files/Git/bin/bash.exe`, overridable per machine via `git_bash_path` in `~/.config/chezmoi/chezmoi.toml`) runs the Claude Code and Codex shell hooks.
  ```pwsh
  winget install Git.Git
  ```
- chezmoi
  ```pwsh
  winget install twpayne.chezmoi
  ```
- just, for `dots`
  ```pwsh
  winget install Casey.Just
  ```
- uv, used by the Python hooks, the Python parsers inside the bash hooks and the `just` recipes. None of them download Python, so run `uv python install` once.
  ```pwsh
  winget install astral-sh.uv
  ```
- jq, for the bash hooks
  ```pwsh
  winget install jqlang.jq
  ```
- bun, for the writing-style hook and `just test`
  ```pwsh
  winget install Oven-sh.Bun
  ```
- rtk, for the agent command rewrite hooks
  ```pwsh
  winget install rtk-ai.rtk
  ```

`winget import winget.json` (run from the repo, see [Managing Winget packages](#managing-winget-packages)) installs all of them.

### Linux / Mac

- Linux: curl, xz-utils
  ```sh
  apt update && apt install curl xz-utils -y
  ```
- Nix via [nix-installer](https://github.com/NixOS/nix-installer):
  ```sh
  curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
  ```
  ```sh
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  ```
- Or, Nix via Determinate Nix installer:
  ```sh
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install
  ```

Everything else (`just`, `uv`, `bun`, `rtk`, `nh`, ...) is installed by Home Manager on the first apply.

#### Linux with no root

Use nix-portable

```sh
cd ~/.local/bin
curl -L https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m) > ./nix-portable
chmod +x ./nix-portable
ln -s nix-portable nix
ln -s nix-portable nix-build
ln -s nix-portable nix-channel
ln -s nix-portable nix-collect-garbage
ln -s nix-portable nix-copy-closure
ln -s nix-portable nix-daemon
ln -s nix-portable nix-env
ln -s nix-portable nix-hash
ln -s nix-portable nix-instantiate
ln -s nix-portable nix-prefetch-url
ln -s nix-portable nix-shell
ln -s nix-portable nix-store
```

and add this to the `~/.bashrc`
```sh
if [ -z "$NP_RUNTIME" ] && [ -t 0 ]; then
    export NP_RUNTIME=bwrap
    export PATH="$HOME/.nix-profile/bin:$PATH"
    exec nix-portable nix shell nixpkgs#zsh nixpkgs#bashInteractive -c zsh
fi
```

## Applying dotfiles

```sh
chezmoi init --apply kot149
```

or with nix:

```sh
nix --extra-experimental-features "flakes nix-command" run nixpkgs#chezmoi -- init --apply kot149
```

Besides rendering the managed files into `$HOME`, the first apply:

- downloads the pinned third-party agent skills into `~/.claude/skills` and `~/.agents/skills` (every OS);
- macOS / Linux: on Determinate Nix, writes `/etc/nix/nix.custom.conf` (`sudo`), then runs the Home Manager switch through `nh home switch` (falls back to `nix run home-manager/master` when `nh` is not installed yet, as on the very first apply). The first switch builds the whole package set and takes minutes;
- macOS: also runs the nix-darwin switch (`nh darwin switch`, or `nix run github:nix-darwin/nix-darwin#darwin-rebuild` before `nh` exists; prompts for the `sudo` password), including Rectangle, DockDoor and AltTab preferences, and the Karabiner script, and installs the tailscaled LaunchDaemon (`sudo`) when tailscaled is installed;
- Linux: on Nix installs without `nix.custom.conf`, edits `/etc/nix/nix.conf` (`sudo`);
- Windows: no Nix step; clones the PowerShell / AutoHotkey libraries.

To preview first, clone without applying and check the diff (`chezmoi apply --dry-run -v` prints the same without changing anything):

```sh
chezmoi init kot149
chezmoi diff
```

Then run `chezmoi apply -v`.

## Maintenance (`dots`)

The `dots` alias ([`dot_zshrc`](dot_zshrc), and a function in the [PowerShell profile](readonly_Documents/PowerShell/Microsoft.PowerShell_profile.ps1)) runs the repo [`justfile`](justfile) from anywhere. `dots` alone lists the tasks, `dots update` pulls the repo and applies it, `dots update --all` (or `--full`) also updates everything for the current OS (`update-full`), and `dots test` runs the repo checks.

| Task | What it does |
|---|---|
| `update-full` | Pull the dotfiles repo and apply it, then update agent skills, Nix, tools and global packages (the task list differs per OS) |
| `apply *args` | Apply the source state to `$HOME` (extra args go to `chezmoi apply`) |
| `update *flags` | Pull the dotfiles repo and apply it; with `--all` or `--full`, run `update-full` instead |
| `pull` | Pull the dotfiles repo without applying it |
| `diff *args` | Show what apply would change |
| `status` | List targets that differ from the source state |
| `skills-check` | Report third-party agent skills whose pinned rev is behind upstream |
| `skills-update *args` | Review, bump and commit third-party agent skill revs, then install them |
| `skills-lint` | Check the agent-skill tree: wrappers, store parity, frontmatter, `agent_skills` |
| `skills-drift` | Report skill directories in `~/.claude/skills` and `~/.agents/skills` that this repo does not manage |
| `hm-switch` (macOS / Linux) | Rebuild the Home Manager generation without updating flake inputs |
| `hm-update` (macOS / Linux) | Update the Home Manager flake inputs and rebuild |
| `darwin-update` (macOS) | Update the nix-darwin flake inputs and rebuild |
| `nix-clean` (macOS / Linux) | Delete Nix generations older than 30 days, keeping the latest one |
| `sheldon-update` (macOS / Linux) | Update zsh plugins |
| `mise-upgrade` (macOS / Linux) | Upgrade the tools in the global mise config |
| `pkgs-list *managers` | List globally installed bun / npm / pnpm / uv / cargo / go packages |
| `pkgs-update *managers` | Update globally installed bun / npm / pnpm / uv / cargo / go packages |
| `pkgs-dupes` | Find commands installed by both bun / npm / pnpm / uv / cargo / go and Nix / apt / winget / others |
| `gh-ext-upgrade` | Upgrade gh CLI extensions |
| `winget-upgrade` (Windows) | Upgrade winget packages (run by hand; not part of `update-full`) |
| `apt-upgrade` (Linux) | Upgrade apt packages (run by hand; not part of `update-full`) |
| `render-check` | Render the agent config templates and check that the output parses |
| `lint` | Run shellcheck, ruff, nixfmt and oxlint over the repo |
| `doctor *args` | Report stale ignore entries, missing Nix hash globs, missing tools, Codex hooks with no trust entry or possibly stale trust, and unmanaged skill directories (run last by `update-full`; `--no-home` skips the `$HOME` checks) |
| `ci-render *args` | Apply the source tree into a scratch directory without scripts and externals, then parse the agent configs (extra args go to `chezmoi`) |
| `hooks-lint` | Check `.chezmoidata/agent-hooks.toml` against the hook files in `dot_claude/hooks` and `dot_codex/hooks` |
| `test` | Run `skills-lint`, `hooks-lint`, `render-check`, `lint` and the tests under [`tests/`](tests) |

Every push to `main` and every pull request runs [`.github/workflows/check.yml`](.github/workflows/check.yml), which runs `ci-render`, `test` and `doctor --no-home` on Ubuntu, macOS and Windows.

## AI agent configuration

The hooks, permission lists and skills for Claude Code, Codex CLI, opencode and Antigravity live in this repo ([`dot_claude/`](dot_claude), [`dot_codex/`](dot_codex), [`dot_agents/`](dot_agents), [`private_dot_config/opencode/`](private_dot_config/opencode), [`dot_gemini/`](dot_gemini)) and are generated from single sources under [`.chezmoitemplates/`](.chezmoitemplates) and [`.chezmoidata/`](.chezmoidata). [`AGENTS.md`](AGENTS.md) documents the layout and the rules.

### Delegated commits

Use `/commit-delegate` for the separate lightweight-worker workflow; `/commit`
keeps its existing behavior. The worker reads status, diffs and history, proposes
three messages, obtains your selection, then stages explicit paths and commits.
Claude Code selects Haiku; GPT runtimes must expose a write-capable Luna
(`gpt-6-luna`) model or role. If the runtime cannot select a lightweight worker,
the skill stops rather than running the workflow on the main model.

Only message choices (when the worker cannot ask directly), scope warnings and
the final result reach the main agent. Raw Git output stays in the worker;
coordination still uses some main-agent context. The shared body and worker
reference install into both `~/.claude/skills/commit-delegate` and
`~/.agents/skills/commit-delegate`.

### Customizing third-party skills

Third-party skills stay pinned in [`.chezmoidata/agent-skills.toml`](.chezmoidata/agent-skills.toml). Local changes live in [`scripts/agent-skill-patches/`](scripts/agent-skill-patches) as one unified diff per skill: `<skill-name>.patch`, with paths relative to the skill root (`a/SKILL.md`, `b/SKILL.md`, or paths under `references/` and `scripts/`). The same patch feeds every declared agent store; do not edit the installed copies.

The external template automatically enables [`filter_agent_skill.py`](scripts/filter_agent_skill.py) for skills with a patch. The filter reads the pinned GitHub archive, extracts only the selected skill into a temporary directory, runs `git apply --check` and then `git apply`, and returns the modified archive to chezmoi. Other skills and binary assets are preserved. This requires Git and `uv` with Python 3.11+ available; the filter uses only the Python standard library and does not download an interpreter.

- **Add or edit a customization:** create a patch against the declared upstream rev, using normal context lines. Preview and apply each affected target, for example:

  ```sh
  chezmoi diff ~/.agents/skills/bro/SKILL.md
  chezmoi apply -v ~/.agents/skills/bro/SKILL.md
  chezmoi apply -v ~/.claude/skills/bro/SKILL.md
  ```

  If a patch touches other files, apply the skill directory instead. Patches are source-only files, not installed targets.
- **Remove a customization:** delete its patch, then apply the affected skill targets to restore the pinned upstream contents. If the patch added files, remove those now-obsolete files from the destination as well: archive externals are not exact directories.
- **Update upstream:** `dots skills-update` validates patches against all selected candidate revs before writing or committing any rev. A conflict or download failure leaves all selected pins unchanged. Review the upstream diff, adapt the patch, and retry. `--no-commit` still validates; `skills-check` remains a freshness-only check.
- **Conflicts:** the filter fails rather than using three-way merges, rejected hunks, or unpatched fallback contents. `chezmoi diff`, `apply` and `verify` all use the patched target state. An apply of multiple targets is not a transaction.
- **Checks:** `dots skills-lint` rejects patches with missing or ambiguous skill declarations. `tests/filter_agent_skill.py` exercises real Git and isolated chezmoi apply/diff/verify against a loopback HTTP archive, without external network access; `ci-render` itself still excludes externals.

The included patches make `ponytail-review` and `ponytail-audit` report in Japanese, replace agent-browser's `npx` tool permission with `bunx`, and extend `/bro` with `/bro --file <path>`. Bro already supports pasted text upstream. Agent-browser's dynamically loaded `agent-browser skills get ...` output is outside the downloaded archive, so these patches do not rewrite that runtime content.

Archive paths cannot escape the temporary directory; links and special files inside the selected skill are rejected. Git's automatic line-ending conversion is disabled during patch application, regardless of host settings. On Windows, existing archive permissions are preserved and new files receive mode `0644`; use content patches rather than executable-bit changes there.

## Managing OS-specific files

Edit [`.chezmoiignore.tmpl`](.chezmoiignore.tmpl).

## Git (shared + per-machine)

Global Git is split so portable settings live in the repo and machine-specific values (account, signing paths, `core.editor`, extra sections you add to the template) stay overridable per host:

- Shared: [`dot_gitconfig.tmpl`](dot_gitconfig.tmpl) (includes `~/.config/git/config.machine`, hunk, LFS, optional `safe.directory` from `git_safe_directories` in data).
- Bootstrap: [`private_dot_config/git/create_config.machine.tmpl`](private_dot_config/git/create_config.machine.tmpl) creates `~/.config/git/config.machine` only when the target is absent. Existing local files are preserved. The template defaults target the **kot149** GitHub profile; override the initial values in `~/.config/chezmoi/chezmoi.toml` on work PCs, etc.

Defaults live in [`.chezmoidata/git.toml`](.chezmoidata/git.toml) (**kot149** + GitHub noreply email). If `git_signing_key` / `git_allowed_signers` are left empty, [`create_config.machine.tmpl`](private_dot_config/git/create_config.machine.tmpl) falls back to `$HOME/.ssh/id_ed25519_github_kot149.pub` and `$HOME/.ssh/allowed_signers`. **`~/.config/chezmoi/chezmoi.toml`** `[data]` overrides `.chezmoidata/git.toml`, so a work machine can point at different keys without editing the repo.

Example override for a work machine:

```toml
[data]
git_user_name = "Your Work Name"
git_user_email = "you@company.example"
git_signing_key = "C:/Users/you/.ssh/id_ed25519_work.pub"
git_allowed_signers = "C:/Users/you/.ssh/allowed_signers_work"
git_editor = "code --wait"
git_commit_gpgsign = true
git_safe_directories = [
  '%(prefix)///wsl.localhost/Ubuntu-24.04/home/you/.local/share/chezmoi',
]
```

On a new machine, `chezmoi init` runs [`.chezmoi.toml.tmpl`](.chezmoi.toml.tmpl) and prompts with **kot149-oriented defaults**; answers are written to `~/.config/chezmoi/chezmoi.toml`. To change machine-only Git settings after initial creation, edit local `~/.config/git/config.machine`; changes to the source template affect only the bootstrap content.

## Managing Winget packages

Export:
```sh
chezmoi cd
```
```sh
winget export -o winget.json
```

Import:
```sh
winget import winget.json
```
