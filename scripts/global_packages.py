# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
List or update packages installed globally through language package managers.

Managers whose command is missing or not usable on this machine are skipped.

Usage:
  uv run --script scripts/global_packages.py list [manager ...]
  uv run --script scripts/global_packages.py update [manager ...]
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def run(*cmd: str) -> bool:
    """Run cmd with its output streamed; return whether it succeeded."""
    exe = shutil.which(cmd[0])
    if exe is None:
        print(f"skip: {cmd[0]} not found")
        return False
    return subprocess.run([exe, *cmd[1:]]).returncode == 0


def capture(*cmd: str) -> str | None:
    exe = shutil.which(cmd[0])
    if exe is None:
        return None
    proc = subprocess.run([exe, *cmd[1:]], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return proc.stdout if proc.returncode == 0 else None


def cargo_crates() -> list[str] | None:
    """Crates from crates.io installed with cargo install (path and git installs excluded)."""
    out = capture("cargo", "install", "--list")
    if out is None:
        return None
    # Header lines look like "name v1.2.3:" or "name v0.1.0 (/local/path):".
    return [line.split()[0] for line in out.splitlines() if line and not line[0].isspace() and "(" not in line]


def cargo_list() -> None:
    if capture("cargo", "install", "--list") is None:
        print("skip: cargo is not usable (no toolchain?)")
        return
    run("cargo", "install", "--list")


def cargo_update() -> None:
    crates = cargo_crates()
    if crates is None:
        print("skip: cargo is not usable (no toolchain?)")
        return
    if not crates:
        print("no crates installed")
        return
    if shutil.which("cargo-binstall"):
        run("cargo", "binstall", "-y", *crates)
    else:
        run("cargo", "install", *crates)


def go_binaries() -> dict[str, str] | None:
    """Map each binary in GOBIN (or GOPATH/bin) to the module path it was built from."""
    gobin = capture("go", "env", "GOBIN")
    gopath = capture("go", "env", "GOPATH")
    if gobin is None or gopath is None:
        return None
    bin_dir = Path(gobin.strip() or Path(gopath.strip().split(os.pathsep)[0]) / "bin")
    binaries = {}
    for exe in sorted(bin_dir.glob("*")) if bin_dir.is_dir() else []:
        info = capture("go", "version", "-m", str(exe)) or ""
        fields = [line.split("\t") for line in info.splitlines()]
        path = next((f[2] for f in fields if len(f) > 2 and f[1] == "path"), None)
        if path:
            binaries[exe.name] = path
    return binaries


def go_list() -> None:
    binaries = go_binaries()
    if binaries is None:
        print("skip: go not found")
        return
    if not binaries:
        print("no binaries installed")
    for name, path in binaries.items():
        print(f"{name}\t{path}")


def go_update() -> None:
    binaries = go_binaries()
    if binaries is None:
        print("skip: go not found")
        return
    if not binaries:
        print("no binaries installed")
    for path in binaries.values():
        run("go", "install", f"{path}@latest")


MANAGERS = {
    "bun": (lambda: run("bun", "pm", "ls", "-g"), lambda: run("bun", "update", "-g")),
    "pnpm": (lambda: run("pnpm", "ls", "-g"), lambda: run("pnpm", "update", "-g")),
    "uv": (lambda: run("uv", "tool", "list"), lambda: run("uv", "tool", "upgrade", "--all")),
    "cargo": (cargo_list, cargo_update),
    "go": (go_list, go_update),
}


def main() -> None:
    sys.stdout.reconfigure(errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["list", "update"])
    parser.add_argument("managers", nargs="*", metavar="manager",
                        help=f"one or more of {', '.join(MANAGERS)} (default: all)")
    args = parser.parse_args()
    if unknown := [m for m in args.managers if m not in MANAGERS]:
        parser.error(f"unknown manager: {', '.join(unknown)}")

    for name in args.managers or MANAGERS:
        print(f"== {name}", flush=True)
        list_fn, update_fn = MANAGERS[name]
        (list_fn if args.action == "list" else update_fn)()
        sys.stdout.flush()


if __name__ == "__main__":
    main()
