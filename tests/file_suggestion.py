# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for dot_claude/executable_file-suggestion.sh, Claude Code's @-mention picker.

  uv run --no-python-downloads --script tests/file_suggestion.py

Runs the script in a scratch tree with its own $HOME and cache. Skipped when fd,
fzf or jq is missing.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "dot_claude" / "executable_file-suggestion.sh"

BASH = shutil.which("bash")
if BASH is None:
    sys.exit("bash not found on PATH")

missing = [tool for tool in ("fd", "fzf", "jq") if shutil.which(tool) is None]
if missing:
    print(f"skip: {', '.join(missing)} not found on PATH")
    sys.exit(0)


def run(query: str, cwd: Path, env: dict[str, str]) -> list[str]:
    out = subprocess.run(
        [BASH, str(SCRIPT)],
        input=json.dumps({"query": query}),
        capture_output=True,
        text=True,
        cwd=cwd,
        env=env,
        check=True,
    ).stdout
    return [line for line in out.splitlines() if line]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        repo = home / "repo"
        other = home / "other"
        for d in (
            repo / ".git",
            repo / ".github" / "workflows",
            repo / "notes",
            repo / "src",
            other / ".claude",
            other / ".direnv",
            other / "visible",
        ):
            d.mkdir(parents=True)
        (repo / ".gitignore").write_text("notes/\n")
        (repo / "notes" / "todo.md").write_text("")
        (repo / "src" / "main.py").write_text("")
        (other / ".gitignore").write_text(".claude/\n")
        (other / ".envrc").write_text("")

        env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CACHE_HOME": str(Path(tmp) / "cache"),
        }

        # (query, cwd, path that must be listed, path that must not be listed)
        cases: list[tuple[str, Path, str, str | None]] = [
            ("~/other/.clau", repo, "~/other/.claude/", None),
            ("~/other/", repo, "~/other/.envrc", None),
            ("~/other/vis", repo, "~/other/visible/", "~/other/.claude/"),
            (f"{other}/.dir", repo, f"{other}/.direnv/", None),
            ("../other/.cl", repo, "../other/.claude/", None),
            ("./src/ma", repo, "./src/main.py", None),
            ("~/missing/x", repo, None, None),
            (".github", repo, ".github/workflows/", None),
            ("todo", repo, "notes/todo.md", None),
            ("main", repo, "src/main.py", ".git/"),
        ]

        failures = 0
        for query, cwd, want, unwanted in cases:
            got = run(query, cwd, env)
            ok = (want in got if want else not got) and unwanted not in got
            if not ok:
                failures += 1
                print(f"FAIL {query!r}: want {want!r}, not {unwanted!r}, got {got}")

    print(f"{len(cases) - failures}/{len(cases)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
