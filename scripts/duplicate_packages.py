# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Find commands installed through a language package manager (bun, npm, pnpm, uv,
cargo, go) that are also provided by another source on PATH, such as Nix,
winget or Homebrew, and show the version each source provides.

The first source on PATH is the one that runs; it is marked with "*".

Usage:
  uv run --script scripts/duplicate_packages.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
IS_WINDOWS = os.name == "nt"


def capture(*cmd: str) -> str | None:
    exe = shutil.which(cmd[0])
    if exe is None:
        return None
    try:
        proc = subprocess.run([exe, *cmd[1:]], capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=30)
    except subprocess.TimeoutExpired:
        return None
    return proc.stdout if proc.returncode == 0 else None


def npm_bins(node_modules: Path, packages: list[str]) -> dict[str, str]:
    """Map each command declared by the packages' package.json "bin" to "package@version"."""
    bins = {}
    for package in packages:
        try:
            manifest = json.loads((node_modules / package / "package.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        declared = manifest.get("bin") or {}
        if isinstance(declared, str):
            declared = {package.split("/")[-1]: declared}
        for name in declared:
            bins[name] = f"{package}@{manifest.get('version', '?')}"
    return bins


def bun_packages() -> tuple[dict[str, str], list[Path]]:
    root = Path(os.environ.get("BUN_INSTALL", HOME / ".bun"))
    try:
        manifest = json.loads((root / "install/global/package.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}, []
    bins = npm_bins(root / "install/global/node_modules", list(manifest.get("dependencies", {})))
    return bins, [root / "bin", root / "install/global"]


def top_level_packages(node_modules: Path) -> list[str]:
    packages = []
    for entry in node_modules.iterdir() if node_modules.is_dir() else []:
        if entry.name.startswith("@"):
            packages += [f"{entry.name}/{sub.name}" for sub in entry.iterdir()]
        elif not entry.name.startswith("."):
            packages.append(entry.name)
    return packages


def npm_packages() -> tuple[dict[str, str], list[Path]]:
    prefix, root = capture("npm", "prefix", "-g"), capture("npm", "root", "-g")
    if prefix is None or root is None:
        return {}, []
    node_modules = Path(root.strip())
    # npm and corepack ship with Node.js itself rather than being installed by the user.
    packages = [p for p in top_level_packages(node_modules) if p not in ("npm", "corepack")]
    bin_dir = Path(prefix.strip()) if IS_WINDOWS else Path(prefix.strip()) / "bin"
    return npm_bins(node_modules, packages), [bin_dir, node_modules]


def pnpm_packages() -> tuple[dict[str, str], list[Path]]:
    out = capture("pnpm", "root", "-g")
    if out is None:
        return {}, []
    node_modules = Path(out.strip())
    bin_dir = capture("pnpm", "bin", "-g")
    dirs = [node_modules.parent] + ([Path(bin_dir.strip())] if bin_dir and bin_dir.strip() != "undefined" else [])
    return npm_bins(node_modules, top_level_packages(node_modules)), dirs


def uv_packages() -> tuple[dict[str, str], list[Path]]:
    out, bin_dir = capture("uv", "tool", "list"), capture("uv", "tool", "dir", "--bin")
    if out is None or bin_dir is None:
        return {}, []
    bins, current = {}, "?"
    for line in out.splitlines():
        if line.startswith("- "):
            bins[line[2:].strip()] = current
        elif line.strip():
            current = "@".join(line.split()[:2]).replace("@v", "@", 1)
    # The uv bin dir is often shared (~/.local/bin), so only the tool's own commands count.
    return bins, [Path(bin_dir.strip()) / (name + (".exe" if IS_WINDOWS else "")) for name in bins]


def cargo_packages() -> tuple[dict[str, str], list[Path]]:
    cargo_home = Path(os.environ.get("CARGO_HOME", HOME / ".cargo"))
    try:
        installs = json.loads((cargo_home / ".crates2.json").read_text(encoding="utf-8"))["installs"]
    except (OSError, ValueError, KeyError):
        return {}, []
    bins = {}
    for key, info in installs.items():
        name, version = key.split()[:2]
        for exe in info.get("bins", []):
            bins[exe.removesuffix(".exe")] = f"{name}@{version}"
    return bins, [cargo_home / "bin"]


def go_packages() -> tuple[dict[str, str], list[Path]]:
    gobin, gopath = capture("go", "env", "GOBIN"), capture("go", "env", "GOPATH")
    if gobin is None or gopath is None:
        return {}, []
    bin_dir = Path(gobin.strip() or Path(gopath.strip().split(os.pathsep)[0]) / "bin")
    bins = {}
    for exe in sorted(bin_dir.glob("*")) if bin_dir.is_dir() else []:
        info = capture("go", "version", "-m", str(exe)) or ""
        fields = [line.split("\t") for line in info.splitlines()]
        mod = next((f for f in fields if len(f) > 3 and f[1] == "mod"), None)
        if mod:
            bins[exe.stem if IS_WINDOWS else exe.name] = f"{mod[2]}@{mod[3]}"
    return bins, [bin_dir]


LANGUAGE_MANAGERS = {
    "bun": bun_packages,
    "npm": npm_packages,
    "pnpm": pnpm_packages,
    "uv": uv_packages,
    "cargo": cargo_packages,
    "go": go_packages,
}


def path_dirs() -> list[Path]:
    dirs = []
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        # On WSL, /mnt/* holds the Windows side's PATH, which is a different machine's install.
        if entry and not (not IS_WINDOWS and entry.startswith("/mnt/")):
            dirs.append(Path(entry))
    return dirs


def find_all(name: str) -> list[Path]:
    """Every executable named name on PATH, in PATH order (like `which -a`)."""
    exts = os.environ.get("PATHEXT", ".EXE;.CMD;.BAT").lower().split(";") if IS_WINDOWS else [""]
    found, seen = [], set()
    for d in path_dirs():
        for ext in exts:
            candidate = d / (name + ext)
            # /bin and /usr/bin can be the same directory; count each real file once.
            real = os.path.realpath(candidate)
            if candidate.is_file() and (IS_WINDOWS or os.access(candidate, os.X_OK)) and real not in seen:
                seen.add(real)
                found.append(candidate)
    return found


def is_under(path: Path, parents: list[Path]) -> bool:
    return any(path == p or path.is_relative_to(p) for p in parents)


def nix_version(path: Path) -> str:
    """Version from the store path name, e.g. /nix/store/<hash>-hunk-0.23.0/bin/hunk -> hunk@0.23.0."""
    store_dir = next((p for p in Path(os.path.realpath(path)).parents if p.parent == Path("/nix/store")), None)
    if store_dir is None:
        return "?"
    name = re.sub(r"-(bin|out|lib|dev|man)$", "", store_dir.name.split("-", 1)[1])
    match = re.search(r"-(\d[^-]*(?:-[^-]+)*)$", name)
    return f"{name[:match.start()]}@{match.group(1)}" if match else name


def brew_version(path: Path) -> str:
    parts = Path(os.path.realpath(path)).parts
    if "Cellar" in parts and len(parts) > parts.index("Cellar") + 2:
        i = parts.index("Cellar")
        return f"{parts[i + 1]}@{parts[i + 2]}"
    return "?"


def reported_version(path: Path) -> str:
    """First line of `<cmd> --version`, for sources without version metadata."""
    try:
        proc = subprocess.run([str(path), "--version"], capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=10, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return "?"
    lines = (proc.stdout or proc.stderr).strip().splitlines()
    return f"--version: {lines[0]}" if lines else "?"


def classify(path: Path, own: dict[str, tuple[dict[str, str], list[Path]]], name: str) -> tuple[str, str]:
    for manager, (bins, dirs) in own.items():
        if name in bins and (is_under(path, dirs) or is_under(Path(os.path.realpath(path)), dirs)):
            return manager, bins[name]
    text = path.as_posix()
    real = Path(os.path.realpath(path)).as_posix()
    # mise shims resolve to the mise binary itself, so check them before the Nix store.
    if "/mise/" in text:
        return "mise", reported_version(path)
    if real.startswith("/nix/store/"):
        return "nix", nix_version(path)
    if "/Cellar/" in real or text.startswith("/opt/homebrew/"):
        return "brew", brew_version(path)
    if "/winget/" in text.lower() or "/windowsapps/" in text.lower():
        return "winget", reported_version(path)
    return "other", reported_version(path)


def main() -> None:
    sys.stdout.reconfigure(errors="replace")
    own = {manager: collect() for manager, collect in LANGUAGE_MANAGERS.items()}
    names = sorted({name for bins, _ in own.values() for name in bins})

    found_any = False
    for name in names:
        sources = [(path, *classify(path, own, name)) for path in find_all(name)]
        if len({source for _, source, _ in sources}) < 2:
            continue
        found_any = True
        print(f"== {name}")
        for i, (path, source, version) in enumerate(sources):
            print(f"  {'*' if i == 0 else ' '} {source:<6} {version:<40} {path}")
    if not found_any:
        print("No duplicates found.")


if __name__ == "__main__":
    main()
