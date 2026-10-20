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
import rule from "../.chezmoitemplates/agents/textlint-rules/textlint-rule-ja-ai-phrasing.js";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

/** The @textlint/kernel version a file pins in its import specifier. */
const kernelPin = (file) =>
  fs.readFileSync(fileURLToPath(new URL(file, import.meta.url)), "utf8").match(/@textlint\/kernel@([\d.]+)/)?.[1] ?? null;

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

/** Every case flags exactly the given substrings. */
const expectHit = async (group, cases) => {
  for (const [text, ...hit] of cases) {
    check(`${group}: ${text}`, await hits(text), hit);
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
  ["放置した場合に壊れるもの。", "壊れる"],
  ["着手順を決めるならここが効く。", "効く"],
  ["可視範囲が広がる方向に効く。", "効く"],
]);

await expectHit("金額やコスト以外を払う", [
  ["毎回次の処理を払っている。", "払っ"],
  ["再計算と Redis の SET を払う。", "払う"],
  ["差分が無い項目でも取得を払う。", "払う"],
  ["コールドスタートを払う行が増える。", "払う"],
  ["この方式なら変換を払わずに済む。", "払わ"],
]);

await expectClean("金額やコスト、慣用句の払う", [
  "その分のコストを払う。",
  "高い代償を払った。",
  "細心の注意を払う。",
  "5000円を払う。",
  "毎月の電気代を払っている。",
  "相手に敬意を払う。",
  "肩の埃を払う。",
  "オーバーヘッドを払う。",
  "会計は先に払う。",
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
  "IDを採番する。",
  "連番で採番した。",
  "転倒に注意する。",
  "資料に目を通す。",
  "筋を通した設計にする。",
  "ログが文字化けしている。",
  "お化け屋敷の話をする。",
]);

await expectHit("要る", [
  ["すでにpush済みなので、反映するにはforce pushが要ります。", "要り"],
  ["Webhook URL自体が認証情報なので、トークンは要りません。", "要り"],
  ["すべてのエンドポイントは Bearer トークンが要る。", "要る"],
  ["新しいプール接続が要るリクエストは、503 で失敗する。", "要る"],
  ["スキーマへの宣言が要るので、スキーマを変えない。", "要る"],
  ["重複除去のループが要らなくなる。", "要ら"],
  ["IAM書き込み権限が要り、", "要り"],
  ["APIの再生成が要るか確認する。", "要る"],
]);

await expectClean("要ると同じ字の語と平仮名のいる", [
  "要件を書く。",
  "差分を要約する。",
  "ここにいる。",
  "時間を要する。",
]);

await expectHit("具体性のない名詞", [
  ["3つ目の消費者が出た時点で破綻する。", "破綻"],
  ["このチケットが着地すると古くなる。", "着地"],
  ["ヘッダ削除の帰結として409が残る。", "帰結"],
  ["この帰結として、リストは既定で空になります。", "帰結"],
  ["ヘッダ削除の必然的帰結だ。", "帰結"],
  ["既存レビューで決着済みです。", "決着"],
  ["このガードは保険という整理です。", "整理"],
  ["この整理で対応方針を確認しますか。", "整理"],
  ["そういう整理になる。", "整理"],
  ["同じ結論が3か所にあり、どこが正本か読めない。", "正本"],
  ["このドキュメントが単一readの正典になる。", "正典"],
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
  ["宣言外プロパティが黙って捨てられる。", "黙って"],
  ["成功を返した後に黙って消える。", "黙って"],
  ["編集権限を持たない項目を入力から黙って削る。", "黙って"],
  ["その結果、最近参照が静かに空っぽになる。", "静かに"],
  ["ラウンド増減で静かに古くなる。", "静かに"],
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

await expectHit("見出しの補足", [
  ["# 適用 (chezmoi apply が必要)", "(chezmoi apply が必要)"],
  ["## 設定（macOS のみ）", "（macOS のみ）"],
  ["#### 前提 (1) と手順 (2)", "(1)", "(2)"],
  ["適用 (必須)\n=====", "(必須)"],
]);

await expectClean("見出し以外の括弧と、見出しの中のコード / 空括弧", [
  "本文に書いた補足 (これは対象外) はそのまま。",
  "- リストの項目 (補足) も対象外。",
  "## `useState()` の使い方",
  "## `parse(input)` の挙動",
  "## 引数なしの呼び出し ()",
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
  ["force pushが要ります。", "force pushが必要です。"],
  ["トークンは要りません。", "トークンは必要ありません。"],
  ["権限が要りました。", "権限が必要でした。"],
  ["Bearer トークンが要る。", "Bearer トークンが必要。"],
  ["接続が要るリクエストは失敗する。", "接続が必要なリクエストは失敗する。"],
  ["宣言が要るので、変えない。", "宣言が必要なので、変えない。"],
  ["DBが要るのは、結合テストだけ。", "DBが必要なのは、結合テストだけ。"],
  ["ループが要らなくなる。", "ループが必要なくなる。"],
  ["権限が要り、", "権限が必要で、"],
  ["再生成が要るか確認する。", "再生成が必要か確認する。"],
]) {
  check(`fixer: ${text}`, await fixed(text), output);
}

for (const text of ["公開語彙に寄せる。", "判断は安全側に倒す。", "この方針で通す。", "権限が要った。"]) {
  check(`fixer が書き換えない: ${text}`, await fixed(text), text);
}

check(
  "textlint version matches the hook",
  kernelPin("../.chezmoitemplates/agents/check-writing-style.js"),
  kernelPin(import.meta.url),
);

console.log(`${checks - failures.length}/${checks} passed`);
for (const failure of failures) console.error(`  x ${failure}`);
if (failures.length) process.exit(1);
