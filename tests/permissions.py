# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the Bash allow / deny rules rendered from .chezmoidata/agent-permissions.toml.

  uv run --no-python-downloads --script tests/permissions.py

Renders the Claude Code settings template and matches commands against its
Bash(...) rules, treating `*` as any run of characters (spaces and newlines
included). Approximates Claude Code's matcher; it does not model its prefix rules.

Also renders the Codex rules and matches commands against their prefix_rule
patterns as argv prefixes, checking that Codex never blocks or allows more than
the Claude rules do, and renders the opencode bash rules for the checks
that differ there.
"""
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / ".chezmoitemplates" / "claude" / "settings.json.tmpl"
CODEX_TEMPLATE = ROOT / "dot_codex" / "rules" / "default.rules.tmpl"
OPENCODE_TEMPLATE = ROOT / ".chezmoitemplates" / "opencode" / "opencode.json.tmpl"


def bash_patterns(rules: list[str]) -> list[re.Pattern[str]]:
    patterns = []
    for rule in rules:
        if not (rule.startswith("Bash(") and rule.endswith(")")):
            continue
        pattern = rule[len("Bash(") : -1]
        regex = "^" + ".*".join(re.escape(part) for part in pattern.split("*")) + "$"
        patterns.append(re.compile(regex, re.DOTALL))
    return patterns


def render(template: Path) -> str:
    return subprocess.run(
        ["chezmoi", "--source", str(ROOT), "execute-template", "-f", str(template)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout


permissions = json.loads(render(TEMPLATE))["permissions"]
DENY_PATTERNS = [r[len("Bash(") : -1] for r in permissions["deny"] if r.startswith("Bash(")]
ALLOW = bash_patterns(permissions["allow"])
DENY = bash_patterns(permissions["deny"])

CODEX_RULES: dict[str, list[list[str]]] = {"allow": [], "forbidden": []}
for line in render(CODEX_TEMPLATE).splitlines():
    match = re.match(r'prefix_rule\(pattern=(\[.*?\]), decision="(\w+)"', line)
    if match:
        CODEX_RULES[match[2]].append(json.loads(match[1]))


def opencode_regex(pattern: str) -> re.Pattern[str]:
    """opencode's wildcard match: `*` is any run of characters, a trailing ` *` is `( .*)?`."""
    optional = pattern.endswith(" *")
    body = ".*".join(re.escape(part) for part in pattern.removesuffix(" *").split("*"))
    return re.compile("^" + body + ("( .*)?" if optional else "") + "$", re.DOTALL)


OPENCODE_RULES = [
    (opencode_regex(pattern), action)
    for pattern, action in json.loads(render(OPENCODE_TEMPLATE))["permission"]["bash"].items()
]


def opencode_action(cmd: str) -> str:
    """opencode's decision for a single command: the last matching rule wins."""
    return [action for regex, action in OPENCODE_RULES if regex.match(cmd)][-1]


def denied(cmd: str) -> bool:
    return any(p.match(cmd) for p in DENY)


def allowed(cmd: str) -> bool:
    return any(p.match(cmd) for p in ALLOW) and not denied(cmd)


def codex_matches(decision: str, cmd: str) -> bool:
    argv = shlex.split(cmd)
    return any(argv[: len(p)] == p for p in CODEX_RULES[decision])


def codex_denied(cmd: str) -> bool:
    return codex_matches("forbidden", cmd)


def codex_allowed(cmd: str) -> bool:
    return codex_matches("allow", cmd) and not codex_denied(cmd)


def shadowed(prefix: list[str], deny: str) -> bool:
    """Whether a deny that a Codex prefix cannot fully express overlaps an allow prefix."""
    tokens = deny.split(" ")
    if tokens[-1] == "*" and deny.count("*") == 1:
        return False
    k = next((i for i, t in enumerate(tokens) if "*" in t), len(tokens))
    head = tokens[k].split("*")[0] if k < len(tokens) else ""
    if prefix[:k] != tokens[:k]:
        return False
    return len(prefix) <= k or prefix[k].startswith(head)


def codex_rule_offenders() -> dict[str, list[str]]:
    """Each Codex rule property mapped to the patterns that break it."""
    allow, forbidden = CODEX_RULES["allow"], CODEX_RULES["forbidden"]
    return {
        "no * survives in a pattern": [
            json.dumps(p) for p in allow + forbidden if any("*" in t for t in p)
        ],
        "every forbidden prefix is denied by the Claude rules": [
            json.dumps(p) for p in forbidden if not denied(" ".join(p) + " x")
        ],
        "every allow prefix is allowed by the Claude rules": [
            json.dumps(p) for p in allow if not allowed(" ".join(p) + " x")
        ],
        "no allow prefix overlaps a deny that Codex cannot fully express": [
            json.dumps(p) for p in allow if any(shadowed(p, d) for d in DENY_PATTERNS)
        ],
        'allow ["git","status"] and forbidden ["rm","-rf","/"] are rendered': [
            json.dumps(p)
            for p, rules in ((["git", "status"], allow), (["rm", "-rf", "/"], forbidden))
            if p not in rules
        ],
    }


# Commands that must prompt: they run arbitrary code, write, or hit a non-GET endpoint.
NOT_ALLOWED = [
    "npx some-pkg --version",
    "bash -c 'rm -rf x' --help",
    "gh api repos/o/r -X DELETE",
    "gh api repos/o/r/git/refs/heads/main -X PATCH -F force=true",
    "gh api repos/o/r/pulls",
    "gh api --method GET repos/o/r -X DELETE",
    "gh api -X GET repos/o/r -XPOST -f a=b",
    "chezmoi git -- push --force origin catalog",
    "direnv exec . env",
    "chezmoi state reset",
    'psql -c \\d -c "drop table x"',
    "gradle tasks publish",
    "tmux list-sessions \\; run-shell 'touch /tmp/x'",
    "rtk pnpm exec some-bin",
    "rtk docker run alpine",
    "rtk prisma migrate reset",
    "deno task anything",
    "ldd ./untrusted",
    "git branch -v -D foo",
    "git branch -r -d origin/x",
    "git branch -vv -m a b",
    "git branch -v newbranch",
    "git branch -a -u origin/x",
    "git branch --list --no-list -D foo",
    "git branch --points-at HEAD --no-points-at -D foo",
    "uniq in out",
    "uniq -c in out",
    "curl -I https://example.com -o /tmp/x",
    "curl -I https://a --next -T file http://x",
    "wget --spider --post-file=/etc/passwd http://x",
    "wget --spider -o log http://x",
    "terraform providers mirror /tmp/x",
    "terraform providers lock",
    "ForEach-Object { Remove-Item $_ }",
    "Where-Object { Remove-Item x; $true }",
    "Sort-Object { Remove-Item x }",
    "Group-Object { Remove-Item x }",
    "Select-Object @{n='x';e={Remove-Item y}}",
    "Format-Table @{e={Remove-Item y}}",
    "Compare-Object a b -Property { Remove-Item y }",
    "fd -HX rm",
    "fd -tf -xrm",
    "git grep -nO'sh -c id' foo",
    "yq -yi '.a=1' f.yml",
    "xxd f out",
]

# Commands Claude denies through a mid-pattern `*`, which Codex cannot block,
# so it must not auto-approve them either.
CODEX_NOT_ALLOWED = [
    "find . -exec rm {} \\;",
    "find . -delete",
    "rg -n --pre x p",
    "git diff HEAD --output=/tmp/x",
    "sort in -o out",
    "git fetch origin --upload-pack=./x",
    "go list -toolexec x ./...",
    "chezmoi diff --pager 'sh -c id'",
    "bat x --pager 'sh -c id'",
]

# Read-only commands that must stay prompt-free.
ALLOWED = [
    "git log --oneline -5",
    "git diff",
    "rg pattern src",
    "gh api rate_limit",
    "gh api graphql -f query='query { viewer { login } }'",
    "chezmoi git -- log --oneline",
    "chezmoi git -- status",
    "ls -la",
    "jq --version",
    "git --version",
    "tmux list-panes -a",
    "rtk docker ps",
    "deno task test",
    "git branch -vv",
    "git branch -a",
    "git branch --contains HEAD",
    "git branch --merged main",
    "uniq -c",
    "terraform providers",
    "terraform providers schema -json",
    "Sort-Object",
    "Format-Table",
    "chezmoi diff ~/.zshrc",
    "chezmoi git -- log --oneline -5",
    "nix eval --expr 1",
    "go env GOPATH",
    "go list -m all",
    "openssl x509 -in a.pem -noout -text",
    "journalctl -u x -n 50",
]

# Destructive or code-running spellings that must be hard-blocked.
DENIED = [
    "rm -fr ~",
    "rm -Rf /",
    "rm -r -f ~/x",
    "rm --recursive --force ~/x",
    "rm --force --recursive /",
    "rm -f -r ~",
    "rm --force -r /",
    "rm -R -v ~/x",
    "rm -fR $HOME",
    "rm -rf /tmp/x",
    "git clean -df",
    "git clean -xdf",
    "git clean -d -f",
    "git clean -dfx",
    "git clean -fdx",
    "git clean --force",
    "xargs -0 rm",
    "xargs -I{} rm {}",
    "fd -X rm",
    "fd . -X rm",
    "sort -uo out in",
    "sort -o out in",
    "sort --compress-program=sh -S 1 f",
    "sort --co=sh -S 1 f",
    "sort --o=out in",
    "sort -no out in",
    "sort -k1 -ro out in",
    "sort -u -oout in",
    "find -delete",
    "find . -delete",
    "chezmoi apply -f",
    "chezmoi apply -vf",
    "git restore .",
    "git restore -- .",
    "git checkout .",
    "git fetch --upload-pack=./x .",
    "git ls-remote --upload-pack=./x origin",
    "git grep -O vim foo",
    "git grep -n -Ovim foo",
    "git grep --open=vim foo",
    "git grep --op=vim foo",
    "git ls-remote --exec=./x .",
    "git ls-remote --u=./x .",
    "git fetch --upl=./x .",
    "git log --output /tmp/x",
    "rg --pre ./x pattern",
    "rg --hostname-bin ./x pattern",
    "bat --pager 'sh -c id' f",
    "git diff --output=/tmp/x",
    "git log --output=/tmp/x",
    "yq -i '.a=1' f.yml",
    "yq --in-place '.a=1' f.yml",
    "yq --in-p '.a=1' f.yml",
    "tree -o /tmp/x",
    "xxd -r in out",
    "find . -fprint /tmp/x",
    "find . -fls /tmp/x",
    "journalctl --vacuum-time=1d",
    "journalctl -u x --vacuum-time=1d",
    "journalctl -u x --rotate",
    "journalctl --no-pager --flush",
    "journalctl -b --sync",
    "journalctl -b --smart-relinquish-var",
    "journalctl -b --setup-keys",
    "journalctl -n 1 --update-catalog",
    "journalctl -u x --cursor-file=/tmp/c",
    "journalctl --rot",
    "journalctl -b --vac=1d",
    "journalctl -b --se",
    "sysctl -n net.ipv4.ip_forward=1",
    "sysctl -w net.ipv4.ip_forward=1",
    "date -s 2020-01-01",
    "date +%s -s 2020-01-01",
    "date -s2020-01-01",
    "date --se=2020-01-01",
    "chezmoi diff -o /tmp/x",
    "chezmoi archive --output=/tmp/x.tar",
    "chezmoi diff --pager 'sh -c id'",
    "chezmoi cat --source /tmp/evil ~/.zshrc",
    "chezmoi data -S /tmp/evil",
    "chezmoi status --config /tmp/evil.toml",
    "chezmoi dump -c /tmp/evil.toml",
    "chezmoi state dump --output=/tmp/x",
    "nix eval --option allow-unsafe-native-code-during-evaluation true --expr 'builtins.exec [\"id\"]'",
    "nix eval --allow-unsafe-native-code-during-evaluation --expr x",
    "nix-instantiate --eval --option a b -E x",
    "nix flake show --plugin-files ./x.so",
    "nix search nixpkgs hello --extra-plugin-files ./x.so",
    "nix path-info nixpkgs#hello --post-build-hook ./x",
    "nix eval --write-to /tmp/x --expr '{}'",
    "go env -w GOFLAGS=-x",
    "go env -u GOFLAGS",
    "go list -toolexec ./x ./...",
    "openssl x509 -in a.pem -out b.pem",
    "openssl x509 -in a.pem -engine ./x.so",
    "openssl x509 -in a.pem -CA ca.pem -CAkey k.pem -CAcreateserial",
    "openssl s_client -connect h:443 -provider-path . -provider x",
    "openssl s_client -connect h:443 -sess_out /tmp/x",
    "openssl s_client -connect h:443 -keylogfile /tmp/k",
]

# Commands that may prompt but must not be hard-blocked.
NOT_DENIED = [
    "rm -i x",
    "rm -rf build",
    "rm -fr build",
    "rm -r -f node_modules",
    "git clean -n",
    "fd pattern",
    "sort -u f",
    "find . -name x",
    "chezmoi apply -v ~/.zshrc",
    "chezmoi apply -v ~/.claude/settings.json ~/.codex/rules/default.rules ~/.config/opencode/opencode.json",
    "chezmoi --source /tmp/wt execute-template -f x.tmpl",
    "chezmoi diff --no-pager",
    "git restore --staged f",
    "rg pattern",
    "bat f",
    "git diff",
    "tree",
    "xxd f",
    "journalctl -u x",
    "journalctl -b -o json",
    "sysctl -n kern.hostname",
    "date +%Y-%m-%d",
    "nix eval .#x --json",
    "nix flake show github:cachix/pre-commit-hooks.nix",
    "nix build --extra-experimental-features 'nix-command flakes' .#x",
    "go env GOPATH",
    "openssl x509 -in a.pem -outform der",
    "openssl s_client -connect h:443 -servername h -CAfile ca.pem",
    "git branch -D foo",
    "rm -f error.log .DS_Store",
    "rm -f server.log $TMPDIR/x",
    "rm -f ./report /x",
    "rm -v src/readme ~/x",
    "sort -k2 photo list",
    "git clean -nd -- fixtures/",
    "git grep -n 'CFLAGS=-O2'",
    "xargs -n1 terraform fmt",
    "xargs -I{} ssh {} uptime",
    "xargs shellcheck",
    "git log --output-indicator-new=+",
    "date -d next-sunday",
    "journalctl --since today",
    "yq -s '.' a.yml b.yml",
]

checks = 0
failures: list[str] = []

for group, check, cases, expected in (
    ("not_allowed", allowed, NOT_ALLOWED, False),
    ("allowed", allowed, ALLOWED, True),
    ("denied", denied, DENIED, True),
    ("not_denied", denied, NOT_DENIED, False),
    ("codex_not_allowed", codex_allowed, NOT_ALLOWED + CODEX_NOT_ALLOWED + DENIED, False),
    ("codex_not_denied", codex_denied, NOT_DENIED, False),
):
    for cmd in cases:
        checks += 1
        if check(cmd) is not expected:
            failures.append(f"{group}: {cmd}")

# opencode runs no github-api-write guard, so GraphQL calls must prompt there.
for cmd, expected in (
    ("gh api graphql -f query='mutation { x }'", "ask"),
    ("rtk gh api graphql -f query='mutation { x }'", "ask"),
    ("rtk proxy gh api graphql -f query='mutation { x }'", "ask"),
    ("gh api graphql", "ask"),
    ("gh api rate_limit", "allow"),
    ("git status", "allow"),
):
    checks += 1
    if opencode_action(cmd) != expected:
        failures.append(f"opencode: {cmd}: expected {expected}, got {opencode_action(cmd)}")

for name, offenders in codex_rule_offenders().items():
    checks += 1
    if offenders:
        failures.append(f"codex_rules: {name}: {', '.join(offenders)}")

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
