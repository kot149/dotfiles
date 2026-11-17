# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Tests for the Bash permission hooks in .chezmoitemplates/agents/ and Claude Code's git -C rewrite, Japanese reply and unverified reply Stop hooks.

  uv run --no-python-downloads --script tests/hooks.py

Each hook runs as a subprocess with the same stdin JSON the agents send, so a passing run means the installed hook behaves the same way.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / ".chezmoitemplates" / "agents"

# Resolved through PATH: on Windows a bare "bash" can start System32's WSL launcher.
BASH = shutil.which("bash")
if BASH is None:
    sys.exit("bash not found on PATH")

PUSH = "check-force-push.sh"
GH_API = "check-github-api-write.sh"

PUSH_ASK = ("ask", "Git push requires confirmation")
FORCE_ASK = ("ask", "Force push")
GH_ASK = ("ask", "GitHub write requires confirmation")

# (hook, command, expected): None means no decision, else (decision, reason substring).
CASES: list[tuple[str, str, None | tuple[str, str]]] = [
    (PUSH, "git push origin main", PUSH_ASK),
    (PUSH, "git push --force origin main", FORCE_ASK),
    (PUSH, "git push -f", FORCE_ASK),
    (PUSH, "git push origin +main", FORCE_ASK),
    (PUSH, "git push --force-with-lease", FORCE_ASK),
    (PUSH, "git push -u origin HEAD", PUSH_ASK),
    (PUSH, "git -C /tmp/x push", PUSH_ASK),
    (PUSH, "FOO=1 git push", PUSH_ASK),
    (PUSH, "git status && git push", PUSH_ASK),
    (PUSH, "(git push --force)", FORCE_ASK),
    (PUSH, "(cd repo && git push)", PUSH_ASK),
    (PUSH, "git publish", PUSH_ASK),
    (PUSH, "git stash push", None),
    (PUSH, "git log", None),
    (PUSH, 'echo "git push"', None),
    (PUSH, "out=$(git push)", PUSH_ASK),
    (PUSH, 'echo "$(git push --force)"', FORCE_ASK),
    (PUSH, "echo `git push`", PUSH_ASK),
    (PUSH, "(git stash push)", None),
    (PUSH, "out=$(git log)", None),
    (PUSH, "git push \\\n  --force origin main", FORCE_ASK),
    (PUSH, "git -c core.x='a;b' push --force", FORCE_ASK),
    (PUSH, "git push origin main 2>&1", PUSH_ASK),
    (PUSH, "git commit -m 'a\nb' && git push", PUSH_ASK),
    (PUSH, "cat <<EOF > notes.txt\ndon't\nEOF\ngit push", PUSH_ASK),
    (PUSH, "echo '<<EOF'\ngit push --force\nEOF", FORCE_ASK),
    (PUSH, "# <<EOF\ngit push\nEOF", PUSH_ASK),
    (PUSH, "# don't\ngit -c core.x='a;b' push --force", FORCE_ASK),
    (PUSH, "git push origin main && git push --force origin other", FORCE_ASK),
    (PUSH, "echo \"$(git push)\" && git push -f", FORCE_ASK),
    (PUSH, "git push --help", None),
    (PUSH, "git push -h", None),
    (PUSH, "git push origin main --help", None),
    (PUSH, "git push --repo --help", PUSH_ASK),
    (PUSH, "git push -o --help --force", FORCE_ASK),
    (PUSH, "git push --force > --help", FORCE_ASK),
    (PUSH, "git push --force &> --help", FORCE_ASK),
    (PUSH, "git push origin main 2> -h", PUSH_ASK),
    (PUSH, "git push --force # --help", FORCE_ASK),
    (PUSH, "git push --force & echo --help", FORCE_ASK),
    (PUSH, "git push --help 2>&1", None),
    (PUSH, "git push --help && git push", PUSH_ASK),
    (PUSH, "git push origin -- --help", PUSH_ASK),
    (GH_API, "gh api repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -X POST repos/o/r/issues/1/comments -f body=x", GH_ASK),
    (
        GH_API,
        'gh api -H "Accept: application/vnd.github+json" -X POST repos/o/r/issues/1/comments -f body=x',
        GH_ASK,
    ),
    (GH_API, "gh api --jq .id repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -XPOST repos/o/r/pulls/1/merge", GH_ASK),
    (GH_API, "gh api -fbody=x repos/o/r/issues/1/comments", GH_ASK),
    (GH_API, "gh api -X PATCH repos/o/r/issues/comments/123 -f body=x", GH_ASK),
    (GH_API, "gh api -X DELETE repos/o/r/issues/comments/123", GH_ASK),
    (
        GH_API,
        "gh api graphql -f query='mutation { addComment(input:{}) { clientMutationId } }'",
        GH_ASK,
    ),
    (GH_API, "gh api repos/o/r/pulls", None),
    (GH_API, "gh api --paginate repos/o/r/pulls", None),
    (GH_API, "gh api repos/o/r/issues/comments/123", None),
    (GH_API, "gh api --method GET repos/o/r/pulls/1/comments", None),
    (GH_API, "gh pr view 1", None),
    (GH_API, "(gh api -X POST repos/o/r/pulls -f title=x)", GH_ASK),
    (GH_API, "x=$(gh api -X POST repos/o/r/issues/1/comments -f body=x)", GH_ASK),
    (GH_API, "gh api -iX POST repos/o/r/issues/1/comments -f body=x", GH_ASK),
    (GH_API, "gh api -iXPOST repos/o/r/pulls/1/merge", GH_ASK),
    (GH_API, "gh api https://api.github.com/repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api https://ghe.example.com/api/v3/repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api -i repos/o/r/pulls", None),
    (GH_API, "x=$(gh api repos/o/r/pulls)", None),
    (GH_API, "gh api https://api.github.com/repos/o/r/pulls", None),
    (GH_API, "gh pr comment 1 --repo o/r --body-file /tmp/c.md", GH_ASK),
    (GH_API, "rtk gh pr comment 1 -b x", GH_ASK),
    (GH_API, "gh pr create --title x --body y", GH_ASK),
    (GH_API, "gh pr edit 1 --body-file b.md", GH_ASK),
    (GH_API, "gh pr review 1 --comment -b x", GH_ASK),
    (GH_API, "gh pr ready 1 --undo", GH_ASK),
    (GH_API, "cd repo && gh issue comment 1 -b x", GH_ASK),
    (GH_API, "gh issue create --title x", GH_ASK),
    (GH_API, "gh pr list --state all", None),
    (GH_API, "gh pr checks 1", None),
    (GH_API, "gh issue view 1 --comments", None),
    (GH_API, 'echo "gh pr comment 1"', None),
    (GH_API, "gh pr create --help", None),
    (GH_API, "gh pr merge 1 -h", None),
    (GH_API, "gh issue comment --help", None),
    (GH_API, "gh api -X POST repos/o/r/pulls --help", None),
    (GH_API, "gh pr create --help && gh pr create --title x", GH_ASK),
    (GH_API, "gh pr comment 1 -b x -- --help", GH_ASK),
    (GH_API, "gh pr comment 1 -b x --help", None),
    (GH_API, "gh pr create --title=x --help", None),
    (GH_API, "gh pr create --title --help", GH_ASK),
    (GH_API, "gh pr comment 1 -b -h", GH_ASK),
    (GH_API, "gh api -X --help repos/o/r/pulls -f title=x", GH_ASK),
    (GH_API, "gh api repos/o/r/pulls -f --help", GH_ASK),
    (GH_API, "gh pr create -t x -b y > --help", GH_ASK),
    (GH_API, "gh pr create -t x &> --help", GH_ASK),
    (GH_API, "gh pr create -t x >& -h", GH_ASK),
    (GH_API, "gh pr create -t x < -h", GH_ASK),
    (GH_API, "gh pr create -t x # --help", GH_ASK),
    (GH_API, "gh api -X POST repos/o/r/pulls -f title=x 2> --help", GH_ASK),
    (GH_API, "gh pr create --help | less", None),
    (
        GH_API,
        "gh api graphql -f query='\n  mutation {\n"
        "    resolveReviewThread(input: {threadId: \"x\"}) { thread { id } }\n  }\n'",
        GH_ASK,
    ),
    (GH_API, "gh api graphql \\\n  -f query='mutation { addComment(input:{}) { clientMutationId } }'", GH_ASK),
    (GH_API, "gh pr create --title x --body \"$(cat <<'EOF'\nIt's done; see notes.\nEOF\n)\"", GH_ASK),
    (GH_API, "gh api graphql --input - <<'EOF'\n{\"query\": \"mutation { x }\"}\nEOF", GH_ASK),
    (GH_API, "gh api graphql -f query='\n  query {\n    viewer { login }\n  }\n'", None),
    (GH_API, "echo '<<EOF'\ngh api graphql -f query='\n  mutation { x }\n'\nEOF", GH_ASK),
    (GH_API, "# <<EOF\ngh api graphql -f query='\n  mutation { x }\n'\nEOF", GH_ASK),
    (GH_API, "# don't\ngh api graphql -f query='\n  mutation { x }\n'", GH_ASK),
    (GH_API, "gh api graphql -F query=@q.graphql", GH_ASK),
    (GH_API, "gh api graphql --field query=@-", GH_ASK),
    (GH_API, "gh api graphql -Fquery=@q.graphql", GH_ASK),
    (GH_API, "gh api graphql -f query=@q.graphql", None),
]

# (command, expected updatedInput.command): None means the hook leaves it as is.
REWRITE_CASES: list[tuple[str, None | str]] = [
    ("git -C /tmp status", "(cd /tmp && git status)"),
    ('git -C "/path with space" log -1', '(cd "/path with space" && git log -1)'),
    ("git -C '/q' diff", "(cd '/q' && git diff)"),
    ("git -C repo status && git -C other log", "(cd repo && git status) && (cd other && git log)"),
    ("cd x; git -C y status", "cd x; (cd y && git status)"),
    ("(git -C repo status)", "( (cd repo && git status))"),
    ("git -C a -C b status", None),
    ("git -C repo log > out.txt", None),
    ("git -C repo log | head", "(cd repo && git log) | head"),
    ("git -C $(pwd) status", None),
    ('git -C repo commit -m "a && b"', '(cd repo && git commit -m "a && b")'),
    ("git status", None),
    ("git -C -x status", None),
    ("echo 'git -C x status'", None),
    ("git -C repo log 2>&1", None),
    ('git -C repo log "a > b"', '(cd repo && git log "a > b")'),
    ("git -C repo log && echo hi > out", "(cd repo && git log) && echo hi > out"),
    ("git -C repo status || git -C r2 status", "(cd repo && git status) || (cd r2 && git status)"),
    ("git -C repo status |& cat", "(cd repo && git status) |& cat"),
    ("git -C repo status &", "(cd repo && git status) &"),
    ("git -C repo status\ngit -C b log", "(cd repo && git status)\n(cd b && git log)"),
    ("git -C=repo status", None),
    ("git -Crepo status", None),
    ("git -C repo log <<EOF", None),
    ("git -C 'unterminated status", None),
]

ENGLISH_REPLY = (
    "I've updated the section in the README. Checking the file after the update, "
    "the TODO line is gone and the new steps are there."
)

# (user prompt, last reply, expected block): the Stop hook should block English prose only.
JAPANESE_REPLY_CASES: list[tuple[str, str, bool]] = [
    ("READMEを更新して", ENGLISH_REPLY, True),
    ("READMEを更新して", "I've updated the 「使い方」 section. " + ENGLISH_REPLY, True),
    ("READMEを更新して", "I've updated the 『はじめに』 section. " + ENGLISH_REPLY, True),
    ("READMEを更新して", "「使い方」の節を更新しました。TODOの行は消えています。", False),
    ("READMEを更新して", "更新しました。\n\n```\n" + ENGLISH_REPLY + "\n```", False),
    ("READMEを更新して", "Done.", False),
    ("英訳して", ENGLISH_REPLY, False),
]

# (user prompt, last reply, expected block): the Stop hook should block unverified notes only.
UNVERIFIED_REPLY_CASES: list[tuple[str, str, bool]] = [
    ("直して", "修正しました。実機での動作はまだ確かめていません。", True),
    ("直して", "修正しました。確かめられていません。", True),
    ("直して", "修正しました。テストは未確認です。", True),
    ("直して", "修正しました。動作確認はしていません。", True),
    ("直して", "修正しました。ビルドは確認できていません。", True),
    ("直して", "Fixed the parser. I haven't run the tests yet.", True),
    ("直して", "Fixed the parser. This is untested.", True),
    ("直して", "修正し、テストが通ることを確認しました。", False),
    ("直して", "修正しました。未確認の点はありません。", False),
    ("直して", "ログを確認していない場合は先に見てください。", False),
    ("直して", "何を確認していないかと何が障害かを短く書かせます。", False),
    ("直して", "ビルドが通るか確認していないかどうかを判定します。", False),
    ("直して", "まだ確認していないかもしれません。", True),
    ("直して", "「未確認です」で終わる返信を検出します。", False),
    ("直して", "修正しました。\n\n```\n# not verified yet\n```", False),
    ("直して", "Fixed it. If you haven't tested it, run `just test`.", False),
    ("直して。確認は不要", "修正しました。動作は未確認です。", False),
]

# Final replies taken from real Claude Code sessions, with names, hosts and IDs replaced.
UNVERIFIED_REPLY_CASES += [
    # Unverified notes Claude could have checked itself.
    ("調べて", "サーバーが中身を切り詰めていないか（モデルが全文を見ているか）は確かめていません。", True),
    ("調べて", "インデックスは使われる形です。実行計画（EXPLAIN）も確認していません。", True),
    ("調べて", "ロールのIDは私の記憶によるもので、APIで確かめてはいません。", True),
    ("直して", "これはコードからの判断で、stgで書き込みは試していません。", True),
    ("直して", "Chromeを再起動すれば戻ると思いますが、まだ確かめていません。", True),
    ("調べて", "stagingは計測済みです。本番の確認はまだ終わっていません。", True),
    ("書いて", "ドキュメントを更新しました。書いた後にファイルを読み直しての確認はしていません。", True),
    ("直して", "テストはまだ実施していないので、PR本文のテスト欄は空のままにしてあります。", True),
    ("直して", "#123はdev環境での動作確認をしていません。", True),
    ("直して", "サーバーは起動しています。ブラウザで実際にダッシュボードを開く確認だけは、まだできていません。", True),
    ("直して", "画面でのテストはまだ実施できていません。", True),
    ("調べて", "通知スキームはMCPから確認できなかったので、ほかの宛先があるかは分かりません。", True),
    ("調べて", "## 確認できなかったこと\n\n- 本番の設定値", True),
    ("直して", "単体テストは通っています。Integration層は実行していません。", True),
    # The blocker is already named, so the stop passes.
    ("調べて", "トークン取得は、パスワードを取れないため実行していません。", False),
    ("作って", "実際にログインできるかは、まだ試していません。仮パスワードはあなたの手元にしかないためです。", False),
    ("調べて", "本番はマシンの性能も件数も確認できていません。本番DBに入る権限がないためです。", False),
    ("進めて", "まだ次の3つは実行していません。進めてよければ指示してください。", False),
    ("試して", "本番WAFのアラームが鳴る可能性があるため、まだ実行していません。必要であれば言ってください。", False),
    ("調べて", "バケットのポリシーはまだ確認できていません。`aws sso login` で認証してもらえれば確認します。", False),
    ("デプロイして", "このデプロイは共有のstagingを入れ替えるので、まだ実行していません。", False),
    ("試して", "新しいユーザーを登録する部分は、自動判定で書き込めないため試していません。", False),
    # Review findings about code, state descriptions and document terms.
    ("レビューして", "| 1 | 保存が失敗したときの分岐を、どのテストも確かめていない | MEDIUM |", False),
    ("レビューして", "1年と9999年の日付を正しい期間に入れるかを、テストが確かめていません。", False),
    ("レビューして", "検索の API が、ページ番号の範囲を確かめていない。", False),
    ("調べて", "最終更新は8月28日なので、2本目のPUTはまだ実行されていません。", False),
    ("まとめて", "APIで入力値を確かめていない件は、まだ担当者に送っていません。", False),
    ("見直して", "PdMに確認していないのに決定済みとして書いてある箇所がありました。", False),
    ("追記して", "ドキュメントの未確認事項の1件目に回答を追記しました。", False),
    ("調べて", "残りを読むと、ほとんどが本物の未確認報告です。", False),
    ("比べて", "| 表の中の指摘 | 直せない。誰が確認していないのかは文脈で決まる |", False),
    ("調べて", "返信を投稿したかどうかを、私が確かめられていないからです。", True),
    ("調べて", "エラーにする経路は、環境変数を変えて起動しないと試せません。", True),
    ("直して", "未確認リストの2件目を消しました。", False),
    ("直して", "否定まで続く語の並びがあれば、未確認の報告とみなします。", False),
    ("直して", "検証用ページの有無を含め、未確認の点がいくつか残っています。", True),
    ("調べて", "親の画面とページがお互いのオリジンを確認できなくなり、通信できなくなります。", False),
    ("調べて", "チームへのreview requestは、メンバーかを確認せずに通知します。", False),
    ("調べて", "設定画面のタブだけは未実施です。", False),
]

# (user prompt, last reply, expected block): the rules themselves are covered by tests/textlint-rule-no-italic.js and tests/textlint-rule-ja-parallel-list.js.
REPLY_FORMAT_CASES: list[tuple[str, str, bool]] = [
    ("調べて", "*原因*\n\n設定ファイルの読み込み順です。", True),
    ("調べて", "## 原因\n\n設定ファイルの *読み込み順* です。", True),
    ("調べて", "## 原因\n\n設定ファイルの**読み込み順**です。", False),
    ("translate", "Done. The *order* matters.", False),
    ("調べて", "- 設定が読まれていません。\n- そのため、再起動しても直りません。", True),
    ("調べて", "- 設定を追加しました。\n- テストを直しました。\n- READMEの更新", True),
    ("調べて", "- 設定を追加しました。\n- テストを直しました。", False),
]

failures: list[str] = []
checks = 0


def check(label: str, ok: bool, detail: str) -> None:
    global checks
    checks += 1
    if not ok:
        failures.append(f"{label}\n      {detail}")


def run(hook: str, command: str) -> tuple[int, None | tuple[str, str]]:
    """Return the hook's exit status and its decision (None when silent)."""
    result = subprocess.run(
        [BASH, str(HOOKS / hook)],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if not result.stdout.strip():
        return result.returncode, None
    d = json.loads(result.stdout)["hookSpecificOutput"]
    return result.returncode, (d["permissionDecision"], d["permissionDecisionReason"])


for hook, command, expected in CASES:
    label = f"{hook}: {command}"
    status, actual = run(hook, command)
    if status != 0:
        check(label, False, f"exit status {status}")
        continue
    if expected is None:
        ok = actual is None
    else:
        ok = actual is not None and actual[0] == expected[0] and expected[1] in actual[1]
    check(label, ok, f"expected: {expected!r}\n      actual:   {actual!r}")


def rewrite(hook_dir: Path, command: str) -> tuple[int, str, None | str]:
    """Return the rewrite hook's exit status, stderr and updatedInput command (None when silent)."""
    result = subprocess.run(
        [BASH, str(hook_dir / "rewrite-git-c.sh")],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**os.environ, "PATH": f"{hook_dir}{os.pathsep}{os.environ['PATH']}"},
    )
    if not result.stdout.strip():
        return result.returncode, result.stderr, None
    updated = json.loads(result.stdout)["hookSpecificOutput"]["updatedInput"]["command"]
    return result.returncode, result.stderr, updated


# Lay the hook out as installed, next to python-runner.sh, with an rtk stub first on PATH so a real rtk does not rewrite the command further.
with tempfile.TemporaryDirectory() as tmp:
    hook_dir = Path(tmp)
    shutil.copy(ROOT / "dot_claude" / "hooks" / "executable_rewrite-git-c.sh", hook_dir / "rewrite-git-c.sh")
    shutil.copy(HOOKS / "python-runner.sh", hook_dir / "python-runner.sh")
    stub = hook_dir / "rtk"
    stub.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    stub.chmod(0o755)

    for command, expected in REWRITE_CASES:
        label = f"rewrite-git-c: {command}"
        status, stderr, actual = rewrite(hook_dir, command)
        # A failing python step falls through silently, so stderr must stay empty too.
        if status != 0 or stderr:
            check(label, False, f"exit status {status}, stderr: {stderr.strip()!r}")
            continue
        check(label, actual == expected, f"expected: {expected!r}\n      actual:   {actual!r}")


def stop_hook(hook_dir: Path, hook: str, prompt: str, reply: str, active: bool = False) -> tuple[int, str, bool]:
    """Return the Stop hook's exit status, stderr and whether it blocked."""
    transcript = hook_dir / "transcript.jsonl"
    transcript.write_text(
        json.dumps({"type": "user", "message": {"role": "user", "content": prompt}}) + "\n",
        encoding="utf-8",
    )
    runners = {".py": ["uv", "run", "--quiet", "--no-python-downloads", "--script"], ".js": ["bun", "run"]}
    runner = runners.get(Path(hook).suffix, [BASH])
    result = subprocess.run(
        [*runner, str(hook_dir / hook)],
        input=json.dumps(
            {"transcript_path": str(transcript), "last_assistant_message": reply, "stop_hook_active": active}
        ),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    blocked = bool(result.stdout.strip()) and json.loads(result.stdout).get("decision") == "block"
    return result.returncode, result.stderr, blocked


STOP_HOOK_CASES = [
    ("check-japanese-reply.sh", JAPANESE_REPLY_CASES),
    ("check-unverified-reply.py", UNVERIFIED_REPLY_CASES),
    ("check-reply-format.js", REPLY_FORMAT_CASES),
]

with tempfile.TemporaryDirectory() as tmp:
    hook_dir = Path(tmp)
    shutil.copy(HOOKS / "python-runner.sh", hook_dir / "python-runner.sh")
    shutil.copytree(HOOKS / "textlint-rules", hook_dir / "textlint-rules")

    for hook, cases in STOP_HOOK_CASES:
        source = ROOT / "dot_claude" / "hooks" / hook
        if not source.exists():
            source = source.with_name(f"executable_{hook}")
        shutil.copy(source, hook_dir / hook)
        for prompt, reply, expected in cases:
            label = f"{hook}: {prompt} / {reply[:40]!r}"
            status, stderr, actual = stop_hook(hook_dir, hook, prompt, reply)
            if status != 0 or stderr:
                check(label, False, f"exit status {status}, stderr: {stderr.strip()!r}")
                continue
            check(label, actual == expected, f"expected block: {expected}\n      actual:   {actual}")

    # The stop after a block passes, so Claude can report what blocks the remaining checks.
    status, stderr, actual = stop_hook(
        hook_dir, "check-unverified-reply.py", "直して", "実機での動作は未確認です。", active=True
    )
    check("check-unverified-reply.py: stop_hook_active", status == 0 and not actual, f"blocked: {actual}")

print(f"{checks - len(failures)}/{checks} passed")
for failure in failures:
    print(f"  x {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
