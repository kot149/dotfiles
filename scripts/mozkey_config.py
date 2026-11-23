# /// script
# requires-python = ">=3.11"
# dependencies = ["grpcio-tools>=1.66"]
# ///
"""
Sync the Mozkey settings kept in ~/.config/mozkey with Mozkey's config1.db.

config.textproto lists the managed Config fields in protobuf text format, and
roman.tsv holds custom_roman_table. Fields not listed keep their current value,
so per-OS settings (fonts, colors, metadata) stay local.

Usage:
  uv run --script scripts/mozkey_config.py apply     # write ~/.config/mozkey into config1.db
  uv run --script scripts/mozkey_config.py capture   # write config1.db back into the source dir
  uv run --script scripts/mozkey_config.py dump      # print every field of config1.db
"""

import argparse
import importlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from google.protobuf import text_format
from grpc_tools import protoc

ROOT = Path(__file__).resolve().parent.parent
PROTO = ROOT / "scripts" / "mozkey" / "config.proto"
SOURCE_DIR = ROOT / "private_dot_config" / "mozkey"
MANAGED_DIR = Path.home() / ".config" / "mozkey"
TEXTPROTO = "config.textproto"
ROMAN = "roman.tsv"


def profile_dir() -> Path:
    if sys.platform == "win32":
        return Path(os.environ["USERPROFILE"]) / "AppData" / "LocalLow" / "Mozc"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Mozc"
    xdg = os.environ.get("XDG_CONFIG_HOME")
    return Path(xdg) / "mozkey" if xdg else Path.home() / ".config" / "mozkey"


def load_config_class(workdir: str):
    rc = protoc.main(["protoc", f"-I{PROTO.parent}", f"--python_out={workdir}", str(PROTO)])
    if rc != 0:
        sys.exit(f"protoc failed for {PROTO}")
    sys.path.insert(0, workdir)
    return importlib.import_module("config_pb2").Config


def read_managed(config_cls, directory: Path):
    managed = config_cls()
    textproto = directory / TEXTPROTO
    if textproto.exists():
        text_format.Parse(textproto.read_text(encoding="utf-8"), managed)
    roman = directory / ROMAN
    if roman.exists():
        managed.custom_roman_table = roman.read_bytes()
    return managed


def restart_server() -> None:
    if sys.platform == "win32":
        cmd = ["taskkill", "/F", "/IM", "mozc_server.exe"]
    elif sys.platform == "darwin":
        cmd = ["pkill", "-x", "MozcConverter"]
    else:
        cmd = ["pkill", "-x", "mozc_server"]
    # The IME client starts the server again on the next key input.
    if subprocess.run(cmd, capture_output=True).returncode == 0:
        print("Restarted the Mozkey server to load the new config.")


def apply(config_cls) -> None:
    db = profile_dir() / "config1.db"
    if not db.exists():
        print(f"{db} does not exist; skipping Mozkey config.")
        return
    managed = read_managed(config_cls, MANAGED_DIR)
    original = db.read_bytes()
    config = config_cls.FromString(original)
    for field, _ in managed.ListFields():
        config.ClearField(field.name)
    config.MergeFrom(managed)
    updated = config.SerializeToString()
    if updated == original:
        print("Mozkey config is up to date.")
        return
    # Rewrite in place: on Windows the file carries an ACL that lets
    # AppContainer apps read it, and replacing the file would drop it.
    with db.open("r+b") as f:
        f.write(updated)
        f.truncate()
    print(f"Updated {db}")
    restart_server()


def capture(config_cls) -> None:
    db = profile_dir() / "config1.db"
    config = config_cls.FromString(db.read_bytes())
    current = read_managed(config_cls, SOURCE_DIR)
    names = [field.name for field, _ in current.ListFields() if field.name != "custom_roman_table"]
    subset = config_cls()
    for name in names:
        descriptor = config.DESCRIPTOR.fields_by_name[name]
        if descriptor.is_repeated:
            getattr(subset, name).extend(getattr(config, name))
        elif descriptor.message_type:
            getattr(subset, name).CopyFrom(getattr(config, name))
        else:
            setattr(subset, name, getattr(config, name))
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    (SOURCE_DIR / TEXTPROTO).write_text(
        text_format.MessageToString(subset, as_utf8=True), encoding="utf-8", newline="\n"
    )
    if config.custom_roman_table:
        (SOURCE_DIR / ROMAN).write_bytes(config.custom_roman_table)
    print(f"Wrote {len(names)} fields and the roman table to {SOURCE_DIR}")


def dump(config_cls) -> None:
    config = config_cls.FromString((profile_dir() / "config1.db").read_bytes())
    config.ClearField("custom_roman_table")
    sys.stdout.reconfigure(encoding="utf-8")
    print(text_format.MessageToString(config, as_utf8=True), end="")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["apply", "capture", "dump"])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as workdir:
        config_cls = load_config_class(workdir)
        {"apply": apply, "capture": capture, "dump": dump}[args.command](config_cls)


if __name__ == "__main__":
    main()
