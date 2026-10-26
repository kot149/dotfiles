# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise real git patches and chezmoi externals without network or HOME writes."""

import difflib
import functools
import http.server
import io
import os
import shutil
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
from filter_agent_skill import filter_archive  # noqa: E402


def archive(files: dict[str, bytes], executable: str = "") -> bytes:
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w:gz") as output:
        for name, body in files.items():
            member = tarfile.TarInfo(name)
            member.size = len(body)
            member.mode = 0o755 if name == executable else 0o644
            output.addfile(member, io.BytesIO(body))
    return result.getvalue()


def contents(data: bytes) -> dict[str, tuple[bytes, int]]:
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as source:
        return {m.name: (source.extractfile(m).read(), m.mode) for m in source if m.isfile()}


def patch_text(old: str, new: str, name: str = "SKILL.md") -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            f"a/{name}" if old else "/dev/null",
            f"b/{name}" if new else "/dev/null",
        )
    )


class FilterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="skill filter tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.patch = self.root / "demo.patch"
        self.patch.write_text(patch_text("English\n", "日本語\n"), encoding="utf-8")

    def test_patch_preserves_other_skills_binary_files_and_modes(self):
        files = {
            "repo/skills/demo/SKILL.md": b"English\n",
            "repo/skills/demo/scripts/run": b"#!/bin/sh\necho ok\n",
            "repo/skills/demo/image.bin": b"\x00\xff\x80",
            "repo/skills/other/SKILL.md": b"English\n",
        }
        data = archive(files, "repo/skills/demo/scripts/run")
        actual = contents(filter_archive(data, "skills/demo", self.patch))
        expected = contents(data)
        expected["repo/skills/demo/SKILL.md"] = ("日本語\n".encode(), 0o644)
        self.assertEqual(actual, expected)

    def test_host_git_line_endings_do_not_change_archive_contents(self):
        config = {
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "core.autocrlf",
            "GIT_CONFIG_VALUE_0": "true",
            "GIT_CONFIG_KEY_1": "core.eol",
            "GIT_CONFIG_VALUE_1": "crlf",
        }
        with patch.dict(os.environ, config):
            actual = contents(filter_archive(archive({"repo/SKILL.md": b"English\n"}), "", self.patch))
        self.assertEqual(actual, {"repo/SKILL.md": ("日本語\n".encode(), 0o644)})

    def test_flat_skill_adds_and_deletes_files(self):
        self.patch.write_text(
            patch_text("English\n", "日本語\n")
            + patch_text("obsolete\n", "", "references/old.md")
            + patch_text("", "new reference\n", "references/new.md"),
            encoding="utf-8",
        )
        actual = contents(
            filter_archive(
                archive(
                    {
                        "repo/SKILL.md": b"English\n",
                        "repo/references/old.md": b"obsolete\n",
                    }
                ),
                "",
                self.patch,
            )
        )
        self.assertEqual(
            actual,
            {
                "repo/SKILL.md": ("日本語\n".encode(), 0o644),
                "repo/references/new.md": (b"new reference\n", 0o644),
            },
        )

    def test_conflict_cli_emits_no_partial_archive(self):
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/filter_agent_skill.py"),
                "--skill-path",
                "skills/demo",
                "--patch",
                str(self.patch),
            ],
            input=archive({"repo/skills/demo/SKILL.md": b"Upstream changed\n"}),
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"demo.patch", result.stderr)
        self.assertIn(b"patch does not apply", result.stderr)

    def test_unsafe_archive_paths_and_links_are_rejected(self):
        for name in ["repo/skills/demo/../../escape", "/absolute", "repo/skills/demo/C:/escape"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                filter_archive(archive({name: b"English\n"}), "skills/demo", self.patch)
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as output:
            member = tarfile.TarInfo("repo/skills/demo/SKILL.md")
            member.type = tarfile.SYMTYPE
            member.linkname = "../../outside"
            output.addfile(member)
        with self.assertRaisesRegex(ValueError, "link or special file"):
            filter_archive(data.getvalue(), "skills/demo", self.patch)

    def test_patch_cannot_escape_skill_directory(self):
        self.patch.write_text(patch_text("", "escaped\n", "../escaped.md"), encoding="utf-8")
        with self.assertRaises(ValueError):
            filter_archive(archive({"repo/SKILL.md": b"English\n"}), "", self.patch)
        self.assertFalse((self.root / "escaped.md").exists())

    def test_chezmoi_diff_apply_verify_and_conflict_with_cached_upstream(self):
        source, home = self.root / "source with spaces", self.root / "home"
        source.mkdir()
        home.mkdir()
        (source / "scripts/agent-skill-patches").mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/filter_agent_skill.py", source / "scripts/filter_agent_skill.py")
        installed_patch = source / "scripts/agent-skill-patches/demo.patch"
        shutil.copyfile(self.patch, installed_patch)
        upstream = self.root / "upstream.tar.gz"
        upstream.write_bytes(archive({"repo/skills/demo/SKILL.md": b"English\n"}))
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(self.root)),
        )
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        template = (ROOT / ".chezmoiexternal.toml.tmpl").read_text(encoding="utf-8")
        template = template.replace(
            "https://github.com/{{ $skill.repo }}/archive/{{ $skill.rev }}.tar.gz",
            f"http://127.0.0.1:{server.server_port}/upstream.tar.gz",
        )
        (source / ".chezmoiexternal.toml.tmpl").write_text(template, encoding="utf-8")
        (source / ".chezmoiignore").write_text("scripts/\nDocuments/**\n", encoding="utf-8")
        (source / ".chezmoidata.toml").write_text(
            '[[agent_skills]]\nrepo = "owner/demo"\nrev = "fixed"\nprefix = "skills"\n'
            'names = ["demo"]\nagents = ["claude", "agents"]\n',
            encoding="utf-8",
        )
        config = self.root / "config.toml"
        config.write_text("", encoding="utf-8")
        command = [
            "chezmoi",
            "--config",
            str(config),
            "--source",
            str(source),
            "--destination",
            str(home),
            "--cache",
            str(self.root / "cache"),
            "--persistent-state",
            str(self.root / "state.boltdb"),
            "--no-tty",
        ]

        def run(*args):
            return subprocess.run([*command, *args], capture_output=True, text=True, encoding="utf-8")

        result = run("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        targets = [home / f".{store}/skills/demo/SKILL.md" for store in ["agents", "claude"]]
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["日本語\n"] * 2)
        self.assertEqual(run("verify").returncode, 0)
        installed_patch.write_text(patch_text("English\n", "自然な日本語\n"), encoding="utf-8")
        result = run("diff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("+自然な日本語", result.stdout)
        result = run("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(run("verify").returncode, 0)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["自然な日本語\n"] * 2)
        installed_patch.write_text(patch_text("Missing anchor\n", "日本語\n"), encoding="utf-8")
        result = run("apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([p.read_text(encoding="utf-8") for p in targets], ["自然な日本語\n"] * 2)


if __name__ == "__main__":
    unittest.main()
