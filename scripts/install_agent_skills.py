# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Install the third-party skills declared in .chezmoidata/agent-skills.toml.

Each pinned GitHub tarball is read once, however many skills and stores use it.
Skills with a patch in scripts/agent-skill-patches/ are patched with git apply.
A state file records what each target was installed from, so unchanged targets
are skipped without downloading or opening their archive, and targets dropped
from the data file are removed.

Usage:
  uv run --script scripts/install_agent_skills.py
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib
from pathlib import Path, PurePosixPath
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_URL = "https://github.com/{repo}/archive/{rev}.tar.gz"


def patch_path(name: str, source: Path = ROOT) -> Path:
    return source / "scripts" / "agent-skill-patches" / f"{name}.patch"


def skill_path(entry: dict, name: str) -> str:
    prefix = entry.get("prefix", "")
    if entry.get("flat", False):
        return prefix
    return f"{prefix}/{name}" if prefix else name


def safe_parts(name: str) -> tuple[str, ...]:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
        raise ValueError(f"unsafe archive path: {name!r}")
    return path.parts


def extract_skills(archive: Path, destinations: dict[str, Path]) -> None:
    """Extract each skill path of a GitHub archive into its destination in one pass; never extract links."""
    wanted = {path: safe_parts(path) for path in destinations}
    root = None
    found: set[str] = set()
    with tarfile.open(archive, mode="r|*") as source:
        for member in source:
            parts = safe_parts(member.name)
            if not parts:
                continue
            if root is None:
                root = parts[0]
            elif parts[0] != root:
                raise ValueError("expected one GitHub archive root directory")
            for path, prefix in wanted.items():
                if parts[1 : 1 + len(prefix)] != prefix:
                    continue
                relative = parts[1 + len(prefix) :]
                if not relative:
                    if not member.isdir():
                        raise ValueError(f"skill root is not a directory: {member.name}")
                    continue
                if any(part.lower() == ".git" for part in relative):
                    raise ValueError(f"unexpected .git entry: {member.name}")
                target = destinations[path].joinpath(*relative)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    if target.exists():
                        raise ValueError(f"duplicate archive member: {member.name}")
                    body = source.extractfile(member)
                    if body is None:
                        raise ValueError(f"cannot read archive member: {member.name}")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open("wb") as output:
                        shutil.copyfileobj(body, output)
                    target.chmod(member.mode & 0o777)
                    found.add(path)
                else:
                    raise ValueError(f"unsupported link or special file in skill: {member.name}")
    missing = sorted(set(destinations) - found)
    if missing:
        raise ValueError(f"skill not found in archive: {', '.join(repr(m) for m in missing)}")


def apply_patch(directory: Path, patch: Path) -> None:
    patch_data = patch.read_bytes().replace(b"\r\n", b"\n")
    for options in (["--check"], []):
        result = subprocess.run(
            ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "apply", "--no-index", *options, "-"],
            cwd=directory,
            input=patch_data,
            capture_output=True,
        )
        if result.returncode:
            raise ValueError(f"{patch.name}: {result.stderr.decode('utf-8', errors='replace').strip()}")
    for target in directory.rglob("*"):
        if target.is_symlink():
            raise ValueError(f"{patch.name} created a symlink: {target.relative_to(directory)}")


def stage(archive: Path, skills: dict[str, Path | None], directory: Path) -> dict[str, Path]:
    """Extract and patch skills ({skill path: patch or None}) under directory; return each staged root."""
    staged = {path: directory / str(index) for index, path in enumerate(skills)}
    for root in staged.values():
        root.mkdir()
    extract_skills(archive, staged)
    for path, patch in skills.items():
        if patch is not None:
            apply_patch(staged[path], patch)
    return staged


def download(url: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    with urlopen(url, timeout=120) as response, partial.open("wb") as output:
        shutil.copyfileobj(response, output)
    partial.replace(target)


def remove(target: Path) -> None:
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)


def install(source: Path, home: Path, cache: Path, url: str) -> int:
    data = source / ".chezmoidata" / "agent-skills.toml"
    entries = tomllib.loads(data.read_text(encoding="utf-8"))["agent_skills"]
    state_file = cache / "installed.json"
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}

    # (repo, rev) -> {target: (skill path, patch, key)}
    repos: dict[tuple[str, str], dict[str, tuple[str, Path | None, str]]] = {}
    for entry in entries:
        for name in entry["names"]:
            path = skill_path(entry, name)
            patch = patch_path(name, source)
            patch = patch if patch.is_file() else None
            digest = hashlib.sha256(patch.read_bytes()).hexdigest() if patch else ""
            key = f"{entry['repo']}@{entry['rev']}:{path}:{digest}"
            for agent in entry["agents"]:
                target = f".{agent}/skills/{name}"
                repos.setdefault((entry["repo"], entry["rev"]), {})[target] = (path, patch, key)
    declared = {target for targets in repos.values() for target in targets}

    failed = False
    for target in sorted(set(state) - declared):
        remove(home / target)
        del state[target]
        print(f"removed {target}")

    archives = cache / "archives"
    kept = set()
    for (repo, rev), targets in repos.items():
        archive = archives / f"{repo.replace('/', '-')}-{rev}.tar.gz"
        kept.add(archive.name)
        stale = {t: v for t, v in targets.items() if state.get(t) != v[2] or not (home / t).is_dir()}
        if not stale:
            continue
        try:
            if not archive.is_file():
                print(f"downloading {repo}@{rev[:12]}", flush=True)
                download(url.format(repo=repo, rev=rev), archive)
            with tempfile.TemporaryDirectory(prefix="agent-skills-") as temporary:
                skills = {path: patch for path, patch, _ in stale.values()}
                staged = stage(archive, skills, Path(temporary))
                for target, (path, _, key) in sorted(stale.items()):
                    destination = home / target
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    incoming = destination.with_name(f".{destination.name}.installing")
                    remove(incoming)
                    shutil.copytree(staged[path], incoming)
                    remove(destination)
                    incoming.rename(destination)
                    state[target] = key
                    print(f"installed {target}")
        except (OSError, ValueError, tarfile.TarError) as error:
            print(f"error: {repo}@{rev[:12]}: {error}", file=sys.stderr)
            failed = True
        finally:
            cache.mkdir(parents=True, exist_ok=True)
            state_file.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if archives.is_dir():
        for old in archives.iterdir():
            if old.name not in kept:
                old.unlink()
    return 1 if failed else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=ROOT, help="repository holding the data file and patches")
    parser.add_argument("--home", type=Path, default=Path.home(), help="directory holding .claude/ and .agents/")
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "agent-skills"
    parser.add_argument("--cache", type=Path, default=cache, help="archive cache and install state")
    parser.add_argument("--url", default=DEFAULT_URL, help="archive URL with {repo} and {rev} placeholders")
    args = parser.parse_args()
    sys.exit(install(args.source, args.home, args.cache, args.url))


if __name__ == "__main__":
    main()
