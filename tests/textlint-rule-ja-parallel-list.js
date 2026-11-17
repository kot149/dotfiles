/**
 * Tests for the parallel-list rule behind ~/.claude/hooks/check-writing-style.js and check-reply-format.js.
 *
 *   bun run tests/textlint-rule-ja-parallel-list.js
 */
import { TextlintKernel } from "@textlint/kernel@15.8.0";
import markdownPlugin from "@textlint/textlint-plugin-markdown@15.8.0";
import rule from "../.chezmoitemplates/agents/textlint-rules/textlint-rule-ja-parallel-list.js";

const kernel = new TextlintKernel();

const options = {
  ext: ".md",
  plugins: [{ pluginId: "markdown", plugin: markdownPlugin.default ?? markdownPlugin }],
  rules: [{ ruleId: "ja-parallel-list", rule, options: true }],
};

const hits = async (text) => {
  const { messages } = await kernel.lintText(text, options);
  return messages.map((m) => text.slice(...m.range));
};

const failures = [];
let checks = 0;

const check = (label, actual, expected) => {
  checks += 1;
  const [a, e] = [JSON.stringify(actual), JSON.stringify(expected)];
  if (a !== e) failures.push(`${label}\n      expected: ${e}\n      actual:   ${a}`);
};

const cases = [
  // Connectives at the start of an item.
  ["- 設定が読まれない\n- つまり、再起動しても直らない", ["つまり"]],
  ["- 設定が読まれない\n- なので再起動しても直らない", ["なので"]],
  ["- 速い\n- ただし、メモリを使う", ["ただし"]],
  ["- 速い\n- また、テストも直した", ["また"]],
  ["- 速い\n- さらにメモリも少ない", ["さらに"]],
  ["- 落ちる\n- その結果、再起動する", ["その結果"]],
  ["- キャッシュする\n- これにより速くなる", ["これにより"]],
  ["1. 設定を書く\n2. 次に、反映する", ["次に"]],
  ["- **原因**: 読み込み順\n- **対策**: 順序の変更", []],
  ["- その他の変更\n- 設定の修正", []],
  ["- 例外の扱い\n- 順序の変更", []],
  ["- 返り方は決まっていない\n- この場合の返り方は書かれていない", []],
  ["- 自動の調整はない\n- じゃんけんで決める", []],
  ["- 自動の調整はない\n- それについては決めていない", []],
  // Mixed endings.
  ["- 設定を追加した\n- テストを直した\n- READMEの更新", ["READMEの更新"]],
  ["- 設定を追加しました。\n- テストを直しました。\n- READMEを更新した。", ["READMEを更新した。"]],
  ["- 太字は対象外です。\n- コード内の`*`", ["コード内の`*`"]],
  ["- 箇条書きの項目\n- 句点で終わる行（`*注記です。*`）\n- 画像の直後のキャプション", []],
  ["- 設定を追加しました。\n- テストを直しました（2件）。", []],
  ["- 原因は読み込み順です。\n- 対策は順序の変更です。", []],
  ["- 確認したこと:\n  - 設定\n  - テスト\n- 残っている作業はありません。", []],
  ["- `foo`\n- `bar`", []],
  ["- Added the setting\n- 設定の修正", []],
  ["- Return only the blocks\n- End with the dictionary form (「〜する」)", []],
  ["- **対象:** `deals`\n- **結果**: 作成しました。\n- a11y: 該当なし", []],
  ["- 本番の読み取り速度。検証環境の値を当てはめています\n- 件数を確認した", []],
  ["- 4件と書く\n- 前回との差は「2〜3割違うものがあります」と書く", []],
  ["- ユーザーの許可が必要\n- アクセス権がない", []],
  ["- 表示します。\n- 実行してください。", []],
  ["- 表示します。\n- 実行してください。\n- 実行する。", ["実行する。"]],
  // Noun-like endings and sentences with だ or する left out.
  ["- 一覧\n- 件数\n- 絞り込みあり", []],
  ["- 新規\n- 編集\n- 権限なし", []],
  ["- レイアウトの説明\n- 注記のリンクと中央揃え", []],
  ["- 公開済みのスキル\n- 未追跡のスキル2つ", []],
  ["- 設定を直した\n- AC 3は確認済み\n- openapi は最新", []],
  ["- 設計は完了\n- 実装も完了\n- テストを追加した", []],
  ["- 設定を直した\n- この例は一般的な語", []],
  ["- 設定を直した\n- XをYに変更\n- 重なるので削除", []],
  ["- ロール削除時のチェック\n- uv.lockの更新\n- テストを追加した", ["テストを追加した"]],
  ["- 外部から読み込む案\n- 当面は画像を出さない案", []],
  ["- 管理者\n- 二段階認証が無効のユーザー", []],
  ["- 退会した人は消えること\n- 言語は設定から決まること", []],
  ["- 消えたもの\n- 「旧ルールです」と書いた箇所", []],
  ["- 設定を直した\n- 理由（議事録にあります）を書いた", []],
  // Items holding a nested list head a group.
  ["- **差分が小さい**\n  - 設定だけ違う\n- **前例がある**: stageを持っている\n- 見積もりの前提\n  - 同じIPは1つと数えた\n- 削減率は下がります", []],
];

for (const [text, expected] of cases) {
  check(text, await hits(text), expected);
}

console.log(`${checks - failures.length}/${checks} passed`);
for (const failure of failures) console.error(`  x ${failure}`);
if (failures.length > 0) process.exit(1);
