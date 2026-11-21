# /// script
# requires-python = ">=3.11,<3.15"
# dependencies = ["fugashi==1.5.2", "unidic-lite==1.0.8"]
# ///
"""Stop hook: when the final reply says something is still unverified (「未確認です」「まだ確かめていません」 "not tested yet" ...), block the stop once and ask Claude to verify whatever it can check by itself. The next stop passes, which is where Claude reports the items it could not check and what blocks them. Other Stop hooks still check that stop, since only the hook that blocked leaves a marker for the session.

Japanese is split into morphemes with fugashi (UniDic), so a note is a verification word followed by a negated predicate chain (確認/は/まだ/し/て/い/ませ/ん), or 未 + a verification noun that ends the noun phrase. Code blocks, inline code, blockquotes and quoted spans are removed first. These pass:
- compound nouns (「未確認事項」「未確認報告」), passive forms (「実行されていません」) and plain refusals (「確認しません」)
- questions, conditionals and concessives after the negation (「確認していないか」「確認していない場合」「確認していないのに」)
- review findings about code (「どのテストも確かめていない」)
- a note whose sentence or the next one already names a blocker (permission, credentials, a request for the user's go-ahead)
- a prompt that says verification is not needed
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

import fugashi

# Hook I/O is UTF-8; Windows would otherwise use the ANSI code page.
data = json.load(sys.stdin.buffer)

# Set when this hook blocked a stop; stop_hook_active alone is also true after another hook's block.
MARKER = (
    Path(tempfile.gettempdir()) / "claude-stop-hooks" / f"{data.get('session_id') or 'unknown'}.check-unverified-reply"
)
if data.get("stop_hook_active") and MARKER.exists():
    sys.exit()
MARKER.unlink(missing_ok=True)


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "") for block in content if isinstance(block, dict) and block.get("type") == "text"
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

if re.search(
    r"(確認|検証|テスト|動作確認)(は|も)?(不要|いらない|しなくて(いい|よい|大丈夫)|しないで)"
    r"|no need to (verify|test|check)|(don't|do not) (verify|test|check)",
    prompt,
    re.IGNORECASE,
):
    sys.exit()

prose = reply
prose = re.sub(r"(`{3,}|~{3,})[^\n]*\n.*?(\n\1|\Z)", "\n", prose, flags=re.DOTALL)
prose = re.sub(r"<([A-Za-z_-]+)[^>]*>.*?</\1>", " ", prose, flags=re.DOTALL)
prose = re.sub(r"`[^`\n]*`", " ", prose)
prose = re.sub(r"^\s*>.*$", " ", prose, flags=re.MULTILINE)
prose = re.sub(r"^ {4,}\S.*$", " ", prose, flags=re.MULTILINE)
prose = re.sub(r"\"[^\"\n]*\"|“[^”\n]*”|「[^」\n]*」|『[^』\n]*』", " ", prose)

VERIFY = {"確認", "検証", "テスト", "確かめる", "試す", "実行", "実施"}
# 未確認 / 未検証 / 未テスト; 未実施 is mostly a status label in test result tables.
PREFIXED = {"確認", "検証", "テスト"}
ABOUT_NOTES = {"報告", "表現", "言い回し", "文", "記述"}
# 「確認できません」 without て; 「実行できません」 states an inability instead.
CAN_NOT = {"確認", "検証", "テスト", "確かめる", "試す"}
# Tokens allowed between the verification word and the negation.
CHAIN = {
    "は",
    "も",
    "を",
    "が",
    "だけ",
    "まで",
    "、",
    "未だ",
    "実施",
    "実行",
    "為る",
    "出来る",
    "終わる",
    "居る",
    "ます",
}
POTENTIAL = {"出来る", "られる"}
NEGATION = {"ない", "ず"}
# After the negation: 「〜場合」「〜なら」「〜とき」「〜件」「〜のに」
NOT_A_NOTE = {"場合", "なら", "とき", "時", "件", "のに"}
# After 未確認: 「未確認の点はありません」
NOTHING_LEFT = re.compile(r"^(の\w{1,4})?(は|も)(特に)?(ありません|ない|なし)")
ENGLISH = re.compile(
    r"\bun(verified|tested|confirmed)\b"
    r"|\bnot (yet )?(been )?(verified|tested|checked|confirmed|run)\b"
    r"|\b(haven't|have not|didn't|did not|couldn't|could not) (yet )?(verify|verified|test|tested|check|checked|confirm|confirmed|run)\b",
    re.IGNORECASE,
)
EN_CONDITIONAL = re.compile(r"\b(if|unless|when) (you|the user)\b[^.]{0,30}$", re.IGNORECASE)
# A review finding about code: 「どのテストも確かめていない」 「APIが権限を確かめていない」
CODE_SUBJECT = re.compile(r"(テスト|コード|API|関数|処理|実装|ガード)\s?(が|も)|どの\S{0,10}も")
# The reply already names what blocks the check, so it may stop.
BLOCKER = re.compile(
    r"権限|許可|資格情報|認証|パスワード|ログインでき|アクセスでき|拒否|手元にしか|負荷"
    r"|共用|共有の|自動判定|書き込めない"
    r"|よければ|もらえれば|必要であれば|言ってください|指示してください|教えてください"
    r"|デプロイされていない|まだデプロイ"
    r"|permission|credential|access|approv|let me know",
    re.IGNORECASE,
)
BOUNDARY = re.compile(r"[。\n|]|\.\s")


def lemma(word):
    return (word.feature.lemma or word.surface).split("-")[0]


def tokens():
    """Yield (start, end, surface, lemma, pos1) for each morpheme of prose."""
    pos = 0
    for word in fugashi.Tagger()(prose):
        start = prose.find(word.surface, pos)
        if start < 0:
            continue
        pos = start + len(word.surface)
        yield start, pos, word.surface, lemma(word), word.feature.pos1


def is_note_end(follows):
    """Whether the morphemes after the negation leave it a plain statement."""
    if follows[:1] == ["た"]:
        follows = follows[1:]
    f0, f1 = (follows + ["", ""])[:2]
    if f0 == "か" and f1 != "も":  # 「確認していないか」, but 「〜かもしれません」 is a note
        return False
    if f0 == "の" and f1 in ("か", "に"):  # 「〜のか」「〜のに」
        return False
    if f0 == "と" and f1 == "、":
        return False
    return f0 not in NOT_A_NOTE


def japanese_notes(toks):
    """Yield (start, end) spans of Japanese unverified notes."""
    for i, (start, end, surface, lem, _) in enumerate(toks):
        if lem not in VERIFY:
            continue
        # 未 + 確認: a note unless a noun continues the compound (未確認事項).
        if lem in PREFIXED and i > 0 and toks[i - 1][2] == "未" and toks[i - 1][4] == "接頭辞":
            nxt = [t[2] for t in toks[i + 1 : i + 3]]
            if i + 1 < len(toks) and toks[i + 1][4] == "名詞":
                continue
            # 「未確認の報告」 talks about such notes; 「未確認の点」 is one.
            if nxt[:1] == ["の"] and nxt[1:] and nxt[1] in ABOUT_NOTES:
                continue
            if NOTHING_LEFT.search(prose[end : end + 20]):
                continue
            yield toks[i - 1][0], end
            continue
        te = False
        potential = surface == "試せ"
        prev = lem
        for j, (_, t_end, t_surface, t_lem, t_pos1) in enumerate(toks[i + 1 : i + 12], i + 1):
            if t_lem == "れる" and prev == "為る":
                break  # passive: 実行されていません
            if t_lem in POTENTIAL:
                potential = True
            elif t_lem == "て" or t_lem == "てる":
                te = True
            elif t_lem in NEGATION and t_pos1 == "助動詞":
                follows = [t[2] for t in toks[j + 1 : j + 4]]
                # 「確認しません」 is a choice; 「確認できない」「確認できなくなる」 are too often findings about code, so without て only ません/ず/なかった count.
                if not te:
                    if not (potential and lem in CAN_NOT):
                        break
                    if t_lem != "ず" and not (t_surface == "なかっ" and follows[:1] == ["た"]):
                        break
                if is_note_end(follows):
                    yield start, t_end
                break
            elif t_lem not in CHAIN and t_lem not in VERIFY:
                break
            prev = t_lem


def sentence_start(pos):
    return max((b.end() for b in BOUNDARY.finditer(prose, 0, pos)), default=0)


def following_end(pos, sentences):
    for _ in range(sentences):
        b = BOUNDARY.search(prose, pos)
        if not b:
            return len(prose)
        pos = b.end()
    return pos


# 「テストはまだ実施できていません」 yields a span from テスト and one from 実施; keep the shortest, so the subject check sees 「テストは」 or 「どのテストも」.
latest = {}
for s, e in japanese_notes(list(tokens())):
    latest[e] = max(s, latest.get(e, s))
spans = [(s, e) for e, s in latest.items()]
spans += [
    (m.start(), m.end())
    for m in ENGLISH.finditer(prose)
    if not EN_CONDITIONAL.search(prose[sentence_start(m.start()) : m.start()])
]

hits = []
for m_start, m_end in sorted(spans):
    start = sentence_start(m_start)
    if CODE_SUBJECT.search(prose[start:m_start]):
        continue
    if BLOCKER.search(prose[start : following_end(m_end, 2)]):
        continue
    end = following_end(m_end, 1)
    hits.append(prose[max(start, m_start - 40) : min(end, m_end + 30)].strip())

if not hits:
    sys.exit()

MARKER.parent.mkdir(parents=True, exist_ok=True)
MARKER.touch()
sys.stdout.buffer.write(
    json.dumps(
        {
            "decision": "block",
            "reason": (
                "Your last reply says some things are not verified yet: "
                + " / ".join(f'"{h}"' for h in list(dict.fromkeys(hits))[:3])
                + ". Before stopping, verify everything you can check yourself with "
                "the tools you have: run the tests, commands or scripts, read files and "
                "logs, render or apply the change and inspect the result. Then report "
                "the actual results instead of the unverified note. Leave an item "
                "unverified only when something you cannot clear yourself blocks it: "
                "it needs the user's permission (outward-facing, destructive or sudo "
                "actions), credentials or access you lack, the user's device, GUI or "
                "environment, or a costly run the user should approve. For each such "
                "item, state concisely what was not checked and what blocks it. Do not "
                "redo work that is already done."
            ),
        },
        ensure_ascii=False,
    ).encode()
    + b"\n"
)
