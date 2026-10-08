# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Render the agent config templates and check that the output parses.

Each target is rendered with `chezmoi cat` (modify_ templates merge the live
file in $HOME) and parsed as JSON / TOML / Nix. Exits 1 if any target fails
to render or parse. Read-only: it never writes to the repository or to $HOME.

Usage:
  uv run --script scripts/render_check.py
  uv run --script scripts/render_check.py --source <dir>
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
    (".config/opencode/tui.json", "json"),
    (".gemini/antigravity-cli/settings.json", "json"),
    (".config/home-manager/flake.nix", "nix"),
    (".config/home-manager/common.nix", "nix"),
    (".config/nix-darwin/flake.nix", "nix"),
    (".config/nix-darwin/darwin-configuration.nix", "nix"),
    (".zshrc", "text"),
]
# (template relative to the source dir, printed name, kind)
NON_TARGETS = [
    (".chezmoiignore.tmpl", ".chezmoiignore", "text"),
    (".chezmoiexternal.toml.tmpl", ".chezmoiexternal.toml", "toml"),
]


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", **kwargs)


def skip_reason(target: str, kind: str) -> str | None:
    if target.startswith(".config/nix-darwin/") and sys.platform != "darwin":
        return "nix-darwin is macOS only"
    if target == ".zshrc" and sys.platform == "win32":
        return "ignored on Windows"
    if kind == "nix" and shutil.which("nix-instantiate") is None:
        return "nix-instantiate not found"
    return None


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    ap.add_argument("--source", help="chezmoi source directory (default: chezmoi source-path)")
    args = ap.parse_args()

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
        reason = skip_reason(target, kind)
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
