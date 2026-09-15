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
  ["小さな修正が巨大なPRに化ける。", "化ける"],
  ["この方針で通す。", "通す"],
  ["この仕様が壊れる。", "壊れる"],
  ["この数字は判断に効く。", "効く"],
]);

await expectClean("字義どおりの壊れる / 効く", [
  "エンコードを誤るとJSONが壊れる。",
  "HDDが物理的に壊れた。",
  "キャッシュが効いているのでレスポンスは速い。",
  "インデックスが効かないクエリを洗い出す。",
  "この薬はよく効く。",
]);

await expectHit("動詞の活用形", [
  ["判断は安全側に倒した。", "倒し"],
  ["公開語彙に寄せています。", "寄せ"],
  ["同じ方式を採らなかった。", "採ら"],
  ["設定を一つ変えるだけで挙動が化けます。", "化け"],
]);

await expectClean("同じ漢字の名詞と慣用句", [
  "この方式を採用する。",
  "転倒に注意する。",
  "資料に目を通す。",
  "筋を通した設計にする。",
  "ログが文字化けしている。",
  "お化け屋敷の話をする。",
]);

await expectHit("具体性のない名詞", [
  ["データの整合性が破綻する。", "破綻"],
  ["今週中に着地させたい。", "着地"],
  ["この設計の帰結として参照が循環する。", "帰結"],
  ["この件は来週決着させたい。", "決着"],
  ["AとBは別物という整理です。", "整理"],
  ["この整理で合っていますか。", "整理"],
  ["そういう整理になる。", "整理"],
  ["この定義が正本になる。", "正本"],
  ["仕様書を正典として扱う。", "正典"],
]);

await expectClean("字義どおりの名詞", [
  "議論は同じ結論に帰結する。",
  "経営破綻した企業の事例を調べる。",
  "体操選手が両足で着地する。",
  "試合は延長で決着がついた。",
  "情報を整理する。",
  "頭の整理がつかない。",
  "課題の整理を進める。",
  "机の上を整理した。",
  "この整理を進める。",
  "改正本文を確認する。",
  "修正本数は3件だった。",
]);

await expectHit("静かに / 黙って", [
  ["設定を間違えると静かに消える。", "静かに"],
  ["エラーを黙って握りつぶす。", "黙って"],
  ["リトライが静かに失敗する。", "静かに"],
  ["黙って例外を握りつぶす。", "黙って"],
  ["静かにフォールバックする。", "静かに"],
  ["静かに、消える。", "静かに"],
]);

await expectClean("人の動作としての静かに / 黙って", [
  "静かに話す。",
  "黙って待つ。",
  "図書館で静かに読む。",
  "黙っている。",
  "静かにしてください。",
  "黙って従うしかない。",
  "彼は黙って立ち去った。",
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
  ["いずれも green です。", "green"],
  ["全 12 項目 green を確認した。", "green"],
  ["CI は Red のままだ。", "Red"],
]);

await expectClean("色そのものの用法", [
  "背景は緑です。",
  "赤いボタンを押す。",
  "グリーンのアイコンを表示する。",
  "レッドの警告バッジを出す。",
  "信号が青から緑に変わる。",
  "都市の緑化を進める。",
  "全テストが通ったままで、退行を検出できない。",
  "Red Hat の話をする。",
  "green thread として実装する。",
  "redis に載せ替える。",
]);

await expectHit("名詞以外に付く寄り", [
  ["優先度は低く「直さなくてよい」寄りです。", "寄り"],
  ["結論は直さなくてよい寄りだ。", "寄り"],
  ["「あとで直す」寄りの判断になる。", "寄り"],
]);

await expectClean("名詞に付く寄り", [
  "この実装は安全寄りです。",
  "保守寄りの判断をする。",
  "設計はUI寄りになっている。",
  "判断は「見送り」寄りになる。",
]);

await expectClean("傾きを表さない寄り", [
  "歩み寄りが必要だ。",
  "左寄りの思想を説明する。",
  "文字を右寄りに配置する。",
  "寄り道をする。",
]);

await expectHit("pin", [
  ["テストが仕様をpinする。", "pin"],
  ["仕様をPinしている。", "Pin"],
  ["仕様をピン留めする。", "ピン"],
  ["ruff 0.14.9 に pin されている。", "pin"],
  ["バージョンを pin する。", "pin"],
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
  ["バージョンを pin する。", "バージョンを 固定する。"],
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
