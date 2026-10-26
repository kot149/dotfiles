## Repository purpose

These are personal dotfiles managed by **chezmoi** (source of truth for files in `$HOME`) and **Nix Home Manager** (declarative package set). On macOS, **nix-darwin** is also used for system-level settings (source: `private_dot_config/nix-darwin/`, applied by `.chezmoiscripts/run_onchange_after_nix-darwin.sh.tmpl`). The repo targets macOS, Linux (including WSL), and Windows from a single source tree.

## How files map to `$HOME`

chezmoi rewrites filenames on apply. Key prefixes used in this repo:

- `dot_foo` → `~/.foo` (e.g. `dot_zshrc` → `~/.zshrc`, `dot_claude/` → `~/.claude/`)
- `private_foo` → `~/foo` with mode `0600`
- `readonly_foo` → read-only on apply
- `executable_foo` → `+x`
- `*.tmpl` → rendered through chezmoi's Go template engine (`.chezmoi.os`, `.chezmoi.arch`, `.chezmoi.username`, etc.); the `.tmpl` suffix is stripped
- `.chezmoiscripts/run_onchange_*` → re-run when their content hash changes (hashes of dependencies are embedded as comments at the top; `run_onchange_after_00_home-manager.sh.tmpl` and `run_onchange_after_nix-darwin.sh.tmpl` hash every file under their source directory through `glob`, so adding or editing any file there re-triggers the switch and no hash list needs editing; the other scripts list their dependencies by hand). Scripts start with `#!/bin/bash` and `set -euo pipefail`; bodies shared by several scripts live in `.chezmoitemplates/scripts/` and are pulled in with `includeTemplate` and a `dict` of per-script values.
- `.chezmoitemplates/` → shared template snippets included via `{{ include "..." }}` (verbatim) or `{{ includeTemplate "..." }}` (rendered)

Per-OS file selection is controlled by `.chezmoiignore.tmpl` (gates `Library/**`, `AppData/**`, `winget.json`, etc. on `.chezmoi.os`).

Files **not** managed by chezmoi (no `dot_`/`private_`/etc. prefix, listed in `.chezmoiignore.tmpl`, or sitting at the repo root as plain docs) live only inside this repository and are never copied to `$HOME`. Notable examples:

- `./AGENTS.md` (this file): repo-level agent guidance, read directly from the repo by tools like Codex CLI / Claude Code. Edits take effect immediately; **do not** run `chezmoi apply` for it (it will say "not managed").
- `./README.md`, `justfile`, `.chezmoiignore.tmpl`, `.chezmoidata/`, `.chezmoiscripts/`, `.chezmoitemplates/`: chezmoi metadata / repo docs, not targets.

To check whether a given file is a chezmoi target, run `chezmoi target-path <source>` (prints the destination) or `chezmoi managed | grep <name>`.

## Applying changes after editing files (MANDATORY for agents)

Editing a managed file in this repo does **not** change anything in `$HOME`; chezmoi only syncs on `apply`. If you (the agent) edit a managed file here, you **must run `chezmoi apply -v <target>` yourself in the same turn**. Do not tell the user to run it; do not end the turn with "now run apply". The edit-then-apply pair is one atomic action. (Unmanaged files like `./AGENTS.md` skip this step; they are read straight from the repo.)

Rules:

- Always pass a target path. **Never** run a bare `chezmoi apply` — it may overwrite unrelated files.
- The target is the **destination path in `$HOME`**, not the source path in the repo. Translate the chezmoi filename prefixes to get it:
  - `dot_zshrc` → `chezmoi apply -v ~/.zshrc`
  - `dot_claude/modify_settings.json` → `chezmoi apply -v ~/.claude/settings.json`
  - `private_dot_config/zellij/config.kdl` → `chezmoi apply -v ~/.config/zellij/config.kdl`
  - `dot_local/bin/executable_zjdev` → `chezmoi apply -v ~/.local/bin/zjdev`
  - `foo.tmpl` → target is `foo` (drop the `.tmpl` suffix)
- If unsure of the target path, run `chezmoi target-path <source-path>` to resolve it before applying.
- If multiple files were edited, run `chezmoi apply -v` once per target path (not a single bare apply).
- After applying, mention any runtime step the user still needs (e.g. restart zellij, reload shell) — but only the parts that genuinely require the user, not the apply itself.

Nix files need an extra switch step: a targeted `chezmoi apply -v <target>` does **not** run the `run_onchange_*` scripts, so after editing Home Manager files (`private_dot_config/home-manager/`, e.g. `common.nix.tmpl`) or nix-darwin files (`private_dot_config/nix-darwin/`), apply the target and then run the corresponding switch yourself in the same turn:

```sh
# Home Manager (after applying ~/.config/home-manager/<file>)
just hm-switch

# nix-darwin (after applying ~/.config/nix-darwin/<file>; needs sudo, may prompt the user)
nh darwin switch ~/.config/nix-darwin -H "$(hostname -s)"
```

The run_onchange scripts fall back to `nix run home-manager/master` / `nix run github:nix-darwin/nix-darwin#darwin-rebuild` when `nh` is not installed yet (first switch on a fresh machine).

herdr config needs a reload: after applying `~/.config/herdr/config.toml`, run the reload yourself in the same turn so the running session picks it up (no restart needed):

```sh
herdr server reload-config
```

## Common commands

Routine maintenance (chezmoi, skill revs, Home Manager, nix-darwin, Nix cleanup, plugin and tool upgrades, global bun / npm / pnpm / uv / cargo / go packages and their duplicates in Nix / apt / winget, tests) is collected in the root `justfile`. The `dots` alias (zsh and PowerShell) runs it from anywhere: `dots` lists the tasks, `dots update` pulls and applies the repo, and `dots update --all` (or `--full`) also runs `update-full`, the full update for the current OS. OS-specific tasks use just's `[macos]` / `[linux]` / `[unix]` / `[windows]` attributes. The `justfile` is not a chezmoi target (it is in `.chezmoiignore.tmpl`).

`just lint` (`scripts/lint.py`) runs shellcheck, ruff, nixfmt and oxlint, rendering the `.tmpl` sources for both macOS and Linux first. `ruff format` and `nixfmt` only report. `just test` runs it.

`just doctor` (`scripts/doctor.py`) reports `.chezmoiignore.tmpl` entries with no source file, a Home Manager / nix-darwin run_onchange script without its hash glob, missing tools, Codex hooks with no trust entry or possibly stale trust, and unmanaged skill directories. `dots update --all` runs it last; `--no-home` skips the checks that read this machine's `$HOME`. A new repo-only root file needs both a `# General` entry in `.chezmoiignore.tmpl` and a name in `REPO_ONLY` in `scripts/doctor.py`.

`just ci-render` applies the source tree into a scratch directory with its own config and state (scripts and externals excluded), then parses the rendered agent configs with `scripts/render_check.py --destination`, which fails on a missing target unless `.chezmoiignore.tmpl` drops it on that OS. `.github/workflows/check.yml` runs it, `just test` and `just doctor --no-home` on Ubuntu, macOS and Windows; a tool a check needs must also be installed there. Locally, `just ci-render --override-data '{"chezmoi":{"os":"linux","kernel":{"osrelease":"generic"}}}'` renders as another OS.

Apply / diff / status (from anywhere):

```sh
chezmoi diff           # preview changes
chezmoi apply -v       # apply to $HOME (runs run_onchange_* scripts)
chezmoi status
chezmoi cd             # cd into this repo
chezmoi execute-template < file.tmpl   # render a template ad-hoc
```

Home Manager (invoked automatically by `.chezmoiscripts/run_onchange_after_00_home-manager.sh.tmpl` on non-Windows):

```sh
just hm-switch
```

The Home Manager flake lives at `private_dot_config/home-manager/` (rendered to `~/.config/home-manager/`). Edit `common.nix.tmpl` to change cross-platform packages; `linux-*.nix`, `darwin.nix`, `wsl.nix` for OS-specific bits. `local.nix` (gitignored, not in repo) is auto-included if present and can set `localDeny.packages = [ ... ]` to remove packages from the common set.

nix-darwin (macOS system-level settings; invoked automatically by `.chezmoiscripts/run_onchange_after_nix-darwin.sh.tmpl`):

```sh
nh darwin switch ~/.config/nix-darwin -H "$(hostname -s)"
```

The nix-darwin flake lives at `private_dot_config/nix-darwin/` (rendered to `~/.config/nix-darwin/`). Edit `darwin-configuration.nix.tmpl` for macOS system settings (`system.defaults.*`, `system.startup.*`, etc.) and `custom-user-preferences.nix` for Rectangle, DockDoor and AltTab preferences. **Home Manager** owns packages and user-level dotfile programs; **nix-darwin** owns macOS system settings and these app preferences.

Windows package list lives in `winget.json`: `winget export -o winget.json` / `winget import winget.json`.

## Configuration layering (important)

1. `.chezmoidata/*.toml` — repo-wide defaults, split by topic (`git.toml` for the git identity, `agent-permissions.toml` for the agent allow/deny lists, `agent-skills.toml` for the third-party skill entries, `agent-hooks.toml` for the agent hook registrations, `nix-binary-caches.toml`)
2. `~/.config/chezmoi/chezmoi.toml` — per-machine overrides (created by `.chezmoi.toml.tmpl` on `chezmoi init`); `[data]` here wins
3. `private_dot_config/git/create_config.machine.tmpl` → `~/.config/git/config.machine`, created only when absent and included by the shared `dot_gitconfig.tmpl` for per-host git settings (signing key paths, work email, `safe.directory`, etc.)

When adding new tunable values, prefer threading them through `.chezmoidata/` + chezmoi template prompts rather than hardcoding.

## Agent permission lists

`.chezmoidata/agent-permissions.toml` defines `agent_plain_allow`, `agent_shell_allow`, `agent_shell_allow_no_rtk`, `agent_shell_allow_js_scripts`, `agent_shell_allow_js_bins`, `agent_shell_allow_write` and `agent_shell_deny` arrays. `agent_shell_allow_js_scripts` holds package.json / deno.json script names, expanded for every JS package manager (`npm run X`, `pnpm X`, `yarn X`, `bun X`, `deno task X`, …); `agent_shell_allow_js_bins` holds `node_modules/.bin` executables, expanded to `npx X`, `bunx X`, `pnpm exec X`, `pnpm dlx X`, `yarn dlx X`, … plus the bare `X`. `.chezmoitemplates/agents/shell-permissions.tmpl` expands the shell lists once (JS script and bin prefixes, `/bin` and `/usr/bin` forms, `--help` / `--version`, `rtk`, `rtk proxy`, bare and `corepack` variants) into plain patterns, and `.chezmoitemplates/claude/settings.json.tmpl`, `.chezmoitemplates/opencode/opencode.json.tmpl`, `.chezmoitemplates/antigravity/settings.json.tmpl` and `dot_codex/rules/default.rules.tmpl` only format them. Codex `prefix_rule` patterns match leading argv tokens exactly, so the Codex template reads every `*` as empty to get a prefix that matches only commands the pattern matches too, and skips patterns with no such prefix (no trailing `*`, or a lone `*` before the last token), so Codex prompts for those, including the exact allow entries. A deny entry other than `<literal tokens> *` blocks more than its prefix rule, so Codex also skips every allow prefix that overlaps the deny's literal head (`rg`, `find`, `git diff`, `chezmoi diff`, `nix eval`, …) and prompts for those commands. Add new always-allowed read-only commands to `agent_shell_allow`; destructive patterns belong in `agent_shell_deny`. Entries in `agent_shell_allow` are emitted both bare and with an auto-generated `rtk <cmd>` variant; put commands that should be allowed **without** the `rtk` wrapper (e.g. `rtk` itself) in `agent_shell_allow_no_rtk`, which emits only the bare form.

A rule only stops a command when its own pattern matches, so a deny entry never narrows an allow entry. What goes into `agent_shell_allow`:

- Read-only **including every option it accepts**: an option that names a program to run (`git fetch --upload-pack`, `rg --pre`) or a file to write (`git diff --output`, `yq -i`) disqualifies the entry unless `agent_shell_deny` covers that option. Where a deny pattern would also hard-block ordinary commands (`curl -I … -o`, `git branch -v -D`, `uniq in out` and `xxd in out`, which write their second argument), list the exact read-only forms instead or leave the command out. The same applies to bundled short flags, which a trailing `*` always admits (`fd -HX rm`, `git grep -nO<cmd>`, `yq -yi`): that is why `fd`, `git grep` and `yq` are not allowed.
- No leading `*`. The shared template generates `<tool> --help` and `<tool> --version` for the first word of every entry instead. `-h` and `-V` prompt, as do `--help` / `--version` in Codex, where an exact command cannot be expressed.
- No mid-pattern `*`.
- No trailing `*` after a subcommand that accepts further subcommands, task names or shell statements (`gradle tasks`, `mvn …`, `adb shell …`, `pwsh -Command …`, `tmux list-panes`, where a lone `;` argument starts a second tmux command, `rtk pnpm`, which passes unknown subcommands through). List the exact forms instead.
- A tool whose dry run still evaluates project code (`make -n`, `just --evaluate`, `bundle list`, `gradle`) is accepted, the same way `cargo test` is. So are formatters and fixers that rewrite project files (`cargo fmt`, `ruff format`, `ruff check --fix`, `oxfmt`, the `format` script), since they only rewrite files inside the project.
- The PowerShell launcher forms (`pwsh -Command …`, `powershell -Command …`) are not allowed, since a quoted `;` runs a second statement; Claude Code on Windows prompts for them. Only the bare cmdlets are listed, for opencode's per-stage matching. Cmdlets that take a script block (`ForEach-Object`, `Where-Object`, `Select-Object`, `Sort-Object`, `Group-Object`, `Compare-Object`, `Format-List`, `Format-Table`, `Format-Wide`, `Format-Custom`) are listed without arguments or not at all, since the block runs arbitrary code.
- Every new wildcard entry gets a case in `tests/permissions.py`, which renders the Claude rules and checks commands against them. It also checks that no Codex rule blocks or allows more than the Claude rules.

Deny entries are anchored at the command name (no leading `*`). A `*` also matches spaces, so a pattern built around a single flag letter (`rm -*r* ~*`) catches ordinary paths such as `rm -f error.log .DS_Store`; spell out the flag forms instead (`rm *-rf ~*`, `sort -uo*`), and cover long-option abbreviations by prefix where the tool accepts them (getopt_long and git: `journalctl --rot`, `git fetch --upl=`). Each entry gets a `denied` case and, where it could catch an ordinary command, a `not_denied` case in `tests/permissions.py`. Known gaps: short-flag bundles other than the listed ones (`rm -rfv ~`, `chezmoi diff -vS <dir>`, `chezmoi status -vc <file>`), and `rm -rf *`, since a pattern cannot match a literal `*`. chezmoi's global flags (`--source`, `--config`, `--output`, `--pager` and their short forms) are denied only after the subcommand (`chezmoi * --source*`), where they would ride on an allowed entry such as `chezmoi diff *`; `chezmoi --source <dir> execute-template …` still prompts. `tree *-o *` is denied for GNU tree, where `-o` writes a file, and so also blocks eza's harmless `-o` (octal permissions).
Do not add `git -C * <subcommand>` style entries: a mid-pattern `*` also matches options such as `-c` or `--exec-path` inserted after the path. Claude Code instead runs `dot_claude/hooks/executable_rewrite-git-c.sh` (registered in place of `rtk hook claude`, which it calls itself), which rewrites `git -C <path> <args>` to `(cd <path> && git <args>)` so the plain `git <args>` rules apply. Codex and opencode prompt for `git -C`.

rtk rewrites shell commands to `rtk <cmd>` in all three agents: Claude Code through the hook above, Codex through its `rtk hook claude` entry in `.chezmoidata/agent-hooks.toml` (Codex accepts the same `updatedInput` output), and opencode through the plugin `private_dot_config/opencode/plugins/rtk.ts`, which calls `rtk rewrite`.

`agent_shell_allow_write` holds commands with side effects (`git add`, `git commit`, `git stash`, `herdr`) and only `.chezmoitemplates/opencode/opencode.json.tmpl` uses its expansion (`allowWrite` in the shared template). Claude Code and Codex keep prompting for those. `herdr` and `git stash` are listed per subcommand, not as `herdr *` / `git stash *`: `herdr pane run` and `herdr --machine` run arbitrary commands, and `git stash drop` / `clear` discard work.

opencode's matcher differs from Claude Code's in ways the template depends on:

- A compound command is parsed into its sub-commands (pipeline stages, `&&` / `;` segments) and **every** one must match an allow rule, or the whole call prompts. A bare `echo "---"` between two allowed commands is enough to trigger a prompt, which is why output cmdlets are in `agent_shell_allow`.
- Rules are matched in **file order, last match wins**, so since v2 the rules are one array with the broad allows first and the shared denies last, and `toJson` preserves that array order through the modify template's fromJson/toPrettyJson round trip. A pattern ending in ` *` also matches the command without arguments (`"git log *"` already matches bare `git log`), so no bare variants are emitted.
- `webfetch` and `websearch` accept only a plain `"allow"` / `"ask"` / `"deny"`, not per-pattern objects, so `agent_plain_allow`'s per-domain `WebFetch(domain:…)` entries have no opencode equivalent.
- Since v2, opencode resolves unmatched rules to `allow`, and `.chezmoitemplates/opencode/opencode.json.tmpl` does not consume the shared allow lists at all: `shell` / `edit` / `external_directory` allow everything, and the auto-approve plugin (see below) judges every resolved-allow call, so only the absolute boundaries stay static: the shared deny list (emitted last, so it always overrides) plus the read rules for `.env*` / `*/.ssh/*` — the judge skips `read`, `glob` and `grep`. New plugin registrations must be declared in the `plugins` array; a bare `opencode plugin add` run would be reverted by the next apply.

## Agent hooks

Every hook registration is one `[[agent_hooks]]` entry in `.chezmoidata/agent-hooks.toml`: the script `file`, its `runner` (`bash`, `uv-script`, `bun`, or `command` for a verbatim command such as `rtk hook claude`), optional `args`, and a `claude` / `codex` table per agent that registers it, holding the event, the optional matcher and any extra handler keys (`timeout`, `statusMessage`, `asyncRewake`). An `opencode = { tools = [...] }` table also runs a PreToolUse guard in opencode (see below). `.chezmoitemplates/agents/hooks.tmpl` turns the entries into each agent's `hooks` object, grouping them by event and matcher in entry order, so both registrations are rendered from the one list. `just hooks-lint` (`scripts/check_agent_hooks.py`, also run by `just test`) checks that every entry's script exists for each agent, that a hook registered for both agents is a one-line include of its body, and that every file in `dot_claude/hooks/` and `dot_codex/hooks/` is registered, except `python-runner.sh`.

A hook registered for both agents has its body in `.chezmoitemplates/agents/` and a one-line `{{ include ... }}` wrapper in `dot_claude/hooks/` and `dot_codex/hooks/`, so there is a single implementation per script. A Claude Code only hook (`rewrite-git-c.sh`, `remind-stop-background.sh`, `check-japanese-reply.sh`, `keep-cache-warm.sh`) is a plain file in `dot_claude/hooks/`. Two support files are shared the same way but not registered:

- `textlint-rules/textlint-rule-ja-ai-phrasing.js` (the textlint rule `check-writing-style.js` imports) → `~/.claude/hooks/textlint-rules/` and `~/.codex/hooks/textlint-rules/`
- `python-runner.sh` (resolves the interpreter for the inline Python parsers: `uv run --script` with `UV_PYTHON_DOWNLOADS=never`, then `python3`, then `python`; with none, it exits 0 so the hook passes the command through; `source`d by the bash hooks) → `~/.claude/hooks/` and `~/.codex/hooks/`

Both registrations are rendered from `.chezmoidata/agent-hooks.toml` by `.chezmoitemplates/agents/hooks.tmpl`, which `.chezmoitemplates/claude/settings.json.tmpl` and `.chezmoitemplates/codex/hooks.json.tmpl` call. Agent-specific details:

- Claude Code: events PreToolUse, PostToolUse, Stop and UserPromptSubmit. PreToolUse matchers name the tools `Bash`, `Write`, `Edit`, `mcp__*`.
- Codex CLI: merged into `~/.codex/hooks.json` by `dot_codex/modify_hooks.json`. A handler takes `command` (used on macOS/Linux) and `commandWindows` (used on Windows); they run the same script and differ only in quoting. On Windows the bash hooks run through Git Bash (`.git_bash_path`, default `C:/Program Files/Git/bin/bash.exe` installed by `Git.Git` in `winget.json`, overridable per machine in `~/.config/chezmoi/chezmoi.toml`); the bun and uv hooks call `bun` / `uv` directly. `matcher` is a regex against the tool name; Codex's shell tool is `Bash` or `Shell` and the matchers name both, but its file edits arrive as a single `apply_patch` tool whose `tool_input.command` is the patch document. `check-writing-style.js` parses that patch format, and `textlint-rules/` is materialized next to each copy by its own include wrapper.
- opencode: Home Manager installs v2 from `llmAgents.opencode2` under the `opencode` command. The permission template emits native v2 permissions (see above); local plugins use the v2 API, not the incompatible v1 hook object. A single file in `plugins/` is a server plugin; a TUI plugin is a subdirectory holding a `tui` entry (`plugins/ctrl-c-interrupt/tui.ts`, which makes ctrl+c interrupt a running session and exit otherwise, together with the keybinds in `modify_cli.json`). The plugin `private_dot_config/opencode/plugins/guards.ts.tmpl` (→ `~/.config/opencode/plugins/guards.ts`, not installed on Windows) bakes in the entries that have an `opencode` table and registers `ctx.tool.hook("execute.before", ...)`. It runs their installed copies from `~/.claude/hooks/` (falling back to `~/.codex/hooks/`) in parallel with the same stdin JSON Claude Code sends: v2's `shell`, `write`, `edit` and `patch` arguments become `Bash`, `Write`, `Edit` and `apply_patch` tool input. The bridge maps `shell` / `patch` to the shared hook list's `bash` / `apply_patch` keys and v2's `path` to `file_path`. An `rtk` / `rtk proxy` prefix is stripped from the command first, because `rtk.ts` may already have rewritten it and some guards do not look past it. On `deny` or `ask` this bridge throws, failing the tool call with the reason rather than opening a permission prompt. `check-force-push.sh` and `check-github-api-write.sh` have no `opencode` table: opencode no longer prompts before `git push` and `gh api` / `gh pr` / `gh issue` writes — the auto-approve plugin judges them — and a throw would convert the guard's supported ask decision into a tool error with no approve option, so these ask-based guards stay with the agents whose ask is a real prompt. A hook that cannot run or prints no JSON lets the call through. `just hooks-lint` checks the `opencode` tables and `just lint` renders the plugin for oxlint. The auto-approve plugin is our own implementation in `private_dot_config/opencode/plugins/auto-approve/` (`index.ts` server gate, `protocol.ts` shared RPC contract, `tui.tsx` TUI half), written from the documented plugin interfaces — it contains no code from `jdjkelly/opencode-auto-approve` (which is unlicensed and had no release compatible with v2.1 anyway). Behavior: every resolved-allow action is judged by an LLM (two-stage review by default; a second pass only for calls the first pass wants to block), over the pending call plus the human user's own messages. Judge output allow → the call runs silently; block → the agent gets a tool error and must change course; identical call+resource pairs reuse the turn's verdict, and a new user message resets the turn; block-count thresholds open a human prompt instead of endless blocking; subagent sessions ask by default; a judge that cannot be reached fails closed to a prompt. Judge generate calls ride the server's one-shot `/generate` endpoint with the `opencode` service credentials (the `ctx.generate.text` provider path trips the opencode zen free-lane `FreeUsageLimitError`); `judge`/`judge2` unset means the session default model. Decision records are journaled to `~/.local/state/opencode/auto-approve/decisions.jsonl` so the TUI's panel sees every location's calls, and options may carry `logFile` to mirror a human-readable log. The TUI half renders a `prompt.footer` badge, registers the `/auto-approve` slash command (alias `/aa`; `on|off|status|log|two|judge|judge2|clear`) via a global keymap layer, opens its decision log as a session panel, and toasts non-allow verdicts. Registered as `./plugins/auto-approve`. Options keys: `enabled`, `judge`, `judge2`, `twoStage`, `subagents` (`ask`|`classify`), `skipActions`, `escalate` (`afterConsecutive`, `perTurn`), `userMessages`, `timeoutMs`, `hardDeny`, `environment`, `rules`, `logFile`. The auto-approve plugin's config is `private_dot_config/opencode/modify_auto-approve.json` (→ `~/.config/opencode/auto-approve.json`): managed keys win, but `judge`, `judge2`, `enabled` and `logFile` are plugin-owned (the `/auto-approve` commands write them straight into the file) and survive every apply.

Other tools (e.g. Orca IDE) also write hooks and settings into these files, so the agent config files are `modify_` templates that all render through `.chezmoitemplates/agents/merge-config.tmpl`: `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.codex/config.toml`, `~/.config/opencode/cli.json`, `~/.gemini/antigravity-cli/settings.json`, `~/.omp/agent/config.yml` (oh-my-pi; `setupVersion` is omp-owned and deliberately unmanaged, so omp's own rewrites survive every apply). Objects are merged at any depth (managed values win, arrays are replaced; yaml uses chezmoi's `fromYaml`/`toYaml`, which error loudly and sort keys, so applies are byte-stable). Hooks are merged per entry instead: every managed `command` gets a trailing `# chezmoi-managed` comment (`commandWindows` does not, since cmd.exe would pass it to the hook as arguments), and on apply the existing hooks carrying it are dropped and the managed ones re-added, so hooks from other tools are kept and hooks deleted from a template disappear. Do not write that marker by hand. A template pulled in with `includeTemplate` cannot call other shared templates, which is why the merge recurses through `merge-config.tmpl` itself.

`tests/` holds tests for the hooks, the permission lists, the config merge template and the skill rev updater, the parts that carry enough logic to regress. They are plain Bun scripts (not `bun test` files, because `bun test` cannot resolve the versioned import specifiers the hooks pin their dependencies with), a Bash script that pipes Codex `apply_patch` payloads into `check-writing-style.js`, and plain PEP 723 Python scripts that run the Bash hooks and `chezmoi execute-template` as subprocesses or import the script under test:

```sh
bun run tests/textlint-rule-ja-ai-phrasing.js   # the rule behind check-writing-style.js
bash tests/writing-style.sh   # apply_patch parsing in check-writing-style.js
bun run tests/opencode-guards.js   # opencode tool mapping and rtk prefix handling in guards.ts
uv run --no-python-downloads --script tests/hooks.py   # check-force-push.sh, check-github-api-write.sh, rewrite-git-c.sh and check-japanese-reply.sh
uv run --no-python-downloads --script tests/permissions.py   # rendered Claude allow / deny rules, Codex prefix rules and opencode gh api graphql rules
uv run --no-python-downloads --script tests/merge_config.py   # merge-config.tmpl fixtures
uv run --no-python-downloads --script tests/update_agent_skills.py   # rev rewrite and grouping in update_agent_skills.py
```

`merge-config.tmpl` fixtures live under `tests/fixtures/merge-config/<case>/`: each case is `managed` + `current` → `expected` (all `.json`, `.toml` or `.yaml`; yaml is parsed through chezmoi's own `fromYaml`, so no PyYAML dependency), with an empty `no-hooks` file for cases that do not pass `"hooks" true`. Each case is also re-rendered with `expected` as `current` and must stay unchanged.

Two Codex-specific details:

- **Blocking** requires JSON on stdout with `hookSpecificOutput.permissionDecision = "deny"` plus a non-empty `permissionDecisionReason`, and exit status 0. A non-zero exit only marks the hook as failed; it does not stop the tool call. Claude Code accepts the same JSON, which is why the shared scripts use it instead of `exit 2`.
- **Trust**: Codex will not run a user-level hook until it is trusted. The TUI prompts "Hooks need review" on the next launch and records the decision in `~/.codex/config.toml` as `[hooks.state."<hooks.json path>:<event>:<group>:<index>"]` with `trusted_hash`. The hash covers the handler as resolved for the current OS (`commandWindows` on Windows, `command` elsewhere), so **an edit to a handler requires re-trusting on the OSes where its resolved form changed** (a `codex exec` run silently skips untrusted hooks). This state is per-machine and is not managed by chezmoi.

## Agent skills

Skills live in two stores. `~/.agents/skills` is the shared store: Codex CLI reads it natively (alongside its own deprecated `~/.codex/skills`), as do opencode, Cursor, Gemini CLI and Amp. `~/.claude/skills` exists because Claude Code is the one agent with no `.agents/` awareness and no setting for extra skill roots, so anything Claude Code should see has to be materialized there as well. Nothing in this repo writes to `~/.codex/skills`.

Both stores are generated, never hand-synced and never symlinked together: a skill is declared or written **once** and the same definition materializes into every store that needs it. For self-authored skills the single source is the body under `.chezmoitemplates/agents/skills/`; for third-party skills it is the `[[agent_skills]]` entry, whose `agents` list names the target stores. `add-slash-command` (case 1 below) is the one exception: it is written twice, by hand.

Skills come from three places, and which one a skill belongs to decides where you edit it:

1. **Self-authored, single agent** — checked in under `dot_claude/skills/<name>/SKILL.md` (Claude Code) or `dot_agents/skills/<name>/SKILL.md` (shared store). Skills in the shared store carry `agents/openai.yaml`, which supplies Codex's TUI interface metadata and is ignored by agents that do not know it; `just skills-lint` reports a shared-store skill that lacks it. Scripts shipped with a skill need the `executable_` prefix.

   One skill sits here: `add-slash-command`, because the Claude Code copy (`dot_claude/commands/add-slash-command.md`) writes a slash-command file while the shared-store copy writes a Codex skill. The two produce different artifacts and cannot share a body, so both are maintained by hand.
2. **Self-authored, shared between agents** — body lives in `.chezmoitemplates/agents/skills/<name>.md` and each agent gets a one-line `{{ includeTemplate "agents/skills/<name>.md" . }}` wrapper named `SKILL.md.tmpl`, same pattern as the shared hooks. Scripts shipped with a shared skill follow the same pattern: body in `.chezmoitemplates/agents/<script>`, and each agent gets an `executable_<script>.tmpl` wrapper (e.g. `keychain-cred.sh`). This is the default for a new self-authored skill.

   A procedure needed by more than one skill body lives under `.chezmoitemplates/agents/skills/_shared/` and is pulled in by the bodies with `{{ includeTemplate "agents/skills/_shared/<name>.md" . }}`. There are three: `git-base.md` (base-branch / merge-base determination, used by `autosquash`, `fixup`, `reorganize-commits`, `resolve-conflict`), `user-choice.md` (the selection-prompt mapping, used by `autosquash`, `dedup`, `deep-review`, `fixup`, `issue-recon`, `loop-until-settled`, `pending-review-comments`, `pr-brief`, `release-notes`, `reorganize-commits`, `reply-pr-comments`, `resolve-conflict`), and `subagents.md` (the subagent mapping and its invariants, used by the skills listed under **Subagents** below). Every skill wrapper uses `includeTemplate`, with no exceptions. `include` inserts a file verbatim without rendering it, so a body that later grows a nested `_shared/` include would emit that directive as literal text into the installed `SKILL.md`. Using one spelling everywhere removes that failure mode. Snippets are numbered as sub-steps (`#### 2-1.` …), so each body supplies its own `### 2. ...` heading and intro before the include.

   A shared body must not hardcode one agent's tool names or call syntax. The repo settles this by naming the capability and mapping it onto each agent once, near the top of the body:

   - **User choice** — the body pulls in `_shared/user-choice.md` under an `## Asking the user to choose` heading, and the steps then say only "selection prompt" or "ask the user to choose". Never call the tool by name inline. `commit` is the exception: its stronger three-step wording is deliberate and stays in the body.
   - **Subagents** — the body pulls in `_shared/subagents.md`, which holds the Claude Code / Codex CLI mapping and the invariants that must hold either way (fresh context, read-only roles, no conversation context, sequential fallback). `deep-review`, `meta-review`, `pr-brief`, `issue-recon` and `loop-until-settled` use it.
   - **Arguments** — the body refers to "the request" or "the user's request", never `$ARGUMENTS`. That token is a Claude Code slash-command convention; every other store reads `SKILL.md` as plain Markdown and shows it unsubstituted. Claude Code's `argument-hint` frontmatter is harmless elsewhere and stays.
   - **MCP tools** — refer to the server and the kind of operation ("Atlassian MCP のissue取得ツール"), not the tool id, since names differ per agent and some agents load tool schemas lazily.
   - **File and search tools** — say "read the file" / "search the repository", not `Read`/`Grep`/`Glob`/`Edit`.
   - **Paths into the skill's own directory** — write them relative to the skill root of whichever store the copy lives in (`~/.claude/skills` vs `~/.agents/skills`), never hardcode one.
3. **Third-party** — declared in `.chezmoidata/agent-skills.toml` as `[[agent_skills]]` and materialized by `.chezmoiexternal.toml.tmpl` as `type = "archive"` externals pulled from a pinned GitHub tarball. This is the cross-platform path: it works on Windows as-is (no symlinks, no Nix), unlike Home Manager, which is non-Windows only.

Adding a third-party skill:

```toml
[[agent_skills]]
repo = "owner/name"
rev = "<commit SHA>"      # gh api repos/owner/name/commits/HEAD --jq .sha
prefix = "skills"         # directory inside the repo holding the skills
names = ["skill-name"]    # one entry per skill dir under prefix
agents = ["claude", "agents"]   # one entry per target store; "claude" ->
                                # ~/.claude/skills, "agents" -> ~/.agents/skills
```

For a repo that keeps `SKILL.md` directly under `prefix` (or at the repo root, with `prefix = ""`) instead of in a per-skill subdirectory, add `flat = true`; `names` then holds the single target directory name.

Then `chezmoi apply -v ~/.claude/skills` (and/or `~/.agents/skills`). The template derives `include` and `stripComponents` from `prefix`, so each skill lands with `SKILL.md` at the root of its target directory. Updating a skill means bumping `rev`; `refreshPeriod = "168h"` only controls re-download of the pinned tarball, never which commit is used. `dots skills-update` (`scripts/update_agent_skills.py`, then `chezmoi apply` of both stores) finds entries whose skill directories changed upstream, shows the changed files (`d` prints the diff), and bumps `rev` for the ones you accept, committing the bump as one `chore(agents): bump ... skill revs` commit that touches only `agent-skills.toml` (`--check` only reports, `--yes` accepts all, `--no-commit` skips the commit; the commit is also skipped when that file already had uncommitted edits). Entries that share a `repo` are offered and bumped as one, so a repository split across several `prefix` values stays at one rev. The exception is an entry whose skill directory no longer exists at upstream HEAD: it is reported as `MISSING` and keeps its rev while the rest of the repo is bumped, and `just skills-lint` reports the repo as pinned at several revs until the entry is removed from `agent-skills.toml`.

`dots skills-update` covers third-party `rev` freshness only. `just skills-lint` (`scripts/check_agent_skills.py`, also run by `just test`) checks the rest: wrapper shape and target, store parity, orphan templates, `name` against the directory name, `agents/openai.yaml` presence, and the `agents` values and `rev` shape in `[[agent_skills]]`. `just render-check` (`scripts/render_check.py`) renders the agent config targets with `chezmoi cat` and checks that the output parses as JSON / TOML / Nix; it runs inside `just test`.

Two things not managed here:

- **Claude Code plugins** supply their own skills. The enabled `cloudflare@cloudflare` marketplace covers the whole `cloudflare/skills` set for Claude, so those are the one exception to listing both stores: they are declared for `agents = ["agents"]` only, which keeps them from showing up twice for Claude Code (once as `cloudflare:<name>` from the plugin, once as `<name>` from the store). Codex has its own plugin system (`codex plugin add/list`, `codex plugin marketplace`) but it does not consume Claude Code marketplaces, so Codex gets those skills through `[[agent_skills]]` instead.
- An OS-specific skill is gated in `.chezmoiignore.tmpl`, not just described as such in its body: `keychain-credentials` reads macOS Keychain items through the `security` CLI, so it installs on macOS only. A path listed in `.chezmoiignore.tmpl` cannot also be cleaned up through `.chezmoiremove`: ignoring it drops it from the target state, so chezmoi neither creates nor removes it. A copy a machine already has from before the gate has to be deleted by hand.
- Skill directories in either store that this repo does not define are reported by `just skills-drift` (`scripts/check_agent_skills.py --home`), which scans `$HOME`; `just test` does not run it. `synced` is allowed in both stores by the script (`UNMANAGED_OK`), since it is Claude Code's own first-party skill set, which it installs and updates itself. Machine-local skills that are not checked in are listed in `~/.config/chezmoi/agent-skills-unmanaged.txt` (one name per line, `#` comments allowed; not managed by chezmoi).
- The **`skills` CLI** (`npx skills add`, vercel-labs) installs into `~/.agents/skills` too, tracked in a per-machine `~/.agents/.skill-lock.json`, and symlinks the non-`.agents` agent directories (Claude Code) at it. Use it to *discover* skills, then transcribe the pick into `[[agent_skills]]`. Do not leave a skill installed that way: the copy is per-machine, invisible to `chezmoi status`, pinned by a separate lock file, and it writes to the same directory names this repo manages.

## User-level agent instructions

Per-agent global instruction files live under each agent's config directory and are distinct from this repo-level `AGENTS.md`:

- `dot_claude/CLAUDE.md.tmpl` → `~/.claude/CLAUDE.md` (Claude Code, applies to *all* projects)
- `dot_codex/AGENTS.md.tmpl` → `~/.codex/AGENTS.md` (Codex CLI, applies to *all* projects)

Both start with `{{ include ".chezmoitemplates/agents/common.md" }}`, and the Claude one adds a "Claude Code specific" section. Put shared content in `.chezmoitemplates/agents/common.md` and edit the `.tmpl` wrappers only for agent-specific additions. These are chezmoi targets: after editing, run `chezmoi apply -v ~/.claude/CLAUDE.md` / `chezmoi apply -v ~/.codex/AGENTS.md`. Edit this file (`AGENTS.md`) for repo-specific guidance.
