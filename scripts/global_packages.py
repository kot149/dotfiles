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
    """Run cmd with its output streamed; return whether it succeeded or was skipped."""
    exe = shutil.which(cmd[0])
    if exe is None:
        print(f"skip: {cmd[0]} not found")
        return True
    return subprocess.run([exe, *cmd[1:]]).returncode == 0


def capture(*cmd: str) -> str | None:
    exe = shutil.which(cmd[0])
    if exe is None:
        return None
    proc = subprocess.run([exe, *cmd[1:]], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return proc.stdout if proc.returncode == 0 else None


def npm_global(action: str) -> bool:
    root = capture("npm", "root", "-g")
    if root is None:
        print("skip: npm not found")
        return True
    # With Nix's nodejs the global prefix is a read-only store path that never holds packages.
    if not Path(root.strip()).is_dir():
        print(f"no global packages ({root.strip()} does not exist)")
        return True
    if action == "list":
        return run("npm", "ls", "-g", "--depth=0")
    return run("npm", "update", "-g")


def cargo_crates() -> list[str] | None:
    """Crates from crates.io installed with cargo install (path and git installs excluded)."""
    out = capture("cargo", "install", "--list")
    if out is None:
        return None
    # Header lines look like "name v1.2.3:" or "name v0.1.0 (/local/path):".
    return [line.split()[0] for line in out.splitlines() if line and not line[0].isspace() and "(" not in line]


def cargo_list() -> bool:
    if capture("cargo", "install", "--list") is None:
        print("skip: cargo is not usable (no toolchain?)")
        return True
    return run("cargo", "install", "--list")


def cargo_update() -> bool:
    crates = cargo_crates()
    if crates is None:
        print("skip: cargo is not usable (no toolchain?)")
        return True
    if not crates:
        print("no crates installed")
        return True
    if shutil.which("cargo-binstall"):
        return run("cargo", "binstall", "-y", *crates)
    return run("cargo", "install", *crates)


def go_binaries() -> dict[str, tuple[str, str, bool]] | None:
    """Map each binary in GOBIN (or GOPATH/bin) to its module path, version and whether it was built locally."""
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
        mod = next((f for f in fields if len(f) > 3 and f[1] == "mod"), None)
        version = mod[3] if mod else ""
        # Local builds have no module sum; before Go 1.24 their version is also "(devel)".
        local = mod is None or version == "(devel)" or len(mod) < 5 or not mod[4]
        if path:
            binaries[exe.name] = (path, version, local)
    return binaries


def go_list() -> bool:
    binaries = go_binaries()
    if binaries is None:
        print("skip: go not found")
        return True
    if not binaries:
        print("no binaries installed")
    for name, (path, version, _) in binaries.items():
        print(f"{name}\t{path}\t{version}")
    return True


def go_update() -> bool:
    binaries = go_binaries()
    if binaries is None:
        print("skip: go not found")
        return True
    if not binaries:
        print("no binaries installed")
    results = []
    for name, (path, _, local) in binaries.items():
        if local:
            print(f"skip: {name} is built locally")
            continue
        results.append(run("go", "install", f"{path}@latest"))
    return all(results)


MANAGERS = {
    "bun": (lambda: run("bun", "pm", "ls", "-g"), lambda: run("bun", "update", "-g")),
    "npm": (lambda: npm_global("list"), lambda: npm_global("update")),
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

    failed: list[str] = []
    for name in args.managers or MANAGERS:
        print(f"== {name}", flush=True)
        list_fn, update_fn = MANAGERS[name]
        if not (list_fn if args.action == "list" else update_fn)():
            failed.append(name)
        sys.stdout.flush()
    if failed:
        print(f"failed: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
