# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise install_agent_skills.py with real git patches against a loopback HTTP archive."""

import difflib
import functools
import http.server
import io
import os
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from install_agent_skills import stage  # noqa: E402


def archive(files: dict[str, bytes], executable: str = "") -> bytes:
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w:gz") as output:
        for name, body in files.items():
            member = tarfile.TarInfo(name)
            member.size = len(body)
            member.mode = 0o755 if name == executable else 0o644
            output.addfile(member, io.BytesIO(body))
    return result.getvalue()


def tree(root: Path) -> dict[str, bytes]:
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def patch_text(old: str, new: str, name: str = "SKILL.md") -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            f"a/{name}" if old else "/dev/null",
            f"b/{name}" if new else "/dev/null",
        )
    )


class StageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="skill install tests ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.patch = self.root / "demo.patch"
        self.patch.write_text(patch_text("English\n", "日本語\n"), encoding="utf-8")

    def stage(self, files: dict[str, bytes], skills: dict[str, Path | None], executable: str = "") -> dict[str, Path]:
        path = self.root / "archive.tar.gz"
        path.write_bytes(archive(files, executable))
        return stage(path, skills, Path(tempfile.mkdtemp(dir=self.root)))

    def test_one_pass_extracts_several_skills_with_modes_and_binaries(self):
        staged = self.stage(
            {
                "repo/skills/demo/SKILL.md": b"English\n",
                "repo/skills/demo/scripts/run": b"#!/bin/sh\necho ok\n",
                "repo/skills/demo/image.bin": b"\x00\xff\x80",
                "repo/skills/other/SKILL.md": b"English\n",
                "repo/README.md": b"ignored\n",
            },
            {"skills/demo": self.patch, "skills/other": None},
            "repo/skills/demo/scripts/run",
        )
        self.assertEqual(
            tree(staged["skills/demo"]),
            {"SKILL.md": "日本語\n".encode(), "image.bin": b"\x00\xff\x80", "scripts/run": b"#!/bin/sh\necho ok\n"},
        )
        self.assertEqual(tree(staged["skills/other"]), {"SKILL.md": b"English\n"})
        if os.name != "nt":
            self.assertTrue(os.access(staged["skills/demo"] / "scripts/run", os.X_OK))

    def test_host_git_line_endings_do_not_change_contents(self):
        config = {
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "core.autocrlf",
            "GIT_CONFIG_VALUE_0": "true",
            "GIT_CONFIG_KEY_1": "core.eol",
            "GIT_CONFIG_VALUE_1": "crlf",
        }
        with patch.dict(os.environ, config):
            staged = self.stage({"repo/SKILL.md": b"English\n"}, {"": self.patch})
        self.assertEqual(tree(staged[""]), {"SKILL.md": "日本語\n".encode()})

    def test_flat_skill_adds_and_deletes_files(self):
        self.patch.write_text(
            patch_text("English\n", "日本語\n")
            + patch_text("obsolete\n", "", "references/old.md")
            + patch_text("", "new reference\n", "references/new.md"),
            encoding="utf-8",
        )
        staged = self.stage({"repo/SKILL.md": b"English\n", "repo/references/old.md": b"obsolete\n"}, {"": self.patch})
        self.assertEqual(tree(staged[""]), {"SKILL.md": "日本語\n".encode(), "references/new.md": b"new reference\n"})

    def test_conflict_and_missing_skill_fail(self):
        with self.assertRaisesRegex(ValueError, "demo.patch"):
            self.stage({"repo/skills/demo/SKILL.md": b"Upstream changed\n"}, {"skills/demo": self.patch})
        with self.assertRaisesRegex(ValueError, "not found"):
            self.stage({"repo/skills/other/SKILL.md": b"English\n"}, {"skills/demo": None})

    def test_unsafe_archive_paths_and_links_are_rejected(self):
        for name in ["repo/skills/demo/../../escape", "/absolute", "repo/skills/demo/C:/escape"]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "a.tar.gz"
                path.write_bytes(archive({name: b"English\n"}))
                (Path(directory) / "out").mkdir()
                with self.assertRaises(ValueError):
                    stage(path, {"skills/demo": None}, Path(directory) / "out")
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as output:
            member = tarfile.TarInfo("repo/skills/demo/SKILL.md")
            member.type = tarfile.SYMTYPE
            member.linkname = "../../outside"
            output.addfile(member)
        path = self.root / "link.tar.gz"
        path.write_bytes(data.getvalue())
        with self.assertRaisesRegex(ValueError, "link or special file"):
            stage(path, {"skills/demo": None}, Path(tempfile.mkdtemp(dir=self.root)))

    def test_patch_cannot_escape_skill_directory(self):
        self.patch.write_text(patch_text("", "escaped\n", "../escaped.md"), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.stage({"repo/SKILL.md": b"English\n"}, {"": self.patch})
        self.assertEqual(list(self.root.rglob("escaped.md")), [])


class InstallTests(unittest.TestCase):
    def test_install_skip_patch_change_conflict_and_removal(self):
        temporary = tempfile.TemporaryDirectory(prefix="skill install tests ")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        source, home, cache, served = root / "source with spaces", root / "home", root / "cache", root / "served"
        (source / ".chezmoidata").mkdir(parents=True)
        (source / "scripts/agent-skill-patches").mkdir(parents=True)
        (served / "owner/demo").mkdir(parents=True)
        (served / "owner/demo/fixed.tar.gz").write_bytes(
            archive({"demo-fixed/skills/demo/SKILL.md": b"English\n", "demo-fixed/skills/extra/SKILL.md": b"Extra\n"})
        )
        data = source / ".chezmoidata/agent-skills.toml"
        entry = (
            '[[agent_skills]]\nrepo = "owner/demo"\nrev = "fixed"\nprefix = "skills"\n'
            'names = [{names}]\nagents = ["claude", "agents"]\n'
        )
        data.write_text(entry.format(names='"demo", "extra"'), encoding="utf-8")
        installed_patch = source / "scripts/agent-skill-patches/demo.patch"
        installed_patch.write_text(patch_text("English\n", "日本語\n"), encoding="utf-8")

        requests = []

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                requests.append(self.path)
                super().do_GET()

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(served)))
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        threading.Thread(target=server.serve_forever, daemon=True).start()

        def run():
            return subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/install_agent_skills.py"),
                    "--source",
                    str(source),
                    "--home",
                    str(home),
                    "--cache",
                    str(cache),
                    "--url",
                    f"http://127.0.0.1:{server.server_port}/{{repo}}/{{rev}}.tar.gz",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )

        targets = [home / f".{store}/skills/demo/SKILL.md" for store in ["agents", "claude"]]
        result = run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["日本語\n"] * 2)
        self.assertEqual((home / ".claude/skills/extra/SKILL.md").read_text(encoding="utf-8"), "Extra\n")
        self.assertEqual(len(requests), 1)

        result = run()
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)

        (home / ".claude/skills/demo/stray.md").write_text("stray\n", encoding="utf-8")
        installed_patch.write_text(patch_text("English\n", "自然な日本語\n"), encoding="utf-8")
        result = run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["自然な日本語\n"] * 2)
        self.assertFalse((home / ".claude/skills/demo/stray.md").exists())
        self.assertNotIn("extra", result.stdout)
        self.assertEqual(len(requests), 1)

        installed_patch.write_text(patch_text("Missing anchor\n", "日本語\n"), encoding="utf-8")
        result = run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("demo.patch", result.stderr)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["自然な日本語\n"] * 2)

        installed_patch.unlink()
        data.write_text(entry.format(names='"demo"'), encoding="utf-8")
        result = run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["English\n"] * 2)
        self.assertFalse((home / ".claude/skills/extra").exists())
        self.assertFalse((home / ".agents/skills/extra").exists())


if __name__ == "__main__":
    unittest.main()
