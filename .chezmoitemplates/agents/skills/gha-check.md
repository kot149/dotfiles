---
name: gha-check
description: Check GitHub Actions workflows and action definitions with actionlint, zizmor and pinact, then report the findings. Use when the user asks to lint, audit or check GitHub Actions workflows, to verify that actions are pinned to commit SHAs, or mentions actionlint / zizmor / pinact, 「GitHub Actionsを検査して」「ワークフローをチェックして」「actionをpinできてるか確認して」, or any similar phrasing in English or Japanese.
---

# GitHub Actions Check

Run three tools against the repository's GitHub Actions files and report what they find. This is a check: do not edit files unless the user asked for fixes.

| Tool | What it checks |
| --- | --- |
| actionlint | Workflow syntax, expressions, `runs-on` labels, shellcheck on `run:` scripts |
| zizmor | Security: template injection, excessive `permissions`, credential persistence, dangerous triggers, unpinned uses |
| pinact | Every `uses:` pinned to a full commit SHA, with a version comment that matches it |

## 1. Collect the targets

- If the request names files or directories, check only those.
- Otherwise use `.github/workflows/*.y{a,}ml` plus any `action.yml` / `action.yaml` in the repository (composite and local actions).
- If there are none, say so and stop.

## 2. Prepare

- Check that `actionlint`, `zizmor` and `pinact` are on `PATH`. For a missing one, try `nix run nixpkgs#<tool> -- <args>`, and for zizmor also `uvx zizmor <args>`; if none of these works, skip that tool and report it as not run. Never install with a system package manager.
- zizmor's online audits and pinact need GitHub API access. If `GH_TOKEN` / `GITHUB_TOKEN` are unset and `gh auth token` succeeds, pass that token through the environment of these commands only (`GITHUB_TOKEN="$(gh auth token)" pinact ...`). Never print the token. Without a token, run zizmor with `--no-online-audits` and pinact with `--no-api`, and say so in the report.
- Respect the repository's own configuration (`.github/actionlint.yaml`, `zizmor.yml` / `.github/zizmor.yml`, `.pinact.yaml` / `.github/pinact.yaml`). If CI or a task runner (`justfile`, `Makefile`, `package.json`, `.pre-commit-config.yaml`) already invokes one of these tools, use the same flags.

## 3. Run

Run the three independently; one failing must not stop the others. Each exits non-zero when it has findings, so read the output rather than treating the exit code as a crash.

```sh
actionlint <workflow files>
zizmor --no-progress --format plain <targets>
pinact run --check --verify-comment <workflow and action files>
```

- actionlint reads only workflow files; pass it the workflows, not `action.yml`.
- zizmor accepts directories, so `zizmor .` works when checking the whole repository.
- With `--no-api`, pinact checks only that each ref is a 40-character SHA; drop `--verify-comment` in that case.

## 4. Report

Reply in Japanese. Group findings by file, and for each give the line, the tool, the rule (actionlint check name, zizmor audit id and severity, or pinact's message) and a one-line explanation of the risk or error. Merge duplicates where two tools flag the same `uses:` line (zizmor `unpinned-uses` and pinact). End with a per-tool line: number of findings, or "問題なし", or why it was not run.

Do not dismiss a finding on your own judgment. If one looks like a false positive, say why, and leave the decision to the user.

## 5. Fixes, only when asked

- pinact: `pinact run <files>` pins tags to SHAs with a version comment.
- zizmor: `zizmor --fix=safe <targets>` applies the fixes zizmor marks as safe. Apply `unsafe` fixes only when the user asks for them.
- actionlint findings and the remaining zizmor findings: edit the workflow by hand.

After fixing, run step 3 again and report what is left.
