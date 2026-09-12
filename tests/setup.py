"""Regression tests for machine-local setup."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        (self.root / "scripts").mkdir()
        self.script = self.root / "scripts/setup.py"
        shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/setup.py", self.script)
        self.target = self.root / "mise.local.toml"
        self.legacy = self.root / "chezmoi.toml"

    def run_setup(self, answers="\n" * 8, *args):
        # scripts/setup.py declares tomlkit via a PEP 723 header, so it must
        # run under `uv run --script` like production (scripts/setup.sh) does.
        # A plain sys.executable ignores the header and fails the import.
        return subprocess.run(
            ["uv", "run", "--script", str(self.script), "--chezmoi-config", str(self.legacy), *args], input=answers,
            capture_output=True, text=True,
        )

    def test_imports_legacy_values_without_overwriting_local_values(self):
        self.legacy.write_text(
            '[data]\ngit_user_name = "Work User"\ngit_user_email = "work@example.com"\n'
            'git_signing_key = "/keys/work.pub"\ngit_allowed_signers = "/keys/signers"\n'
            'git_editor = "vim"\ngit_commit_gpgsign = false\n'
            'git_safe_directories = ["/work/a", "/work/b"]\nlinuxGui = false\n', encoding="utf-8",
        )
        self.target.write_text('[vars]\ngit_editor = "nano"\n', encoding="utf-8")
        result = self.run_setup("", "--migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        values = tomllib.loads(self.target.read_text())["vars"]
        self.assertEqual(values, {
            "git_user_name": "Work User", "git_user_email": "work@example.com",
            "git_signing_key": "/keys/work.pub", "git_allowed_signers": "/keys/signers",
            "git_editor": "nano", "git_commit_gpgsign": "false",
            "git_safe_directories": "/work/a,/work/b", "linux_gui": "false",
        })
        original = self.target.read_text()
        self.assertEqual(self.run_setup("", "--migrate").returncode, 0)
        self.assertEqual(self.target.read_text(), original)

    def test_interactive_setup_uses_legacy_defaults(self):
        self.legacy.write_text('[data]\ngit_user_name = "Work User"\n', encoding="utf-8")
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertEqual(tomllib.loads(self.target.read_text())["vars"]["git_user_name"], "Work User")

    def test_migration_without_legacy_config_does_not_create_defaults(self):
        self.assertEqual(self.run_setup("", "--migrate").returncode, 0)
        self.assertFalse(self.target.exists())

    def test_preserves_other_settings_and_comments(self):
        self.target.write_text(
            '# machine settings\n[vars]\ngit_editor = "vim" # editor\n'
            'git_commit_gpgsign = "false"\ngit_safe_directories = "/work"\n'
            '[env]\nCUSTOM = "keep"\n', encoding="utf-8",
        )
        result = self.run_setup('Work User\nwork@example.com\nC:\\keys\\work.pub\n\n\n\n\nfalse\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.target.read_text(encoding="utf-8")
        doc = tomllib.loads(text)
        self.assertEqual(doc["vars"]["git_user_name"], "Work User")
        self.assertEqual(doc["vars"]["git_signing_key"], r"C:\keys\work.pub")
        self.assertEqual(doc["vars"]["git_editor"], "vim")
        self.assertEqual(doc["vars"]["git_commit_gpgsign"], "false")
        self.assertEqual(doc["vars"]["git_safe_directories"], "/work")
        self.assertEqual(doc["env"]["CUSTOM"], "keep")
        self.assertIn("# machine settings", text)
        self.assertIn("# editor", text)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_text(encoding="utf-8"), text)

    def test_defaults_on_first_run(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        doc = tomllib.loads(self.target.read_text(encoding="utf-8"))
        self.assertEqual(doc["vars"]["git_user_name"], "kot149")
        self.assertEqual(doc["vars"]["linux_gui"], "")

    def test_invalid_toml_is_not_overwritten(self):
        self.target.write_text("[broken", encoding="utf-8")
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual(self.target.read_text(encoding="utf-8"), "[broken")

    def test_interrupted_input_is_not_saved(self):
        original = '[vars]\ngit_user_name = "Original"\n'
        self.target.write_text(original, encoding="utf-8")
        self.assertNotEqual(self.run_setup("Changed\n").returncode, 0)
        self.assertEqual(self.target.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
