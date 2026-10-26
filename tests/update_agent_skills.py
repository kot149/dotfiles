# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the pure functions of scripts/update_agent_skills.py.

  uv run --no-python-downloads --script tests/update_agent_skills.py

No network: list_files is replaced where check_entry needs it.
"""

import contextlib
import importlib.util
import io
import sys
import tarfile
import tempfile
import tomllib
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "update_agent_skills.py"
sys.path.insert(0, str(ROOT / "scripts"))

spec = importlib.util.spec_from_file_location("update_agent_skills", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

text = (Path(__file__).resolve().parent / "fixtures" / "agent-skills.toml").read_text(encoding="utf-8")
entries = tomllib.loads(text)["agent_skills"]
A, B, D, H = "a" * 40, "b" * 40, "d" * 40, "h" * 40

failures: list[str] = []
checks = 0


def check(label: str, actual: object, expected: object) -> None:
    global checks
    checks += 1
    if actual != expected:
        failures.append(f"{label}\n      expected: {expected!r}\n      actual:   {actual!r}")


def blocks(s: str) -> list[str]:
    return s.split(module.BLOCK_HEADER)


# Both entries of a shared repo are bumped; the other blocks stay byte-identical.
result = module.apply_updates(text, [{"label": "o/shared", "new": D, "targets": [(0, A), (1, A)]}])
before, after = blocks(text), blocks(result)
check("apply: shared blocks bumped", [f'rev = "{D}"' in b for b in after[1:3]], [True, True])
check("apply: other blocks unchanged", [after[0], *after[3:]], [before[0], *before[3:]])

# CRLF line endings survive the rewrite.
crlf = text.replace("\n", "\r\n")
result = module.apply_updates(crlf, [{"label": "o/solo", "new": D, "targets": [(2, B)]}])
check("apply crlf: rewritten line", f'rev = "{D}"\r\n' in result, True)
check("apply crlf: line endings kept", result.count("\r\n"), crlf.count("\r\n"))

# A rev that is not in the block exits instead of writing a partial file.
try:
    module.apply_updates(text, [{"label": "x", "new": D, "targets": [(2, "f" * 40)]}])
    check("apply: unknown rev exits", None, "SystemExit")
except SystemExit as e:
    check("apply: unknown rev exits", str(e.code), "Could not find the rev line for x")

# A MISSING entry is left out of its repo's targets and reported in a warning.
outdated = {
    "index": 0,
    "label": "o/shared (one)",
    "repo": "o/shared",
    "old": A,
    "new": D,
    "changes": [("modified", "skills/one/SKILL.md")],
}
missing = {"index": 1, "label": "o/shared (two)", "repo": "o/shared", "missing": True}
groups = module.group_by_repo([dict(outdated)], entries, [missing])
check("group with missing: one group", len(groups), 1)
check("group with missing: targets", groups[0]["targets"], [(0, A)])
check("group with missing: warning", "o/shared (two)" in groups[0].get("warning", ""), True)
check("group with missing: label", groups[0]["label"], "o/shared (one)")
groups = module.group_by_repo([dict(outdated)], entries)
check("group: targets", groups[0]["targets"], [(0, A), (1, A)])
check("group: no warning", "warning" in groups[0], False)
check("group: label", groups[0]["label"], "o/shared (one, two)")


def message(*repos: str) -> str:
    return module.commit_message([{"repo": r} for r in repos])


check("commit message: one", message("o/solo"), "chore(agents): bump solo skill rev")
check("commit message: skills repo", message("o/skills"), "chore(agents): bump o skill rev")
check(
    "commit message: three",
    message("o/solo", "o/shared", "o/skills"),
    "chore(agents): bump solo, shared and o skill revs",
)

# check_entry flags an entry whose skill directory is gone at HEAD.
list_files = module.list_files
module.list_files = lambda repo, ref, path: {} if ref == H else {"skills/one/SKILL.md": "sha"}
try:
    line, update = module.check_entry(0, entries[0], H)
finally:
    module.list_files = list_files
check("check_entry missing: line", line.startswith("  MISSING"), True)
check(
    "check_entry missing: update",
    update,
    {"index": 0, "label": "o/shared (one)", "repo": "o/shared", "missing": True},
)

# Candidate archives are patched with real git apply before main mutates the pin.
with tempfile.TemporaryDirectory(prefix="skill-update-preflight-") as temporary:
    directory = Path(temporary)
    data_file = directory / "agent-skills.toml"
    initial = (
        '[[agent_skills]]\nrepo = "owner/demo"\n'
        f'rev = "{A}"\nprefix = "skills"\nnames = ["demo"]\nagents = ["agents"]\n'
    ).encode()
    local_patch = directory / "demo.patch"
    local_patch.write_bytes(b"--- a/SKILL.md\n+++ b/SKILL.md\n@@ -1 +1 @@\n-English\n+Japanese\n")
    candidate = {
        "repo": "owner/demo",
        "label": "owner/demo (demo)",
        "old": A,
        "new": B,
        "targets": [(0, A)],
        "changes": [("modified", "skills/demo/SKILL.md")],
    }
    for content, succeeds in [(b"Upstream changed\n", False), (b"English\n", True)]:
        data_file.write_bytes(initial)
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w:gz") as output:
            member = tarfile.TarInfo("demo-rev/skills/demo/SKILL.md")
            member.size = len(content)
            output.addfile(member, io.BytesIO(content))
        with (
            patch.object(module, "DATA_FILE", data_file),
            patch.object(module, "find_updates", return_value=[candidate]),
            patch.object(module, "patch_path", return_value=local_patch),
            patch.object(module, "urlopen", return_value=io.BytesIO(archive.getvalue())),
            patch.object(module, "git", side_effect=AssertionError("Git must not run on validation failure")),
            patch.object(sys, "argv", ["update_agent_skills.py", "--yes"]),
            contextlib.redirect_stdout(io.TextIOWrapper(io.BytesIO(), encoding="utf-8")),
        ):
            if succeeds:
                # The no-commit path still validates, then updates the pin.
                with (
                    patch.object(sys, "argv", ["update_agent_skills.py", "--yes", "--no-commit"]),
                    patch.object(module, "git", return_value=type("Result", (), {"stdout": ""})()),
                ):
                    module.main()
                check(
                    "preflight success: candidate rev written",
                    data_file.read_bytes(),
                    initial.replace(A.encode(), B.encode()),
                )
            else:
                try:
                    module.main()
                    check("preflight conflict: exits", None, "SystemExit")
                except SystemExit as error:
                    check(
                        "preflight conflict: diagnostic", "Patch validation failed for owner/demo@" in str(error), True
                    )
                check("preflight conflict: original rev retained", data_file.read_bytes(), initial)

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
