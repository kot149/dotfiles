# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Run shellcheck, ruff, nixfmt and oxlint over the repo.

Templates (.chezmoiscripts/*.sh.tmpl, *.nix.tmpl, the opencode plugin
*.ts.tmpl) are rendered with `chezmoi execute-template` once per OS in
RENDER_OS into a temporary directory first; a render identical to an earlier
OS's is checked once. Rendered paths show as `[<os>]/<source path minus
.tmpl>`. A tool that is missing or whose `--version` fails is skipped. Exits 1 if a template fails to
render, nixfmt cannot parse a file, or shellcheck, `ruff check` or oxlint
reports anything; formatting differences from `ruff format --check` and
`nixfmt --check` only report.

Usage:
  uv run --script scripts/lint.py
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SHELL_DIRS = [
    ".chezmoitemplates/agents",
    "dot_claude",
    "dot_claude/hooks",
    "dot_local/bin",
    "private_dot_config/home-manager/pkgs",
    "scripts/macos-launchd",
    "tests",
]
SHEBANGS = ("#!/usr/bin/env bash", "#!/bin/bash", "#!/bin/sh")
# Sourced bash library without a shebang.
SHELL_LIBS = [".chezmoitemplates/agents/python-runner.sh"]
SHELL_TEMPLATES = [".chezmoiscripts/*.sh.tmpl"]

PYTHON_FILES = [
    "scripts/*.py",
    "tests/*.py",
    ".chezmoitemplates/agents/check-package-manager.py",
    "dot_claude/executable_codex-weekly-limit.py",
    "dot_local/share/herdr-plugins/*/executable_*.py",
]

NIX_FILES = [
    "private_dot_config/home-manager/*.nix",
    "private_dot_config/home-manager/pkgs/*.nix",
    "private_dot_config/nix-darwin/*.nix",
]
NIX_TEMPLATES = [
    "private_dot_config/home-manager/*.nix.tmpl",
    "private_dot_config/nix-darwin/*.nix.tmpl",
]

JS_FILES = [
    ".chezmoitemplates/agents/*.js",
    ".chezmoitemplates/agents/textlint-rules/*.js",
    "tests/*.js",
    "private_dot_config/opencode/plugins/*.ts",
]
JS_TEMPLATES = ["private_dot_config/opencode/plugins/*.ts.tmpl"]

# chezmoi data overrides per rendered OS. kernel.osrelease is set because the
# templates read it on Linux (WSL detection) and macOS has no such key.
RENDER_OS = {
    "darwin": {"chezmoi": {"os": "darwin"}},
    "linux": {"chezmoi": {"os": "linux", "kernel": {"osrelease": "generic"}}},
}


class Renderer:
    def __init__(self, tmp: Path):
        self.tmp = tmp
        self.ok = True
        self.chezmoi = shutil.which("chezmoi") is not None
        if not self.chezmoi:
            print("SKIP templates: chezmoi not installed", flush=True)

    def render(self, patterns: list[str]) -> list[Path]:
        """Render each template for every OS; skip empty and duplicate output."""
        if not self.chezmoi:
            return []
        out = []
        for template in glob(patterns):
            seen = set()
            for os_name, data in RENDER_OS.items():
                r = run(
                    ["chezmoi", "--source", str(ROOT), "execute-template"]
                    + ["--override-data", json.dumps(data), "-f", rel(template)]
                )
                if r.returncode != 0:
                    print(f"FAIL render {rel(template)} ({os_name}): {r.stderr.strip()}", flush=True)
                    self.ok = False
                    continue
                if not r.stdout.strip() or r.stdout in seen:
                    continue
                seen.add(r.stdout)
                path = self.tmp / os_name / rel(template).removesuffix(".tmpl")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(r.stdout, encoding="utf-8", newline="\n")
                out.append(path)
        return out

    def show(self, text: str) -> str:
        return re.sub(re.escape(str(self.tmp)) + r"/(\w+)/", r"[\1]/", text)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", **kwargs)


def available(tool: str) -> bool:
    if shutil.which(tool) is None or run([tool, "--version"]).returncode != 0:
        print(f"SKIP {tool}: not installed", flush=True)
        return False
    return True


def glob(patterns: list[str]) -> list[Path]:
    return sorted({p for pattern in patterns for p in ROOT.glob(pattern) if p.is_file()})


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def first_line(path: Path) -> str:
    with path.open(encoding="utf-8", errors="replace") as f:
        return f.readline().rstrip("\r\n")


def shell_sources() -> list[Path]:
    files = []
    for d in SHELL_DIRS:
        for p in sorted((ROOT / d).iterdir()):
            if p.is_file() and not p.name.endswith(".tmpl") and first_line(p) in SHEBANGS:
                files.append(p)
    return files


def count(text: str, pattern: str) -> int:
    return len(re.findall(pattern, text, re.MULTILINE))


def report(
    rd: Renderer, label: str, results: list[subprocess.CompletedProcess[str]], n: int, noun: str = "findings"
) -> bool:
    failed = any(r.returncode != 0 for r in results)
    for r in results:
        sys.stdout.write(rd.show(r.stdout))
        sys.stdout.flush()
        sys.stderr.write(rd.show(r.stderr))
        sys.stderr.flush()
    print(f"{label}: {max(n, 1) if failed else n} {noun}", flush=True)
    return not failed


def lint_shell(rd: Renderer) -> bool:
    if not available("shellcheck"):
        return True
    # No --rcfile: the preinstalled shellcheck on ubuntu-latest (0.9.x) rejects
    # it. Every shellcheck run executes with cwd=ROOT, so ./.shellcheckrc is
    # picked up from the working directory anyway.
    rc = ["-S", "warning"]
    files = [*map(rel, shell_sources()), *map(str, rd.render(SHELL_TEMPLATES))]
    results = [run(["shellcheck", *rc, *files]), run(["shellcheck", *rc, "-s", "bash", *SHELL_LIBS])]
    n = sum(count(r.stdout, r"\^[-^]* SC\d{4} ") for r in results)
    return report(rd, "shellcheck", results, n)


def lint_python(rd: Renderer) -> bool:
    if not available("ruff"):
        return True
    files = [rel(p) for p in glob(PYTHON_FILES)]
    r = run(["ruff", "check", "--output-format", "concise", *files])
    ok = report(rd, "ruff check", [r], count(r.stdout, r"^\S+:\d+:\d+: "))
    r = run(["ruff", "format", "--check", *files])
    m = re.search(r"^(\d+) files? would be reformatted", r.stdout, re.MULTILINE)
    report(rd, "ruff format", [r], int(m[1]) if m else 0, "files would be reformatted")
    return ok


def lint_nix(rd: Renderer) -> bool:
    if not available("nixfmt"):
        return True
    unformatted = broken = 0
    for f in [*glob(NIX_FILES), *rd.render(NIX_TEMPLATES)]:
        r = run(["nixfmt", "--check", rel(f) if f.is_relative_to(ROOT) else str(f)])
        if r.returncode == 0:
            continue
        sys.stderr.write(rd.show(r.stderr))
        sys.stderr.flush()
        if r.stderr.strip().endswith(": not formatted"):
            unformatted += 1
        else:
            broken += 1
    print(f"nixfmt: {unformatted} files not formatted, {broken} parse errors", flush=True)
    return broken == 0


def lint_js(rd: Renderer) -> bool:
    if not available("oxlint"):
        return True
    files = [*map(rel, glob(JS_FILES)), *map(str, rd.render(JS_TEMPLATES))]
    r = run(["oxlint", "-f", "unix", "--deny-warnings", *files])
    return report(rd, "oxlint", [r], count(r.stdout, r"^\S+:\d+:\d+: "))


def main() -> int:
    with tempfile.TemporaryDirectory() as d:
        rd = Renderer(Path(d))
        ok = lint_shell(rd)
        ok &= lint_python(rd)
        ok &= lint_nix(rd)
        ok &= lint_js(rd)
        ok &= rd.ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
