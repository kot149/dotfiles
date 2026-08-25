#!/usr/bin/env python3
"""Block Claude-flavored Japanese phrasing before it lands in a document, a ticket, or a PR.

Covers Markdown writes, Jira / Confluence create-update-comment calls, and the
`gh` commands that post issue / PR / release bodies and comments.
"""

import json
import os
import re
import shlex
import sys

# Each rule is (id, pattern, what to write instead).
RULES = [
    (
        "yoseru",
        re.compile(r"寄せ(?:る|て|た|ます|れば|ない|られ|よう)"),
        "「寄せる」→ 何をどの形に合わせるのかを具体的に書く"
        " (例: 「公開語彙に寄せる」→「公開語彙と同じ invalid_date_value を使う」)",
    ),
    (
        "taosu",
        re.compile(r"倒(?:す|し(?:て|た|ます|とく))"),
        "「〜に倒す」→ どちらの値や挙動を選ぶのかを具体的に書く"
        " (例: 「安全側に倒す」→「判定材料が取れないときは拒否する」)",
    ),
    (
        "test-color",
        re.compile(
            r"(?:緑|グリーン|(?<!ス)レッド|赤)(?:く|に|の|を)?"
            r"(?:なる|なっ|なり|まま|返す|保つ|維持)"
        ),
        "テストの赤/緑 → 「テストが通る/成功する」「テストが落ちる/失敗する」と書く"
        " (例: 「全テストが緑のまま」→「全テストが通ったままで、退行を検出できない」)",
    ),
    (
        "pin",
        re.compile(r"(?:[Pp]in|ピン)(?:留め|止め)?(?:する|して|した|され|しま)"),
        "「pinする/される」→「固定する/される」と書く"
        " (例: 「テストが仕様をpinする」→「テストが仕様を固定し、変わったら落ちるようにする」)",
    ),
]


MARKDOWN_SUFFIXES = (".md", ".markdown", ".mdx")

GH_SUBCOMMAND = re.compile(
    r"\bgh\s+(?:pr|issue|release)\s+"
    r"(?:create|edit|comment|review|reply|update)\b"
)
GH_API = re.compile(r"\bgh\s+api\b")
GH_API_WRITE = re.compile(
    r"(?:-X|--method)\s+(?:POST|PATCH|PUT|post|patch|put)\b"
    r"|(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)"
)

MCP_ATLASSIAN = re.compile(r"(?i)^mcp__.*(?:jira|confluence|atlassian)")
MCP_WRITE_OP = re.compile(r"(?i)(?:create|edit|update|add|post|comment)")

FENCE = re.compile(r"^\s*(?:```|~~~)")
CODE_SPAN = re.compile(r"`[^`\n]+`")
URL = re.compile(r"\b(?:https?|git|ssh)://\S+")

FILE_FLAGS = ("--body-file", "-F", "--input")


def read_body_files(command, cwd):
    """Pull in bodies passed by path. Heredocs break shlex, so failures are ignored."""
    try:
        words = shlex.split(command, comments=False)
    except ValueError:
        return []

    texts = []
    for flag in FILE_FLAGS:
        for i, word in enumerate(words):
            path = None
            if word == flag and i + 1 < len(words):
                path = words[i + 1]
            elif word.startswith(flag + "="):
                path = word[len(flag) + 1 :]
            if not path or path == "-":
                continue
            path = os.path.join(cwd, os.path.expanduser(path))
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    texts.append(f.read())
            except OSError:
                continue
    return texts


def collect_strings(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [s for item in value for s in collect_strings(item)]
    if isinstance(value, dict):
        return [s for item in value.values() for s in collect_strings(item)]
    return []


def target_texts(tool_name, tool_input, cwd):
    """Return the texts worth scanning for this call, empty when the tool is out of scope."""
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        is_gh_write = GH_SUBCOMMAND.search(command) or (
            GH_API.search(command) and GH_API_WRITE.search(command)
        )
        if not is_gh_write:
            return []
        return [command] + read_body_files(command, cwd)

    if tool_name in ("Write", "Edit"):
        path = tool_input.get("file_path", "")
        if not path.lower().endswith(MARKDOWN_SUFFIXES):
            return []
        text = tool_input.get("content") or tool_input.get("new_string") or ""
        return [text] if text else []

    if MCP_ATLASSIAN.match(tool_name) and MCP_WRITE_OP.search(tool_name):
        return collect_strings(tool_input)

    return []


def strip_code(text):
    """Blank out fenced blocks, code spans and URLs; phrasing rules do not apply there."""
    lines, in_fence = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
            lines.append("")
            continue
        lines.append("" if in_fence else line)
    stripped = "\n".join(lines)
    stripped = CODE_SPAN.sub(lambda m: " " * len(m.group(0)), stripped)
    return URL.sub(lambda m: " " * len(m.group(0)), stripped)


def find_issues(texts):
    findings, seen = [], set()
    for text in texts:
        scannable = strip_code(text)
        for rule_id, pattern, advice in RULES:
            for m in pattern.finditer(scannable):
                line_start = scannable.rfind("\n", 0, m.start()) + 1
                line_end = scannable.find("\n", m.end())
                line = scannable[line_start : line_end if line_end != -1 else None].strip()
                key = (rule_id, m.group(0), line)
                if key in seen:
                    continue
                seen.add(key)
                findings.append((m.group(0), line[:120], advice))
    return findings


def decide(decision, reason):
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision,
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()

    texts = target_texts(tool_name, tool_input, cwd)
    if not texts:
        return

    findings = find_issues(texts)
    if not findings:
        return

    detail = "\n".join(
        f"  「{hit}」  in: {line}\n    -> {advice}" for hit, line, advice in findings
    )
    reason = (
        "[言い回しの矯正]\n\n"
        "曖昧・翻訳調な表現が含まれています。読み手が具体的な動作を想像できる書き方に直してください。\n\n"
        f"{detail}\n"
    )

    print(reason, file=sys.stderr)

    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if os.environ.get("FORCE_STYLE") == "1" or "FORCE_STYLE=1" in command:
            return
        decide(
            "deny",
            reason + "\n誤検知の場合は FORCE_STYLE=1 をコマンド先頭に付けて再実行してください。",
        )

    decide("ask", reason + "\n意図した表現であればそのまま承認してください。")


if __name__ == "__main__":
    main()
