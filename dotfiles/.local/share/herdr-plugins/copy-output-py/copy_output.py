#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Copy the whole output of a command run in a Herdr pane to the clipboard.

Herdr carries no shell-integration command marks: OSC 133 is consumed by the
terminal emulator and does not survive `herdr pane read`. Command blocks are
therefore delimited by the shell prompt itself. A prompt line that still has
text after the marker is a command that ran, and its output reaches to the
next prompt line.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PROMPT_MARKER = "\u276F"  # starship's prompt character
DEFAULT_HEADER_MARKER = "\uE0B6"  # powerline cap opening starship's status line
DEFAULT_MAX_LINES = 5000
CLIPBOARD_COMMANDS = (
    ("pbcopy",),
    ("wl-copy",),
    ("xclip", "-selection", "clipboard"),
)
PICKER_PANE_ID = "picker"
SOURCE_PANE_ENV = "HERDR_COPY_OUTPUT_SOURCE_PANE"
NO_COMMAND_MESSAGE = "No command output found in this pane"
NO_OUTPUT_MESSAGE = "That command produced no output"
EMPTY_PREVIEW = "(no output)"


class CopyOutputError(Exception):
    """A recoverable failure that should be reported on stderr."""


@dataclass(frozen=True)
class Config:
    prompt_marker: str
    header_marker: str
    max_lines: int


@dataclass(frozen=True)
class Block:
    """One command line from the pane together with the output it produced."""

    command: str
    output: tuple[str, ...]


def load_config(config_dir: str) -> Config:
    default = Config(DEFAULT_PROMPT_MARKER, DEFAULT_HEADER_MARKER, DEFAULT_MAX_LINES)
    if not config_dir:
        return default

    path = Path(config_dir) / "config.toml"
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (OSError, tomllib.TOMLDecodeError) as err:
        raise CopyOutputError(f"read Copy Output configuration {path}: {err}") from err

    unknown = set(raw) - {"prompt_marker", "header_marker", "max_lines"}
    if unknown:
        raise CopyOutputError(f"invalid configuration: unknown field {', '.join(sorted(unknown))}")

    prompt_marker = raw.get("prompt_marker", DEFAULT_PROMPT_MARKER)
    if not isinstance(prompt_marker, str) or not prompt_marker:
        raise CopyOutputError("invalid configuration: prompt_marker must be a non-empty string")

    header_marker = raw.get("header_marker", DEFAULT_HEADER_MARKER)
    if not isinstance(header_marker, str) or not header_marker:
        raise CopyOutputError("invalid configuration: header_marker must be a non-empty string")

    max_lines = raw.get("max_lines", DEFAULT_MAX_LINES)
    if not isinstance(max_lines, int) or isinstance(max_lines, bool) or max_lines < 1:
        raise CopyOutputError("invalid configuration: max_lines must be a positive integer")

    return Config(prompt_marker, header_marker, max_lines)


def run_herdr(binary: str, *args: str) -> str:
    argv = (binary, *args)
    try:
        done = subprocess.run(argv, capture_output=True, text=True, check=False)
    except OSError as err:
        raise CopyOutputError(f"{' '.join(argv)} failed: {err}") from err
    if done.returncode != 0:
        detail = done.stderr.strip() or f"exit status {done.returncode}"
        raise CopyOutputError(f"{' '.join(argv)} failed: {detail}")
    return done.stdout


def notify(binary: str, title: str, body: str | None = None) -> None:
    args = ["notification", "show", title]
    if body:
        args += ["--body", body]
    run_herdr(binary, *args)


def plugin_context() -> dict:
    try:
        return json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or "{}")
    except json.JSONDecodeError as err:
        raise CopyOutputError(f"parse HERDR_PLUGIN_CONTEXT_JSON: {err}") from err


def target_pane() -> str:
    """Resolve the source pane the way Herdr plugins are expected to."""
    direct = os.environ.get(SOURCE_PANE_ENV) or os.environ.get("HERDR_PANE_ID", "")
    if direct:
        return direct

    context = plugin_context()
    for path in (
        ("focused_pane", "pane_id"),
        ("focused_pane", "id"),
        ("pane", "pane_id"),
        ("pane", "id"),
        ("focused_pane_id",),
        ("pane_id",),
    ):
        value: object = context
        for key in path:
            if not isinstance(value, dict):
                break
            value = value.get(key)
        else:
            if isinstance(value, str) and value:
                return value
    raise CopyOutputError("Herdr invocation context has no focused pane")


def read_blocks(binary: str, pane: str, config: Config) -> list[Block]:
    """Return every command block visible in the pane, oldest first."""
    # recent-unwrapped reaches into the scrollback and rejoins soft-wrapped
    # rows, so an output taller or wider than the pane is copied intact.
    stdout = run_herdr(
        binary, "pane", "read", pane,
        "--source", "recent-unwrapped", "--lines", str(config.max_lines), "--format", "text",
    )
    lines = [line.rstrip() for line in stdout.splitlines()]

    prompt = re.compile(r"^\s*" + re.escape(config.prompt_marker) + r"(\s|$)")
    prompts = [i for i, line in enumerate(lines) if prompt.match(line)]

    blocks = []
    for position, start in enumerate(prompts):
        command = prompt.sub("", lines[start], count=1).strip()
        # A bare prompt line is the idle prompt waiting for input, not a
        # command that ran.
        if not command:
            continue
        end = prompts[position + 1] if position + 1 < len(prompts) else len(lines)
        output = lines[start + 1 : end]
        while output and (not output[-1].strip() or output[-1].startswith(config.header_marker)):
            output.pop()
        blocks.append(Block(command, tuple(output)))
    return blocks


def plural(count: int) -> str:
    return f"{count} line" if count == 1 else f"{count} lines"


def copy_to_clipboard(text: str) -> None:
    for argv in CLIPBOARD_COMMANDS:
        if not shutil.which(argv[0]):
            continue
        try:
            subprocess.run(argv, input=text, text=True, check=True)
        except (OSError, subprocess.CalledProcessError) as err:
            raise CopyOutputError(f"{argv[0]} failed: {err}") from err
        return
    raise CopyOutputError("no clipboard tool found (pbcopy, wl-copy or xclip)")


def deliver(binary: str, block: Block) -> None:
    if not block.output:
        notify(binary, NO_OUTPUT_MESSAGE, block.command)
        return
    copy_to_clipboard("\n".join(block.output) + "\n")
    notify(binary, "Copied command output", f"{plural(len(block.output))} from {block.command}")


def copy_command(binary: str, config: Config, nth: int) -> None:
    blocks = read_blocks(binary, target_pane(), config)
    if len(blocks) < nth:
        notify(binary, NO_COMMAND_MESSAGE)
        return
    deliver(binary, blocks[-nth])


def pick_command(binary: str) -> None:
    """Open the picker in an overlay pane over the pane being read."""
    pane = target_pane()
    # Overlay panes always cover the active pane and reject --placement and
    # --workspace; the manifest sets the placement and the pane to read
    # travels in the environment.
    run_herdr(
        binary, "plugin", "pane", "open",
        "--plugin", plugin_id(), "--entrypoint", PICKER_PANE_ID,
        "--env", f"{SOURCE_PANE_ENV}={pane}", "--focus",
    )


def plugin_id() -> str:
    return os.environ.get("HERDR_PLUGIN_ID") or "local.copy-output"


def picker_command(binary: str, config: Config) -> None:
    """Run the fzf picker itself. This runs inside the overlay pane."""
    if not shutil.which("fzf"):
        raise CopyOutputError("fzf is required for the picker")

    blocks = read_blocks(binary, target_pane(), config)
    if not blocks:
        notify(binary, NO_COMMAND_MESSAGE)
        return

    # Newest first, so the most likely pick sits under the cursor.
    blocks.reverse()
    with tempfile.TemporaryDirectory(prefix="herdr-copy-output-") as directory:
        menu = []
        for index, block in enumerate(blocks):
            body = "\n".join(block.output) if block.output else EMPTY_PREVIEW
            (Path(directory) / str(index)).write_text(body + "\n", encoding="utf-8")
            label = plural(len(block.output)) if block.output else "no output"
            menu.append(f"{index}\t{label:>10}  {block.command}")

        selected = run_fzf(directory, menu)

    if selected is None:
        return
    deliver(binary, blocks[selected])


def run_fzf(directory: str, menu: list[str]) -> int | None:
    done = subprocess.run(
        [
            "fzf",
            "--delimiter", "\t",
            "--with-nth", "2..",
            "--no-sort",
            "--layout", "reverse",
            "--prompt", "copy output> ",
            "--header", "enter: copy to clipboard    esc: cancel",
            "--preview", f"cat {shlex.quote(directory)}/{{1}}",
            "--preview-window", "right,60%,wrap",
        ],
        input="\n".join(menu),
        text=True,
        capture_output=True,
        check=False,
    )
    if done.returncode != 0:  # 1 = no match, 130 = cancelled
        return None
    return int(done.stdout.split("\t", 1)[0])


def parse_args(argv: list[str]) -> tuple[str, int]:
    if not argv or argv[0] == "copy":
        rest = argv[1:]
        if not rest:
            return "copy", 1
        if len(rest) == 1 and rest[0].isdigit() and int(rest[0]) >= 1:
            return "copy", int(rest[0])
    elif argv in (["pick"], ["picker"]):
        return argv[0], 1
    raise CopyOutputError("usage: copy_output.py [copy [N] | pick | picker]")


def main(argv: list[str]) -> int:
    try:
        command, nth = parse_args(argv)
        config = load_config(os.environ.get("HERDR_PLUGIN_CONFIG_DIR", ""))
        binary = os.environ.get("HERDR_BIN_PATH") or "herdr"
        if command == "copy":
            copy_command(binary, config, nth)
        elif command == "pick":
            pick_command(binary)
        else:
            picker_command(binary, config)
    except CopyOutputError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
