#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Focus the next or previous Herdr Agent in a configured semantic state."""

from __future__ import annotations

import json
import os
import socket
import sys

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

    path = os.path.join(config_dir, "config.toml")
    try:
        with open(path, "rb") as handle:
            text = handle.read()
    except FileNotFoundError:
        return DEFAULT_STATES, DISPLAY_ORDER
    except OSError as err:
        raise NextAgentError(f"read Next Agent configuration {path}: {err}") from err

    # Imported here so the common no-config path skips the interpreter cost.
    import tomllib

    try:
        raw = tomllib.loads(text.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as err:
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


def call_herdr(socket_path: str, method: str, params: dict) -> dict:
    """Send one request over the Herdr API socket, avoiding a CLI process per call."""
    request = json.dumps({"id": "next-agent", "method": method, "params": params})
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(5)
            conn.connect(socket_path)
            conn.sendall(request.encode() + b"\n")
            with conn.makefile("rb") as reader:
                line = reader.readline()
    except OSError as err:
        raise NextAgentError(f"herdr {method} failed: {err}") from err
    try:
        response = json.loads(line)
    except json.JSONDecodeError as err:
        raise NextAgentError(f"herdr {method} returned an invalid response") from err
    if not isinstance(response, dict):
        raise NextAgentError(f"herdr {method} returned an invalid response")
    if "error" in response:
        raise NextAgentError(f"herdr {method} failed: {response['error'].get('message')}")
    result = response.get("result")
    if not isinstance(result, dict):
        raise NextAgentError(f"herdr {method} returned an invalid response")
    return result


def list_agents(socket_path: str) -> list[dict]:
    agents = call_herdr(socket_path, "agent.list", {}).get("agents")
    if not isinstance(agents, list):
        raise NextAgentError("herdr agent.list returned an invalid response")
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
        socket_path = os.environ.get("HERDR_SOCKET_PATH")
        if not socket_path:
            raise NextAgentError("HERDR_SOCKET_PATH is not set")
        target = select_agent(list_agents(socket_path), states, order, step)
        if target is None:
            call_herdr(socket_path, "notification.show", {"title": NO_MATCH_MESSAGE})
        else:
            call_herdr(socket_path, "agent.focus", {"target": target["pane_id"]})
    except NextAgentError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
