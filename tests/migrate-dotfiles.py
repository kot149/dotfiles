"""Regression tests for migration rollback, using temporary files."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("migration", Path(__file__).resolve().parents[1] / "scripts/migrate-dotfiles.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTests(unittest.TestCase):
    def test_restores_files_on_backup_and_apply_failures(self):
        for failure in ("backup", "launch", "apply"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as work:
                root = Path(work)
                first, second = root / "first", root / "second"
                first.write_text("first original")
                second.write_text("second original")
                status = subprocess.CompletedProcess([], 0, json.dumps({"files": [
                    {"target": str(path), "state": "differs"} for path in (first, second)
                ]}), "")
                real_move = migration.shutil.move

                def move(source, target):
                    if failure == "backup" and source == str(second):
                        raise PermissionError("backup denied")
                    return real_move(source, target)

                def run(args, **kwargs):
                    if args[0] == "uv":
                        return subprocess.CompletedProcess(args, 0)
                    if "status" in args:
                        return status
                    if failure == "launch":
                        raise FileNotFoundError("mise unavailable")
                    first.write_text("partially applied")
                    raise subprocess.CalledProcessError(1, args)

                with patch.object(migration, "DOTFILES_HOME", work), \
                     patch.object(migration.shutil, "move", side_effect=move), \
                     patch.object(migration.subprocess, "run", side_effect=run):
                    self.assertEqual(migration.main(), 1)
                self.assertEqual(first.read_text(), "first original")
                self.assertEqual(second.read_text(), "second original")


if __name__ == "__main__":
    unittest.main()
