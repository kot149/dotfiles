#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Focus the next or previous Herdr Agent in a configured semantic state."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path

SUPPORTED_STATES = frozenset({"idle", "working", "blocked", "done", "unknown"})
DISPLAY_ORDER = "display"
WAITING_ORDER = "waiting"
DEFAULT_STATES = ("blocked",)
NO_MATCH_MESSAGE = "No matching Agents"


class NextAgentError(Exception):
    """A recoverable failure that should be reported on stderr."""


def load_config(config_dir: str) -> tuple[tuple[str, ...], str]:
    if not config_dir:
        return DEFAULT_STATES, DISPLAY_ORDER

    path = Path(config_dir) / "config.toml"
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return DEFAULT_STATES, DISPLAY_ORDER
    except (OSError, tomllib.TOMLDecodeError) as err:
        raise NextAgentError(f"read Next Agent configuration {path}: {err}") from err

    unknown = set(raw) - {"states", "order"}
    if unknown:
        raise NextAgentError(f"invalid configuration: unknown field {', '.join(sorted(unknown))}")

    order = raw.get("order", DISPLAY_ORDER)
    if order not in (DISPLAY_ORDER, WAITING_ORDER):
        raise NextAgentError('invalid configuration: order must be "display" or "waiting"')

    states = tuple(raw.get("states", DEFAULT_STATES))
    if not states:
        raise NextAgentError("invalid configuration: states must contain at least one Agent state")
    if len(set(states)) != len(states):
        raise NextAgentError("invalid configuration: duplicate state")
    for state in states:
        if state not in SUPPORTED_STATES:
            raise NextAgentError(f"invalid configuration: unsupported state {state}")
    return states, order


def run_herdr(binary: str, *args: str) -> str:
    argv = (binary, *args)
    try:
        done = subprocess.run(argv, capture_output=True, text=True, check=False)
    except OSError as err:
        raise NextAgentError(f"{' '.join(argv)} failed: {err}") from err
    if done.returncode != 0:
        detail = done.stderr.strip() or f"exit status {done.returncode}"
        raise NextAgentError(f"{' '.join(argv)} failed: {detail}")
    return done.stdout


def list_agents(binary: str) -> list[dict]:
    stdout = run_herdr(binary, "agent", "list")
    try:
        agents = json.loads(stdout)["result"]["agents"]
    except (json.JSONDecodeError, KeyError, TypeError) as err:
        raise NextAgentError("herdr agent list returned an invalid response") from err
    if not isinstance(agents, list):
        raise NextAgentError("herdr agent list returned an invalid response")
    return agents


def select_agent(
    agents: list[dict], states: tuple[str, ...], order: str, step: int
) -> dict | None:
    """Pick the neighboring matching Agent, wrapping at either end."""
    if order == WAITING_ORDER:
        candidates = sorted(
            (a for a in agents if a.get("agent_status") in states),
            key=lambda a: a.get("state_change_seq", 0),
        )
        if not candidates:
            return None
        current = focused_index(candidates)
        if current < 0 and step < 0:
            current = 0
        return candidates[(current + step) % len(candidates)]

    # Display order walks every Agent so the focused position anchors the search
    # even when the focused Agent itself does not match `states`.
    current = focused_index(agents)
    if current < 0 and step < 0:
        current = 0
    for offset in range(1, len(agents) + 1):
        candidate = agents[(current + step * offset) % len(agents)]
        if candidate.get("agent_status") in states:
            return candidate
    return None


def focused_index(agents: list[dict]) -> int:
    return next((i for i, agent in enumerate(agents) if agent.get("focused")), -1)


def parse_step(argv: list[str]) -> int:
    if not argv or argv == ["next"]:
        return 1
    if argv == ["previous"]:
        return -1
    raise NextAgentError("usage: next_agent.py [next|previous]")


def main(argv: list[str]) -> int:
    try:
        step = parse_step(argv)
        states, order = load_config(os.environ.get("HERDR_PLUGIN_CONFIG_DIR", ""))
        binary = os.environ.get("HERDR_BIN_PATH") or "herdr"
        target = select_agent(list_agents(binary), states, order, step)
        if target is None:
            run_herdr(binary, "notification", "show", NO_MATCH_MESSAGE)
        else:
            run_herdr(binary, "agent", "focus", target["pane_id"])
    except NextAgentError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
