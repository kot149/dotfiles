#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["fugashi[unidic-lite]", "markdown-it-py"]
# ///
"""Block Claude-flavored Japanese phrasing before it lands in a document, a ticket, or a PR.

Covers Markdown and plain-text writes, Jira / Confluence create-update-comment
calls, and the `gh` commands that post issue / PR / release bodies and comments.

Every hit is denied rather than handed to the permission prompt, so the advice
always reaches the model. Repeating the identical call is the way to override a
hit that is a false positive or a deliberate choice.

Prose is located with a Markdown parser and matched with a morphological
analyser, so conjugation, compounds and code blocks are decided by the parsers
instead of by hand-written patterns. Both are imported lazily, so a call that is
out of scope never pays for them.
"""

import hashlib
import json
import os
import re
import shlex
import sys
import time

# Matched on the dictionary form of a token tagged as a verb, so every
# conjugation is covered and same-kanji nouns (採用, 転倒) are not.
VERB_RULES = {
    "寄せる": "「寄せる」→ 何をどの形に合わせるのかを具体的に書く"
    " (例: 「公開語彙に寄せる」→「公開語彙と同じ invalid_date_value を使う」)",
    "倒す": "「〜に倒す」→ どちらの値や挙動を選ぶのかを具体的に書く"
    " (例: 「安全側に倒す」→「判定材料が取れないときは拒否する」)",
    "採る": "「採る」→「採用する」と書く"
    " (例: 「この方式を採る」→「この方式を採用する」)",
}

COLOR_BASES = {"緑", "赤", "赤い", "グリーン", "レッド"}
COLOR_TAILS = {"なる", "まま", "返す", "保つ", "維持"}
# Allows one intervening particle between the colour and the predicate.
COLOR_WINDOW = 2
COLOR_ADVICE = (
    "テストの赤/緑 → 「テストが通る/成功する」「テストが落ちる/失敗する」と書く"
    " (例: 「全テストが緑のまま」→「全テストが通ったままで、退行を検出できない」)"
)

PIN_ADVICE = (
    "「pinする/される」→「固定する/される」と書く"
    " (例: 「テストが仕様をpinする」→「テストが仕様を固定し、変わったら落ちるようにする」)"
)

PROSE_SUFFIXES = (".md", ".markdown", ".mdx", ".txt")

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

URL = re.compile(r"\b(?:https?|git|ssh)://\S+")

# Inline nodes that are not prose; they cut the surrounding text in two so that
# neighbouring characters are never analysed as one word.
BREAKING_INLINE = {"code_inline", "image", "html_inline", "softbreak", "hardbreak"}

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
        if not path.lower().endswith(PROSE_SUFFIXES):
            return []
        text = tool_input.get("content") or tool_input.get("new_string") or ""
        return [text] if text else []

    if MCP_ATLASSIAN.match(tool_name) and MCP_WRITE_OP.search(tool_name):
        return collect_strings(tool_input)

    return []


def prose_segments(text):
    """Split text into prose runs, dropping code blocks, code spans, link targets and URLs."""
    from markdown_it import MarkdownIt

    segments = []
    for token in MarkdownIt("commonmark").parse(text):
        if token.type != "inline":
            continue
        prose = "".join(
            child.content
            if child.type == "text"
            else "\n"
            if child.type in BREAKING_INLINE
            else ""
            for child in token.children or []
        )
        for run in prose.split("\n"):
            run = URL.sub(" ", run).strip()
            if run:
                segments.append(run)
    return segments


def dictionary_form(token):
    return token.feature.orthBase or token.surface


def is_pin(tokens, i):
    following = dictionary_form(tokens[i + 1]) if i + 1 < len(tokens) else ""
    if tokens[i].surface.lower() == "pin":
        return following == "する"
    if tokens[i].surface == "ピン":
        return following in ("留める", "止める")
    return False


def find_matches(tokens):
    """Yield (rule id, surface, advice) for every token that trips a rule."""
    for i, token in enumerate(tokens):
        form = dictionary_form(token)
        part = token.feature.pos1
        if part == "動詞" and form in VERB_RULES:
            yield form, token.surface, VERB_RULES[form]
        elif form in COLOR_BASES and part in ("名詞", "形容詞"):
            window = tokens[i + 1 : i + 1 + COLOR_WINDOW]
            if any(dictionary_form(t) in COLOR_TAILS for t in window):
                yield "color", token.surface, COLOR_ADVICE
        elif is_pin(tokens, i):
            yield "pin", token.surface, PIN_ADVICE


def find_issues(texts):
    from fugashi import Tagger

    tagger = Tagger()
    findings, seen = [], set()
    for text in texts:
        for segment in prose_segments(text):
            for rule_id, surface, advice in find_matches(list(tagger(segment))):
                key = (rule_id, surface, segment)
                if key in seen:
                    continue
                seen.add(key)
                findings.append((surface, segment[:120], advice))
    return findings


# A denied call arms a one-shot pass keyed on its exact content, so repeating the
# same call goes through. That keeps the advice reaching the model on the first
# try while leaving a way past a false positive.
OVERRIDE_DIR = os.path.expanduser("~/.cache/claude-writing-style")
OVERRIDE_TTL = 600


def override_key(session_id, tool_name, texts):
    digest = hashlib.sha256()
    for part in [session_id, tool_name] + list(texts):
        digest.update(part.encode("utf-8", "replace") + b"\0")
    return digest.hexdigest()


def consume_override(key):
    """True when this exact call was denied a moment ago, so it is a deliberate retry."""
    path = os.path.join(OVERRIDE_DIR, key)
    try:
        fresh = time.time() - os.path.getmtime(path) < OVERRIDE_TTL
        os.remove(path)
        return fresh
    except OSError:
        return False


def arm_override(key):
    try:
        os.makedirs(OVERRIDE_DIR, exist_ok=True)
        for name in os.listdir(OVERRIDE_DIR):
            stale = os.path.join(OVERRIDE_DIR, name)
            try:
                if time.time() - os.path.getmtime(stale) >= OVERRIDE_TTL:
                    os.remove(stale)
            except OSError:
                continue
        open(os.path.join(OVERRIDE_DIR, key), "w").close()
    except OSError:
        pass


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

    key = override_key(payload.get("session_id") or "", tool_name, texts)
    if consume_override(key):
        return

    command = tool_input.get("command", "") if tool_name == "Bash" else ""
    if os.environ.get("FORCE_STYLE") == "1" or "FORCE_STYLE=1" in command:
        return

    arm_override(key)
    hint = (
        "\n表現を直して実行し直してください。"
        "指摘が誤検知、または意図した表現である場合に限り、"
        "同じ内容のまま同じ操作をもう一度実行すれば通過します。"
    )
    if tool_name == "Bash":
        hint += "\nコマンド先頭に FORCE_STYLE=1 を付けても通過します。"
    decide("deny", reason + hint)


if __name__ == "__main__":
    main()
