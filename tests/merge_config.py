# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Fixture tests for .chezmoitemplates/agents/merge-config.tmpl.

  uv run --no-python-downloads --script tests/merge_config.py

Each directory under tests/fixtures/merge-config/ is one case: managed + current
-> expected, all .json, .toml or .yaml. The template is called with "hooks" true
unless the case holds an empty no-hooks file. Every case is rendered a second
time with expected as current, which must give expected again (a re-apply
changes nothing). Outputs are compared as parsed objects serialized with sorted
keys, so key order does not matter but list order and value types do. YAML is
parsed (and serialized) through chezmoi's own fromYaml/toYaml via
execute-template, so the comparison sees exactly what the template sees without
adding a PyYAML dependency.
"""
import difflib
import json
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures" / "merge-config"

failures = 0
checks = 0


def check(label: str, ok: bool, detail: str) -> None:
    global checks, failures
    checks += 1
    print(f"{'OK' if ok else 'FAIL'} {label}")
    if not ok:
        failures += 1
        print(detail)


def parse(text: str, fmt: str) -> object:
    if fmt == "yaml":
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "in.yaml"
            path.write_text(text, encoding="utf-8")
            driver = Path(tmp) / "driver.tmpl"
            driver.write_text(
                f'{{{{ (include "{path.as_posix()}") | fromYaml | toJson }}}}',
                encoding="utf-8",
            )
            result = subprocess.run(
                ["chezmoi", "execute-template", "-f", driver.as_posix()],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
        if result.returncode != 0:
            raise RuntimeError(f"exit status {result.returncode}: {result.stderr.strip()}")
        return json.loads(result.stdout)
    return tomllib.loads(text) if fmt == "toml" else json.loads(text)


def dump(value: object) -> str:
    # json.dumps keeps 1, 1.0 and true apart, unlike == on the parsed values.
    return json.dumps(value, indent=2, sort_keys=True)


def render(case: Path, fmt: str, current: Path) -> object:
    args = [
        f'"managed" (include "{(case / f"managed.{fmt}").as_posix()}")',
        f'"current" (include "{current.as_posix()}")',
        f'"format" "{fmt}"',
    ]
    if not (case / "no-hooks").exists():
        args.append('"hooks" true')
    with tempfile.TemporaryDirectory() as tmp:
        driver = Path(tmp) / "driver.tmpl"
        driver.write_text(
            f'{{{{ template "agents/merge-config.tmpl" (dict {" ".join(args)}) }}}}\n',
            encoding="utf-8",
        )
        result = subprocess.run(
            ["chezmoi", "execute-template", "--source", ROOT.as_posix(), "-f", driver.as_posix()],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    if result.returncode != 0:
        raise RuntimeError(f"exit status {result.returncode}: {result.stderr.strip()}")
    return parse(result.stdout, fmt)


def compare(label: str, expected: object, actual: object) -> None:
    want, got = dump(expected), dump(actual)
    diff = difflib.unified_diff(
        want.splitlines(keepends=True), got.splitlines(keepends=True), "expected", "actual"
    )
    check(label, want == got, "".join(diff))


for case in sorted(p for p in FIXTURES.iterdir() if p.is_dir()):
    fmt = "toml" if (case / "managed.toml").exists() else "yaml" if (case / "managed.yaml").exists() else "json"
    expected_path = case / f"expected.{fmt}"
    try:
        expected = parse(expected_path.read_text(encoding="utf-8"), fmt)
        compare(case.name, expected, render(case, fmt, case / f"current.{fmt}"))
        compare(f"{case.name} (re-apply)", expected, render(case, fmt, expected_path))
    except Exception as e:
        check(case.name, False, f"  {type(e).__name__}: {e}")

if checks == 0:
    check("fixtures", False, f"  no cases under {FIXTURES}")
print(f"{checks - failures}/{checks} passed")
if failures:
    sys.exit(1)
