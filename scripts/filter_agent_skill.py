# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Patch one skill in a GitHub tarball before chezmoi builds its target state."""

import argparse
import copy
import gzip
import io
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

PATCH_DIR = Path(__file__).resolve().parent / "agent-skill-patches"


def patch_path(name: str) -> Path:
    return PATCH_DIR / f"{name}.patch"


def safe_parts(name: str) -> tuple[str, ...]:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
        raise ValueError(f"unsafe archive path: {name!r}")
    return path.parts


def filter_archive(data: bytes, skill_path: str, patch: Path) -> bytes:
    """Return an archive with only skill_path patched; never extract archive links."""
    parts = safe_parts(skill_path)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as source:
        members = source.getmembers()
        roots = {safe_parts(member.name)[0] for member in members if safe_parts(member.name)}
        if len(roots) != 1:
            raise ValueError("expected one GitHub archive root directory")
        prefix = (next(iter(roots)), *parts)
        originals: dict[str, tarfile.TarInfo] = {}
        with tempfile.TemporaryDirectory(prefix="agent-skill-patch-") as temporary:
            directory = Path(temporary)
            for member in members:
                member_parts = safe_parts(member.name)
                if member_parts[: len(prefix)] != prefix:
                    continue
                relative_parts = member_parts[len(prefix) :]
                if not relative_parts:
                    if not member.isdir():
                        raise ValueError(f"skill root is not a directory: {member.name}")
                    continue
                if any(part.lower() == ".git" for part in relative_parts):
                    raise ValueError(f"unexpected .git entry: {member.name}")
                relative = "/".join(relative_parts)
                if relative in originals:
                    raise ValueError(f"duplicate archive member: {member.name}")
                originals[relative] = member
                target = directory.joinpath(*relative_parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    body = source.extractfile(member)
                    if body is None:
                        raise ValueError(f"cannot read archive member: {member.name}")
                    target.write_bytes(body.read())
                    target.chmod(member.mode & 0o777)
                else:
                    raise ValueError(f"unsupported link or special file in skill: {member.name}")
            if not any(member.isfile() for member in originals.values()):
                raise ValueError(f"skill not found in archive: {skill_path!r}")
            patch_data = patch.read_bytes().replace(b"\r\n", b"\n")
            for options in (["--check"], []):
                result = subprocess.run(
                    ["git", "apply", "--no-index", *options, "-"],
                    cwd=directory,
                    input=patch_data,
                    capture_output=True,
                )
                if result.returncode:
                    raise ValueError(
                        f"{patch.name} ({skill_path or '.'}): {result.stderr.decode('utf-8', errors='replace').strip()}"
                    )
            files = {}
            for target in directory.rglob("*"):
                if target.is_symlink():
                    raise ValueError(f"patch created a symlink: {target.relative_to(directory)}")
                if target.is_file():
                    files[target.relative_to(directory).as_posix()] = target
            output = io.BytesIO()
            with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as destination:
                    for member in members:
                        member_parts = safe_parts(member.name)
                        if member_parts[: len(prefix)] != prefix or member.isdir():
                            destination.addfile(member, source.extractfile(member) if member.isfile() else None)
                            continue
                        relative = "/".join(member_parts[len(prefix) :])
                        target = files.pop(relative, None)
                        if target is not None:
                            updated = copy.copy(member)
                            body = target.read_bytes()
                            updated.size = len(body)
                            # git apply recreates files using the host umask; only its executable bit is meaningful.
                            if os.name != "nt":
                                updated.mode = (member.mode & ~0o111) | (stat.S_IMODE(target.stat().st_mode) & 0o111)
                            destination.addfile(updated, io.BytesIO(body))
                    for relative, target in sorted(files.items()):
                        member = tarfile.TarInfo("/".join((*prefix, relative)))
                        body = target.read_bytes()
                        member.size = len(body)
                        member.mode = 0o755 if os.name != "nt" and target.stat().st_mode & 0o111 else 0o644
                        destination.addfile(member, io.BytesIO(body))
            return output.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skill-path", required=True)
    parser.add_argument("--patch", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = filter_archive(sys.stdin.buffer.read(), args.skill_path, args.patch)
    except (ValueError, OSError, tarfile.TarError) as error:
        sys.exit(str(error))
    sys.stdout.buffer.write(result)


if __name__ == "__main__":
    main()
