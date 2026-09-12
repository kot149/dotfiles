#!/usr/bin/env python3
"""Adopt pre-existing dotfiles into mise management without data loss.

`mise bootstrap dotfiles apply` refuses to overwrite existing regular files
(e.g. files previously deployed by chezmoi as copies), even when the content
is identical. This one-shot migration, run as `mise run migrate-from-chezmoi`:

1. Lists every entry that is not in its desired state.
2. Moves any existing path aside into ~/.local/share/mise-backup/<timestamp>/.
3. Applies those targets (on failure, moved-aside paths are restored).
4. Deletes backups whose content is byte-identical to the applied result and
   reports the rest for manual review.

Re-running is safe: entries already in their desired state are skipped.
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

DOTFILES_HOME = os.path.expanduser("~")


def target_path(target):
    if target.startswith("~/"):
        return os.path.join(DOTFILES_HOME, target[2:])
    return target


def main():
    setup = subprocess.run(["uv", "run", "--script", str(Path(__file__).with_name("setup.py")), "--migrate"])
    if setup.returncode != 0:
        return setup.returncode
    proc = subprocess.run(
        ["mise", "bootstrap", "dotfiles", "status", "-J"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        return 1
    try:
        files = json.loads(proc.stdout)["files"]
    except (json.JSONDecodeError, KeyError) as exc:
        print(f"cannot parse dotfiles status: {exc}", file=sys.stderr)
        return 1

    pending = [f for f in files if f.get("state") != "applied"]
    if not pending:
        print("everything already applied; nothing to migrate.")
        return 0

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root = os.path.join(DOTFILES_HOME, ".local", "share", "mise-backup", stamp)
    backups = {}  # target -> backup path (only when something was moved aside)
    try:
        for entry in pending:
            tpath = target_path(entry["target"])
            if os.path.lexists(tpath):
                rel = os.path.relpath(tpath, DOTFILES_HOME)
                bpath = os.path.join(backup_root, rel)
                os.makedirs(os.path.dirname(bpath) or backup_root, exist_ok=True)
                shutil.move(tpath, bpath)
                backups[entry["target"]] = bpath
                print(f"backup: {entry['target']} -> {bpath}")

        subprocess.run(
            ["mise", "bootstrap", "dotfiles", "apply"]
            + [f["target"] for f in pending], check=True
        )
    except (OSError, subprocess.CalledProcessError, KeyboardInterrupt) as exc:
        print(f"migration failed ({exc}); restoring backups from {backup_root}", file=sys.stderr)
        for target, bpath in backups.items():
            tpath = target_path(target)
            try:
                if os.path.lexists(tpath):
                    if os.path.isdir(tpath) and not os.path.islink(tpath):
                        shutil.rmtree(tpath)
                    else:
                        os.remove(tpath)
                parent = os.path.dirname(tpath)
                if parent:
                    os.makedirs(parent, exist_ok=True)
                shutil.move(bpath, tpath)
                print(f"restored: {bpath} -> {target}")
            except OSError as exc:
                print(f"cannot restore {target} from {bpath}: {exc}", file=sys.stderr)
        return 1

    kept = []
    for target, bpath in backups.items():
        tpath = target_path(target)
        try:
            with open(bpath, "rb") as fh:
                old = fh.read()
            with open(tpath, "rb") as fh:
                new = fh.read()
        except OSError:
            kept.append((target, bpath))  # dir/symlink oddity: keep for review
            continue
        if old == new:
            os.remove(bpath)
        else:
            kept.append((target, bpath))
    # Prune backup dirs left empty by identical-file cleanup.
    for dirpath, dirnames, filenames in os.walk(backup_root, topdown=False):
        if not dirnames and not filenames:
            os.rmdir(dirpath)

    if kept:
        print("review differing backups (kept):")
        for target, bpath in kept:
            print(f"  {target}: {bpath}")
    else:
        print("no differing backups; migration is clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
