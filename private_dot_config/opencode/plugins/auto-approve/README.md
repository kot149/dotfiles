# auto-approve

An LLM gate for opencode v2's auto-approved actions. Our own implementation, written from the documented plugin interfaces; it contains no code from `jdjkelly/opencode-auto-approve` (which is unlicensed and had no release compatible with v2.1 anyway).

| File | Role |
| --- | --- |
| `index.ts` | Server gate |
| `protocol.ts` | RPC contract shared by the server and TUI halves |
| `tui.tsx` | TUI half |

## Behavior

- Every resolved-allow action is judged by an LLM over the pending call plus the human user's own messages. Two-stage review by default: a second pass runs only for calls the first pass wants to block.
- Judge allow → the call runs silently. Block → the agent gets a tool error and must change course.
- Identical call+resource pairs reuse the turn's verdict; a new user message resets the turn.
- Block-count thresholds open a human prompt instead of endless blocking.
- Subagent sessions ask by default.
- A judge that cannot be reached fails closed to a prompt.
- Judge generate calls ride the server's one-shot `/generate` endpoint with the `opencode` service credentials, because the `ctx.generate.text` provider path trips the opencode zen free-lane `FreeUsageLimitError`. `judge` / `judge2` unset means the session default model.
- Decision records are journaled to `~/.local/state/opencode/auto-approve/decisions.jsonl`, so the TUI's panel sees every location's calls. `logFile` mirrors a human-readable log.

## TUI

- A `prompt.footer` badge, and toasts for non-allow verdicts.
- The `/auto-approve` slash command, registered through a global keymap layer: `on|off|status|log|two|judge|judge2|clear`. `judge` / `judge2` without a `provider/model` argument open a searchable model picker fed by the gate's `models` RPC.
- `log` opens the decision log as a session panel.

## Options

Read before every judged call from `~/.config/opencode/auto-approve.json` and the project's `.opencode/auto-approve.json`, so edits and TUI commands take effect immediately.

Keys: `enabled`, `judge`, `judge2`, `twoStage`, `subagents` (`ask`|`classify`), `skipActions`, `escalate` (`afterConsecutive`, `perTurn`), `userMessages`, `timeoutMs`, `hardDeny`, `environment`, `rules`, `logFile`.

The global file is rendered from `private_dot_config/opencode/modify_auto-approve.json`. Managed keys win, but `judge`, `judge2`, `enabled` and `logFile` are plugin-owned (the `/auto-approve` commands write them straight into the file) and survive every apply.
