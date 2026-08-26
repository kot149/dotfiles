/**
 * Tests for the writing-style rule behind ~/.claude/hooks/check-writing-style.js.
 *
 *   bun run tests/textlint-rule-ja-ai-phrasing.js
 *
 * The rule is driven through the same TextlintKernel the hook uses, so a passing
 * run means the hook behaves the same way. Assertions are hand-rolled because
 * `bun test` cannot resolve the versioned import specifiers this repo pins
 * dependencies with, and dependencies are installed on demand by Bun, so there
 * is no node_modules to keep in sync.
 */
import { TextlintKernel } from "@textlint/kernel@15.8.0";
import markdownPlugin from "@textlint/textlint-plugin-markdown@15.8.0";
import rule from "../dot_claude/hooks/textlint-rules/textlint-rule-ja-ai-phrasing.js";

const kernel = new TextlintKernel();

const options = {
  ext: ".md",
  plugins: [{ pluginId: "markdown", plugin: markdownPlugin.default ?? markdownPlugin }],
  rules: [{ ruleId: "ja-ai-phrasing", rule, options: true }],
};

/** The reported text itself, so a range that drifts off the match fails here. */
const hits = async (text) => {
  const { messages } = await kernel.lintText(text, options);
  return messages.map((m) => text.slice(...m.range));
};

const fixed = async (text) => (await kernel.fixText(text, options)).output;

const failures = [];
let checks = 0;

const check = (label, actual, expected) => {
  checks += 1;
  const [a, e] = [JSON.stringify(actual), JSON.stringify(expected)];
  if (a !== e) failures.push(`${label}\n      expected: ${e}\n      actual:   ${a}`);
};

/** Every case flags exactly the given substring. */
const expectHit = async (group, cases) => {
  for (const [text, hit] of cases) {
    check(`${group}: ${text}`, await hits(text), [hit]);
  }
};

/** Every case is left alone. */
const expectClean = async (group, texts) => {
  for (const text of texts) {
    check(`${group}: ${text}`, await hits(text), []);
  }
};

await expectHit("曖昧な動詞", [
  ["公開語彙に寄せる。", "寄せる"],
  ["判断は安全側に倒す。", "倒す"],
  ["この方式を採る。", "採る"],
  ["今回は申し送りとする。", "申し送り"],
  ["db側のゲートもこの関数を通す。", "通す"],
  ["この方針で通す。", "通す"],
]);

await expectHit("動詞の活用形", [
  ["判断は安全側に倒した。", "倒し"],
  ["公開語彙に寄せています。", "寄せ"],
  ["同じ方式を採らなかった。", "採ら"],
]);

await expectClean("同じ漢字の名詞と慣用句", [
  "この方式を採用する。",
  "転倒に注意する。",
  "資料に目を通す。",
  "筋を通した設計にする。",
]);

await expectHit("テストの色", [
  ["`mise run check` グリーン、collection も従来どおりです。", "グリーン"],
  ["テストはオールグリーンでした。", "グリーン"],
  ["レッドのまま放置している。", "レッド"],
  ["全テストが緑のまま。", "緑"],
  ["CIが緑になった。", "緑"],
  ["lint は赤です。", "赤"],
  ["型チェックが緑の状態を保つ。", "緑"],
  ["ビルドを緑に戻す。", "緑"],
  ["スイートが真っ赤だ。", "真っ赤"],
]);

await expectClean("色そのものの用法", [
  "背景は緑です。",
  "赤いボタンを押す。",
  "グリーンのアイコンを表示する。",
  "レッドの警告バッジを出す。",
  "信号が青から緑に変わる。",
  "都市の緑化を進める。",
  "全テストが通ったままで、退行を検出できない。",
]);

await expectHit("pin", [
  ["テストが仕様をpinする。", "pin"],
  ["仕様をPinしている。", "Pin"],
  ["仕様をピン留めする。", "ピン"],
]);

await expectClean("動詞化していない pin", ["ピンを刺す。", "pinned という名前にする。"]);

await expectHit("行頭のラベル", [
  ["結論: この方式を採用する。", "結論: "],
  ["**結論**: この方式を採用する。", "**結論**: "],
  ["**要点:** この方式を採用する。", "**要点:** "],
  ["まとめ：この方式を採用する。", "まとめ："],
  ["TL;DR: この方式を採用する。", "TL;DR: "],
  ["- ポイント: この方式を採用する。", "ポイント: "],
]);

await expectClean("行頭でないラベル", [
  "議論の結果、結論: この方式を採用すると決めた。",
  "結論はまだ出ていない。",
]);

await expectClean("URL の中身", ["https://example.com/pin/green を参照する。"]);

check(
  "URL の後ろでも報告位置がずれない",
  await hits("https://example.com/pin を見て、安全側に倒す。"),
  ["倒す"],
);

for (const [text, output] of [
  ["この方式を採る。", "この方式を採用する。"],
  ["テストが仕様をpinする。", "テストが仕様を固定する。"],
  ["結論: この方式を採用する。", "この方式を採用する。"],
]) {
  check(`fixer: ${text}`, await fixed(text), output);
}

for (const text of ["公開語彙に寄せる。", "判断は安全側に倒す。", "この方針で通す。"]) {
  check(`fixer が書き換えない: ${text}`, await fixed(text), text);
}

console.log(`${checks - failures.length}/${checks} passed`);
for (const failure of failures) console.error(`  x ${failure}`);
if (failures.length) process.exit(1);
