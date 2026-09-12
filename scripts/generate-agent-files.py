#!/usr/bin/env python3
"""Regenerate checked-in agent permission files from config/*.toml.

Single source of truth for the shell-allow expansion logic shared by the
Claude settings, Codex rules, opencode, and Antigravity permission outputs. Outputs in generated/ are checked in; [dotfiles] and
merge tasks consume them directly (no template rendering at apply time).

Usage:
    scripts/generate-agent-files.py           # regenerate generated/
    scripts/generate-agent-files.py --check    # exit 1 if generated/ is stale
"""
import difflib
import json
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config"
TEMPLATES = ROOT / "templates"
GENERATED = ROOT / "generated"

SCRIPT_PREFIXES = ["npm run", "pnpm run", "pnpm", "yarn run", "yarn", "bun run", "bun"]
BIN_PREFIXES = [
    "npx", "pnpm exec", "pnpm dlx", "pnpm", "yarn exec", "yarn dlx", "yarn",
    "bunx", "bun x", "bun",
]
ABS_DIRS = ["/bin", "/usr/bin"]
ABS_BINS = [
    "ls", "cat", "find", "grep", "head", "tail", "wc", "stat", "file", "du",
    "df", "sort", "uniq", "cut", "basename", "dirname", "realpath", "date",
    "which",
]


def load_toml(name):
    with open(CONFIG / name, "rb") as f:
        return tomllib.load(f)


def expand_shell_allow(perms):
    """Shared base list: raw allow + js-script/js-bin cross products."""
    shell_allow = list(perms["agent_shell_allow"])
    for script in perms["agent_shell_allow_js_scripts"]:
        for prefix in SCRIPT_PREFIXES:
            shell_allow.append(f"{prefix} {script} *")
    for binary in perms["agent_shell_allow_js_bins"]:
        shell_allow.append(f"{binary} *")
        for prefix in BIN_PREFIXES:
            shell_allow.append(f"{prefix} {binary} *")
    return shell_allow


def with_abs_variants(shell_allow):
    """Mirror bare forms reachable by absolute path (Claude settings only)."""
    out = list(shell_allow)
    for binary in ABS_BINS:
        if f"{binary} *" in out:
            for d in ABS_DIRS:
                out.append(f"{d}/{binary} *")
    return out


def pretty_block(value):
    """Indent-4 JSON block matching the old `toPrettyJson | indent 4 | trim`."""
    raw = json.dumps(value, indent=2, ensure_ascii=False)
    lines = raw.split("\n")
    return lines[0] + "\n" + "\n".join("    " + line for line in lines[1:])


def claude_permissions(perms):
    shell_allow = with_abs_variants(expand_shell_allow(perms))
    allow = list(perms["agent_plain_allow"])
    for entry in shell_allow:
        allow.append(f"Bash({entry})")
        allow.append(f"Bash(rtk {entry})")
        allow.append(f"Bash(rtk proxy {entry})")
        if entry.endswith(" *"):
            bare = entry[:-2]
            allow.append(f"Bash({bare})")
            allow.append(f"Bash(rtk {bare})")
            allow.append(f"Bash(rtk proxy {bare})")
        if entry.startswith(("pnpm ", "npm ", "yarn ")):
            allow.append(f"Bash(corepack {entry})")
    allow.extend(f"Bash({e})" for e in perms["agent_shell_allow_no_rtk"])
    deny = ["EnterPlanMode"]
    for rule in perms["agent_shell_deny"]:
        deny.append(f"Bash({rule})")
        deny.append(f"Bash(rtk {rule})")
        deny.append(f"Bash(rtk proxy {rule})")
        if rule.split(" ")[0] in ABS_BINS:
            for d in ABS_DIRS:
                deny.append(f"Bash({d}/{rule})")
                deny.append(f"Bash(rtk {d}/{rule})")
                deny.append(f"Bash(rtk proxy {d}/{rule})")
    return allow, deny


def opencode_bash_rules(perms):
    rules = {"*": "ask"}
    for entry in expand_shell_allow(perms):
        rules[entry] = "allow"
        rules[f"rtk {entry}"] = "allow"
        if entry.endswith(" *"):
            bare = entry[:-2]
            rules[bare] = "allow"
            rules[f"rtk {bare}"] = "allow"
        if entry.startswith(("pnpm ", "npm ", "yarn ")):
            rules[f"corepack {entry}"] = "allow"
    for entry in perms["agent_shell_allow_no_rtk"]:
        rules[entry] = "allow"
    for rule in perms["agent_shell_deny"]:
        rules[rule] = "deny"
        rules[f"rtk {rule}"] = "deny"
    return rules


def antigravity_permissions(perms):
    allow_set = set()
    for entry in expand_shell_allow(perms):
        allow_set.add(entry)
        allow_set.add(f"rtk {entry}")
        if entry.endswith(" *"):
            bare = entry[:-2]
            allow_set.add(bare)
            allow_set.add(f"rtk {bare}")
        if entry.startswith(("pnpm ", "npm ", "yarn ")):
            allow_set.add(f"corepack {entry}")
    allow_set.update(perms["agent_shell_allow_no_rtk"])
    allow = sorted(f"command({key})" for key in allow_set)
    deny_set = set()
    for rule in perms["agent_shell_deny"]:
        deny_set.add(rule)
        deny_set.add(f"rtk {rule}")
    deny = sorted(f"command({key})" for key in deny_set)
    return allow, deny


def codex_pattern(pattern):
    tokens = [t.strip("*") for t in pattern.split(" ")]
    tokens = [t for t in tokens if t]
    return json.dumps(tokens, separators=(",", ":"), ensure_ascii=False)


def codex_rules(perms):
    lines = []
    for rule in perms["agent_shell_deny"]:
        lines.append(
            f'prefix_rule(pattern={codex_pattern(rule)}, decision="forbidden", '
            'justification="Blocked by shared agent deny list")'
        )
        lines.append(
            f'prefix_rule(pattern={codex_pattern("rtk " + rule)}, decision="forbidden", '
            'justification="Blocked by shared agent deny list")'
        )
    for entry in expand_shell_allow(perms):
        lines.append(
            f'prefix_rule(pattern={codex_pattern(entry)}, decision="allow")'
        )
        lines.append(
            f'prefix_rule(pattern={codex_pattern("rtk " + entry)}, decision="allow")'
        )
    for entry in perms["agent_shell_allow_no_rtk"]:
        lines.append(
            f'prefix_rule(pattern={codex_pattern(entry)}, decision="allow")'
        )
    return "\n".join(lines) + "\n"


def fill_skeleton(path, replacements):
    text = path.read_text(encoding="utf-8")
    for token, block in replacements.items():
        text = text.replace(token, block)
    return text


def build():
    perms = load_toml("agent-permissions.toml")
    caches = load_toml("nix-binary-caches.toml")["nix_substituters"]

    allow, deny = claude_permissions(perms)
    settings = fill_skeleton(
        TEMPLATES / "claude/settings.json.skel",
        {"__ALLOW__": pretty_block(allow), "__DENY__": pretty_block(deny)},
    )
    bash_rules = opencode_bash_rules(perms)
    # Go template `range` over a map emits keys sorted; match that order.
    opencode = fill_skeleton(
        TEMPLATES / "opencode/opencode.json.skel",
        {
            "__BASHRULES__": pretty_block(
                {k: bash_rules[k] for k in sorted(bash_rules)}
            )
        },
    )
    ag_allow, ag_deny = antigravity_permissions(perms)
    antigravity = fill_skeleton(
        TEMPLATES / "antigravity/settings.json.skel",
        {"__ALLOW__": pretty_block(ag_allow), "__DENY__": pretty_block(ag_deny)},
    )
    urls = "\n".join(f'        "{c["url"]}"' for c in caches) + "\n"
    keys = "\n".join(f'        "{c["key"]}"' for c in caches) + "\n"

    return {
        GENERATED / "claude-settings.json": settings + "\n",
        GENERATED / "opencode.json": opencode + "\n",
        GENERATED / "antigravity-settings.json": antigravity + "\n",
        GENERATED / "codex-rules": codex_rules(perms),
        GENERATED / "nix-substituters-urls.nix": urls,
        GENERATED / "nix-substituters-keys.nix": keys,
    }


def main():
    check = "--check" in sys.argv
    outputs = build()
    failed = False
    for path, content in outputs.items():
        if check:
            current = path.read_text(encoding="utf-8") if path.exists() else ""
            if current != content:
                failed = True
                print(f"STALE: {path.relative_to(ROOT)}")
                for line in difflib.unified_diff(
                    current.splitlines(),
                    content.splitlines(),
                    str(path.relative_to(ROOT)),
                    "regenerated",
                    lineterm="",
                ):
                    print(line)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            print(f"wrote {path.relative_to(ROOT)}")
    if check and failed:
        print("Run scripts/generate-agent-files.py to refresh generated/.")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
