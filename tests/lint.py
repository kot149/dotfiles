# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Check focused linting against isolated sources and the real ruff CLI."""

import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import lint  # noqa: E402


class SelectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="lint selection ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "scripts").mkdir()
        (self.root / "scripts/good.py").write_text("answer = 42\n", encoding="utf-8")
        (self.root / "scripts/bad.py").write_text("def broken(\n", encoding="utf-8")

    def invoke(self, *args):
        output = io.StringIO()
        with patch.object(lint, "ROOT", self.root), patch.object(sys, "argv", ["lint.py", *args]):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                try:
                    status = lint.main()
                except SystemExit as error:
                    status = error.code
        return status, output.getvalue()

    @unittest.skipUnless(shutil.which("ruff"), "ruff not installed")
    def test_file_selection_excludes_broken_sibling(self):
        status, output = self.invoke("--only", "python", "scripts/good.py")
        self.assertEqual(status, 0, output)
        status, output = self.invoke("--only", "python", "scripts")
        self.assertEqual(status, 1, output)
        self.assertIn("scripts/bad.py", output)

    def test_selection_uses_directory_boundaries(self):
        renderer = lint.Renderer(self.root, [self.root / "scripts"])
        files = [self.root / "scripts/good.py", self.root / "scripts-other/bad.py"]
        self.assertEqual(renderer.select(files), files[:1])

    def test_unmatched_selection_is_an_error(self):
        (self.root / "notes.txt").write_text("not a lint source\n", encoding="utf-8")
        status, output = self.invoke("--only", "python", "notes.txt")
        self.assertEqual(status, 2)
        self.assertIn("no lint sources matched", output)

    def test_missing_and_outside_paths_are_errors(self):
        for path in ("missing.py", str(self.root.parent)):
            with self.subTest(path=path):
                status, output = self.invoke("--only", "python", path)
                self.assertEqual(status, 2)
                self.assertIn("path must exist inside the repo", output)


if __name__ == "__main__":
    unittest.main()
