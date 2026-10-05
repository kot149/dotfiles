#!/usr/bin/env bash
# Stop hook: when the final reply is written in English prose, block the stop
# and ask Claude to answer again in Japanese.
#
# Only the prose counts. Code blocks, inline code, blockquotes, URLs and paths
# are removed first, so quoting or generating English text inside them never
# triggers it. The reply passes as long as its prose contains Japanese at all,
# which covers a Japanese lead-in followed by an English translation or draft.

INPUT=$(cat)

[[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]] && exit 0

source "$(dirname "${BASH_SOURCE[0]}")/python-runner.sh"

HOOK_INPUT="$INPUT" "${PYTHON[@]}" - <<'PYEOF'
import json
import os
import re

data = json.loads(os.environ["HOOK_INPUT"])


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def read_transcript(path):
    """Return (last user prompt, last assistant text) from the transcript."""
    prompt, reply = "", ""
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, TypeError):
        return prompt, reply
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get("message") or {}
        text = text_of(message.get("content"))
        if not text.strip():
            continue
        if entry.get("type") == "assistant" and not reply:
            reply = text
        elif entry.get("type") == "user" and not entry.get("isMeta"):
            prompt = text
            break
    return prompt, reply


prompt, transcript_reply = read_transcript(data.get("transcript_path"))
reply = data.get("last_assistant_message") or transcript_reply

# The user explicitly asked for English output.
if re.search(r"英訳|英語(訳|化|版|に|で)|英文|in English|translat", prompt, re.IGNORECASE):
    raise SystemExit

prose = reply
prose = re.sub(r"(`{3,}|~{3,})[^\n]*\n.*?(\n\1|\Z)", "\n", prose, flags=re.DOTALL)
prose = re.sub(r"<([A-Za-z_-]+)[^>]*>.*?</\1>", " ", prose, flags=re.DOTALL)
prose = re.sub(r"`[^`\n]*`", " ", prose)
prose = re.sub(r"^\s*>.*$", " ", prose, flags=re.MULTILINE)
prose = re.sub(r"^ {4,}\S.*$", " ", prose, flags=re.MULTILINE)
prose = re.sub(r"\]\([^)]*\)", "]", prose)
prose = re.sub(r"https?://\S+|\S*[/\\]\S*", " ", prose)
prose = re.sub(r"\"[^\"\n]*\"|“[^”\n]*”", " ", prose)

if re.search(r"[぀-ヿ]", prose):
    raise SystemExit

words = re.findall(r"[A-Za-z]{2,}(?:'[a-z]+)?", prose)
if len(words) < 12:
    raise SystemExit

print(json.dumps({
    "decision": "block",
    "reason": (
        "The last reply was written in English prose. Rewrite the same reply "
        "in Japanese, following the language rules in CLAUDE.md. Keep code, "
        "identifiers, quoted text and requested English deliverables as they "
        "are, and do not redo any work or tool calls."
    ),
}))
PYEOF
