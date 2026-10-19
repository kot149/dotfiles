# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Render the agent config templates and check that the output parses.

Each target is rendered with `chezmoi cat` (modify_ templates merge the live
file in $HOME) and parsed as JSON / TOML / Nix. Exits 1 if any target fails
to render or parse. Read-only: it never writes to the repository or to $HOME.

With --destination, the targets are read from a directory chezmoi already
applied into (see `just ci-render`) instead, for the OS given with --os; a
missing target fails unless .chezmoiignore drops it on that OS, and the
non-target templates are not checked.

Usage:
  uv run --script scripts/render_check.py
  uv run --script scripts/render_check.py --source <dir>
  uv run --script scripts/render_check.py --destination <dir> [--os <os>]
"""
import argparse
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

# (target relative to $HOME, kind)
TARGETS = [
    (".claude/settings.json", "json"),
    (".codex/hooks.json", "json"),
    (".codex/config.toml", "toml"),
    (".config/opencode/opencode.json", "json"),
    (".config/opencode/cli.json", "json"),
    (".gemini/antigravity-cli/settings.json", "json"),
    (".config/home-manager/flake.nix", "nix"),
    (".config/home-manager/common.nix", "nix"),
    (".config/nix-darwin/flake.nix", "nix"),
    (".config/nix-darwin/darwin-configuration.nix", "nix"),
    (".config/nix-darwin/custom-user-preferences.nix", "nix"),
    (".zshrc", "text"),
]
# (template relative to the source dir, printed name, kind)
NON_TARGETS = [
    (".chezmoiignore.tmpl", ".chezmoiignore", "text"),
    (".chezmoiexternal.toml.tmpl", ".chezmoiexternal.toml", "toml"),
]


HOST_OS = {"win32": "windows"}.get(sys.platform, sys.platform)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", **kwargs)


def gated_reason(target: str, os_name: str) -> str | None:
    """Why .chezmoiignore drops this target on os_name (a .chezmoi.os value)."""
    if target.startswith(".config/nix-darwin/") and os_name != "darwin":
        return "nix-darwin is macOS only"
    if target.startswith(".config/home-manager/") and os_name == "windows":
        return "Home Manager is not used on Windows"
    if target == ".zshrc" and os_name == "windows":
        return "ignored on Windows"
    return None


def nix_missing(kind: str) -> bool:
    return kind == "nix" and shutil.which("nix-instantiate") is None


def parse_error(text: str, kind: str) -> str | None:
    try:
        if kind == "json":
            json.loads(text)
        elif kind == "toml":
            tomllib.loads(text)
    except ValueError as e:
        return f"{kind} parse error: {e}"
    if kind == "nix":
        r = run(["nix-instantiate", "--parse", "-"], input=text)
        if r.returncode != 0:
            return f"nix parse error: {r.stderr.strip()}"
    return None


def report(name: str, error: str | None) -> bool:
    print(f"FAIL {name}: {error}" if error else f"OK   {name}")
    return error is None


def check_destination(dest: Path, os_name: str) -> int:
    ok = True
    for target, kind in TARGETS:
        path = dest / target
        reason = gated_reason(target, os_name)
        if reason:
            print(f"SKIP {target}: {reason}")
        elif not path.is_file():
            ok &= report(target, "not rendered")
        elif nix_missing(kind):
            print(f"SKIP {target}: nix-instantiate not found")
        else:
            ok &= report(target, parse_error(path.read_text(encoding="utf-8"), kind))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    ap.add_argument("--source", help="chezmoi source directory (default: chezmoi source-path)")
    ap.add_argument("--destination", help="check the files chezmoi applied into this directory")
    ap.add_argument("--os", default=HOST_OS,
                    help="the .chezmoi.os the targets were rendered for (default: this host's)")
    args = ap.parse_args()

    if args.destination:
        return check_destination(Path(args.destination), args.os)

    if args.source:
        source_dir = Path(args.source).resolve()
        chezmoi = ["chezmoi", "--source", str(source_dir)]
    else:
        r = run(["chezmoi", "source-path"])
        if r.returncode != 0:
            print(f"chezmoi source-path failed: {r.stderr.strip()}", file=sys.stderr)
            return 1
        source_dir = Path(r.stdout.strip())
        chezmoi = ["chezmoi"]
    home = Path.home()

    ok = True
    for target, kind in TARGETS:
        reason = gated_reason(target, HOST_OS) or ("nix-instantiate not found" if nix_missing(kind) else None)
        if reason:
            print(f"SKIP {target}: {reason}")
            continue
        # Decide by exit code only: chezmoi warns on stderr with exit 0 when
        # the config template is newer than the generated config.
        r = run([*chezmoi, "cat", str(home / target)])
        error = r.stderr.strip() if r.returncode != 0 else parse_error(r.stdout, kind)
        ok &= report(target, error)

    for template, name, kind in NON_TARGETS:
        r = run([*chezmoi, "execute-template"], cwd=source_dir,
                input=(source_dir / template).read_text(encoding="utf-8"))
        error = r.stderr.strip() if r.returncode != 0 else parse_error(r.stdout, kind)
        ok &= report(name, error)

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
