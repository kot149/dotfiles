# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Bump the pinned revs in .chezmoidata/agent-skills.toml.

An entry counts as outdated only when one of its skill directories differs
between the pinned rev and the upstream default branch HEAD (compared by blob
SHA), so commits that touch other parts of the repo are ignored.
Entries that share a `repo` are bumped together, so one repository is never
pinned at two revs.
Accepted bumps are committed as one commit touching only the data file.
Requires the `gh` CLI.

Usage:
  uv run --script scripts/update_agent_skills.py               # review, apply and commit interactively
  uv run --script scripts/update_agent_skills.py --check       # report only; exit 1 if outdated
  uv run --script scripts/update_agent_skills.py --yes         # apply and commit every update without asking
  uv run --script scripts/update_agent_skills.py --no-commit   # apply without committing
"""
import argparse
import difflib
import json
import re
import subprocess
import sys
import tomllib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DATA_FILE = Path(__file__).resolve().parent.parent / ".chezmoidata" / "agent-skills.toml"
BLOCK_HEADER = "[[agent_skills]]"


MAX_LISTED_FILES = 30


def gh(path: str, raw: bool = False) -> str | None:
    """Return the response body, or None on 404."""
    cmd = ["gh", "api", path]
    if raw:
        cmd[2:2] = ["-H", "Accept: application/vnd.github.raw"]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        stderr = proc.stderr.decode(errors="replace")
        if "HTTP 404" in stderr:
            return None
        sys.exit(f"gh api {path} failed:\n{stderr}")
    return proc.stdout.decode(errors="replace")


def skill_dirs(entry: dict) -> list[str]:
    prefix = entry.get("prefix", "")
    if entry.get("flat", False):
        return [prefix]
    return [f"{prefix}/{name}" if prefix else name for name in entry["names"]]


def list_files(repo: str, ref: str, path: str) -> dict[str, str]:
    """Map each file under path at ref to its blob SHA (empty if path does not exist)."""
    body = gh(f"repos/{repo}/git/trees/{ref}:{path}?recursive=1" if path else f"repos/{repo}/git/trees/{ref}?recursive=1")
    if body is None:
        return {}
    tree = json.loads(body)
    if tree["truncated"]:
        sys.exit(f"Tree listing of {repo}:{path} at {ref} is truncated")
    base = path + "/" if path else ""
    return {base + e["path"]: e["sha"] for e in tree["tree"] if e["type"] == "blob"}


def under(files: dict[str, str], directory: str) -> dict[str, str]:
    if not directory:
        return files
    return {path: sha for path, sha in files.items() if path.startswith(directory + "/")}


def diff_files(old: dict[str, str], new: dict[str, str]) -> list[tuple[str, str]]:
    changes = []
    for path in sorted(old.keys() | new.keys()):
        if path not in old:
            changes.append(("added", path))
        elif path not in new:
            changes.append(("removed", path))
        elif old[path] != new[path]:
            changes.append(("modified", path))
    return changes


def check_entry(index: int, entry: dict, head: str) -> tuple[str, dict | None]:
    """Return the status line for the entry and its update, if any."""
    repo, rev = entry["repo"], entry["rev"]
    label = f"{repo} ({', '.join(entry['names'])})"
    if head == rev:
        return f"  up to date  {label}", None

    # One recursive listing of prefix per ref covers every skill dir in the entry.
    prefix = entry.get("prefix", "")
    old_files, new_files = list_files(repo, rev, prefix), list_files(repo, head, prefix)
    changes, missing = [], []
    for d in skill_dirs(entry):
        new = under(new_files, d)
        if not new:
            missing.append(d)
            continue
        changes += diff_files(under(old_files, d), new)
    if missing:
        return f"  MISSING     {label}: not found at HEAD: {', '.join(missing)} (left unchanged)", None
    if not changes:
        return f"  up to date  {label} (other paths changed upstream)", None
    return f"  outdated    {label}", {"index": index, "label": label, "repo": repo, "old": rev, "new": head, "changes": changes}


def group_by_repo(updates: list[dict], entries: list[dict]) -> list[dict]:
    """Merge the updates of one repo into a single update covering every entry
    of that repo, so a repository is never left pinned at two revs."""
    grouped: dict[str, dict] = {}
    for update in updates:
        group = grouped.get(update["repo"])
        if group is None:
            grouped[update["repo"]] = dict(update, labels=[update["label"]])
            continue
        group["labels"].append(update["label"])
        group["changes"] += update["changes"]
    for repo, group in grouped.items():
        group["targets"] = [(i, e["rev"]) for i, e in enumerate(entries) if e["repo"] == repo]
        names = ", ".join(sorted({n for e in entries if e["repo"] == repo for n in e["names"]}))
        group["label"] = f"{repo} ({names})"
    return list(grouped.values())


def find_updates(entries: list[dict]) -> list[dict]:
    with ThreadPoolExecutor(max_workers=8) as pool:
        repos = sorted({e["repo"] for e in entries})
        heads = dict(zip(repos, pool.map(lambda r: json.loads(gh(f"repos/{r}/commits/HEAD"))["sha"], repos)))
        results = list(pool.map(lambda ie: check_entry(ie[0], ie[1], heads[ie[1]["repo"]]), enumerate(entries)))

    updates = []
    for line, update in results:
        print(line)
        if update:
            updates.append(update)
    return group_by_repo(updates, entries)


def print_patch(update: dict, status: str, path: str) -> None:
    def read(ref: str) -> list[str]:
        body = gh(f"repos/{update['repo']}/contents/{path}?ref={ref}", raw=True)
        return body.splitlines(keepends=True) if body else []

    old = [] if status == "added" else read(update["old"])
    new = [] if status == "removed" else read(update["new"])
    for line in difflib.unified_diff(old, new, f"a/{path}", f"b/{path}"):
        print("      " + line, end="" if line.endswith("\n") else "\n")


def show_update(update: dict, with_patch: bool) -> None:
    changes = update["changes"]
    print(f"\n== {update['label']}: {len(changes)} file(s) changed")
    print(f"   https://github.com/{update['repo']}/compare/{update['old']}...{update['new']}")
    if len(update["targets"]) > 1:
        print(f"   bumps all {len(update['targets'])} entries of this repo together")
    listed = changes if with_patch else changes[:MAX_LISTED_FILES]
    for status, path in listed:
        print(f"   {status:<9} {path}")
        if with_patch:
            print_patch(update, status, path)
    if len(listed) < len(changes):
        print(f"   ... and {len(changes) - len(listed)} more")


def confirm(update: dict) -> bool:
    while True:
        answer = input("   Update? [y]es / [n]o / [d]iff: ").strip().lower()
        if answer in ("y", "yes"):
            return True
        if answer in ("", "n", "no"):
            return False
        if answer in ("d", "diff"):
            show_update(update, with_patch=True)


def apply_updates(text: str, updates: list[dict]) -> str:
    """Rewrite the rev line inside each target block, keeping the rest of the file as is."""
    head, *blocks = text.split(BLOCK_HEADER)
    for update in updates:
        for index, old in update["targets"]:
            new_block, count = re.subn(
                rf'^rev = "{old}"(?=\r?$)', f'rev = "{update["new"]}"', blocks[index], count=1, flags=re.M
            )
            if count != 1:
                sys.exit(f"Could not find the rev line for {update['label']}")
            blocks[index] = new_block
    return BLOCK_HEADER.join([head, *blocks])


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(DATA_FILE.parent), *args], capture_output=True, text=True)


def commit_message(updates: list[dict]) -> str:
    # Generic repo names like "mattpocock/skills" read better as the owner.
    names = [owner if name == "skills" else name for owner, name in (u["repo"].split("/") for u in updates)]
    joined = names[0] if len(names) == 1 else f"{', '.join(names[:-1])} and {names[-1]}"
    return f"chore(agents): bump {joined} skill rev{'' if len(names) == 1 else 's'}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="report only; exit 1 if any entry is outdated")
    mode.add_argument("--yes", action="store_true", help="apply every update without asking")
    parser.add_argument("--no-commit", action="store_true", help="leave the bumped revs uncommitted")
    args = parser.parse_args()

    # Upstream diffs can hold characters the Windows console code page lacks.
    sys.stdout.reconfigure(errors="replace")
    # Bytes I/O keeps UTF-8 and the checked-out line endings on Windows too.
    text = DATA_FILE.read_bytes().decode("utf-8")
    entries = tomllib.loads(text)["agent_skills"]
    if text.count(BLOCK_HEADER) != len(entries):
        sys.exit(f"Expected one {BLOCK_HEADER} line per entry in {DATA_FILE}")

    updates = find_updates(entries)
    if not updates:
        return

    selected = []
    for update in updates:
        show_update(update, with_patch=False)
        if args.check:
            continue
        if args.yes or confirm(update):
            selected.append(update)

    if args.check:
        sys.exit(1)
    if not selected:
        return
    # Committing a file that already had local edits would sweep them into the bump commit.
    dirty = bool(git("status", "--porcelain", "--", DATA_FILE.name).stdout.strip())
    DATA_FILE.write_bytes(apply_updates(text, selected).encode("utf-8"))
    print(f"\nUpdated {len(selected)} entr{'y' if len(selected) == 1 else 'ies'} in {DATA_FILE.name}.")
    if args.no_commit:
        return
    if dirty:
        print(f"Not committing: {DATA_FILE.name} had uncommitted changes before the update.")
        return
    message = commit_message(selected)
    proc = git("commit", "-m", message, "--", DATA_FILE.name)
    if proc.returncode != 0:
        sys.exit(f"git commit failed:\n{proc.stdout}{proc.stderr}")
    print(f"Committed: {message}")


if __name__ == "__main__":
    main()
