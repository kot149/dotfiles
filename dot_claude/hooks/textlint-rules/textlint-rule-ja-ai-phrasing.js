/**
 * Flag Claude-flavored Japanese phrasing: vague verbs, test red/green metaphors
 * and English "pin" used as a Japanese verb.
 *
 * Matching is done on the part of speech and the dictionary form of each token,
 * so every conjugation is covered and same-kanji nouns (採用, 転倒) are not.
 */
import { tokenize } from "kuromojin@3.0.1";

const VERB_RULES = {
  寄せる: {
    advice:
      "「寄せる」→ 何をどの形に合わせるのかを具体的に書く" +
      " (例: 「公開語彙に寄せる」→「公開語彙と同じ invalid_date_value を使う」)",
  },
  倒す: {
    advice:
      "「〜に倒す」→ どちらの値や挙動を選ぶのかを具体的に書く" +
      " (例: 「安全側に倒す」→「判定材料が取れないときは拒否する」)",
  },
  採る: {
    advice: "「採る」→「採用する」と書く (例: 「この方式を採る」→「この方式を採用する」)",
    // Only the dictionary form is safe to rewrite mechanically; 採った などは指摘だけ。
    fix: { 採る: "採用する" },
  },
  申し送る: {
    // No fixer: 引き継ぎの意味なら書き換えてはいけないので、置換先は文脈で決まる。
    advice: "「申し送り」→「見送り」と書く (例: 「今回は申し送りとする」→「今回は見送る」)",
  },
  通す: {
    // 「目を通す」「筋を通す」は慣用句なので対象外。
    skip: (tokens, i) => ["目", "筋"].includes(dictionaryForm(tokens[i - 2] ?? {})),
    advice:
      "「〜を通す」→ 何をどう扱う / 維持するのかを具体的に書く" +
      " (例: 「db側のゲートもこの関数を通す」→「db側のゲートもこの関数を経由させる」" +
      " /「この方針で通す」→「新規ファイルでも同じ命名規則を使う」)",
  },
};

// テストの成否の比喩でしか使わない語。単独で出ても指摘する。大文字小文字は問わない。
const COLOR_METAPHORS = new Set(["グリーン", "レッド", "green", "red"]);
// 色そのものも指す語。テストの文脈があるときだけ指摘する。
const COLOR_BASES = new Set(["緑", "赤", "赤い", "真っ赤"]);
const COLOR_TAILS = new Set([
  "なる",
  "まま",
  "返す",
  "保つ",
  "維持",
  "戻す",
  "戻る",
  "キープ",
  "状態",
]);
const COLOR_SUBJECTS = new Set([
  "テスト",
  "test",
  "ci",
  "ビルド",
  "build",
  "lint",
  "チェック",
  "check",
  "スイート",
  "suite",
  "ジョブ",
  "job",
  "パイプライン",
  "pipeline",
]);
const LATIN_WORD = /^[A-Za-z][A-Za-z0-9_-]*$/;
// Allows one intervening particle between the colour and the predicate.
const COLOR_WINDOW = 2;
// 「全テストが緑」のように主語との間に接頭詞や助詞が挟まる分の余裕。
const COLOR_SUBJECT_WINDOW = 4;
const COLOR_ADVICE =
  "テストの赤/緑 → 「テストが通る/成功する」「テストが落ちる/失敗する」と書く" +
  " (例: 「全テストが緑のまま」→「全テストが通ったままで、退行を検出できない」)";

const LEANING_ADVICE =
  "「〜寄り」→ どちらに近いかではなく、実際の判断を言い切る" +
  " (例: 「「直さなくてよい」寄りです」→「今回は直さなくてよい」)";

const PIN_ADVICE =
  "「pinする/される」→「固定する/される」と書く" +
  " (例: 「テストが仕様をpinする」→「テストが仕様を固定し、変わったら落ちるようにする」)";

// A label dropped in front of a paragraph, plain or bold:
// 「結論: ...」「**結論**: ...」「**結論:** ...」「結論：...」
const LEAD_LABELS = ["結論", "要点", "まとめ", "ポイント", "補足", "概要", "TL;DR"];
const LEAD_LABEL = new RegExp(
  String.raw`^(?:\*\*)?(?:${LEAD_LABELS.join("|")})(?:\*\*)?[ \t]*[:：](?:\*\*)?[ \t]*(?=\S)`,
);
const LEAD_LABEL_ADVICE =
  "行頭の「結論:」のようなラベル → ラベルを外して本文をそのまま書くか、文に溶かす" +
  " (例: 「結論: この方式を採用する」→「この方式を採用する」/「結論としては、この方式を採用する」)";

const URL = /\b(?:https?|git|ssh):\/\/\S+/g;

const dictionaryForm = (token) =>
  token.basic_form && token.basic_form !== "*" ? token.basic_form : token.surface_form;

/** Blank out URLs while keeping every other character at its original offset. */
const maskUrls = (text) => text.replace(URL, (m) => " ".repeat(m.length));

/** The nearest token in the given direction, skipping the whitespace kuromoji emits as 記号. */
const neighborIndex = (tokens, i, step) => {
  for (let j = i + step; j >= 0 && j < tokens.length; j += step) {
    if (tokens[j].surface_form.trim()) return j;
  }
  return -1;
};

const neighbor = (tokens, i, step) => tokens[neighborIndex(tokens, i, step)] ?? {};

const isAttributive = (tokens, i) => dictionaryForm(neighbor(tokens, i, 1)) === "の";

/** 「Red Hat」「green thread」のように英単語と連なる形。色の比喩ではなく固有名詞や術語。 */
const isLatinCompound = (tokens, i) =>
  [-1, 1].some((step) => LATIN_WORD.test(neighbor(tokens, i, step).surface_form ?? ""));

/**
 * テストの成否を色で言い換えた表現。「グリーン」「レッド」は単独でも拾い、
 * 「緑」「赤」は前にテストの主語があるか後ろに状態の述語が続くときだけ拾う。
 */
const isTestColor = (tokens, i) => {
  const token = tokens[i];
  if (token.pos !== "名詞" && token.pos !== "形容詞") return false;
  const form = dictionaryForm(token);
  const isMetaphor = COLOR_METAPHORS.has(form.toLowerCase());
  if (!isMetaphor && !COLOR_BASES.has(form)) return false;
  // 「グリーンのアイコン」「Red Hat」のような色そのもの / 固有名詞の用法を外すため、
  // 連体修飾と英単語の複合語だけは文脈を見る。
  if (isMetaphor && !isAttributive(tokens, i) && !isLatinCompound(tokens, i)) return true;
  const before = tokens.slice(Math.max(0, i - COLOR_SUBJECT_WINDOW), i);
  const after = tokens.slice(i + 1, i + 1 + COLOR_WINDOW);
  return (
    before.some((t) => COLOR_SUBJECTS.has(dictionaryForm(t).toLowerCase())) ||
    after.some((t) => COLOR_TAILS.has(dictionaryForm(t)))
  );
};

/** 「〜寄り」が付く先の語。閉じ括弧が挟まるときは括弧の中の末尾の語を見る。 */
const leaningBase = (tokens, i) => {
  const j = neighborIndex(tokens, i, -1);
  if (j < 0) return {};
  return tokens[j].pos_detail_1 === "括弧閉" ? neighbor(tokens, j, -1) : tokens[j];
};

/**
 * 名詞以外に付く「寄り」。「安全寄り」「「見送り」寄り」のような名詞に付く形は
 * 語として定着しているので対象外で、用言や文を受ける形だけを指摘する。
 * 「歩み寄り」「左寄り」「寄り道」は一語にまとまるので surface が一致しない。
 */
const isLeaning = (tokens, i) => {
  if (tokens[i].pos !== "名詞" || tokens[i].surface_form !== "寄り") return false;
  const base = leaningBase(tokens, i);
  return Boolean(base.pos) && base.pos !== "名詞";
};

const isPin = (tokens, i) => {
  const next = tokens[i + 1];
  if (!next) return false;
  if (tokens[i].surface_form.toLowerCase() === "pin") return dictionaryForm(next) === "する";
  if (tokens[i].surface_form === "ピン") return ["留める", "止める"].includes(dictionaryForm(next));
  return false;
};

/** Yield { index, length, advice, replacement } for every token that trips a rule. */
function* findMatches(tokens) {
  for (const [i, token] of tokens.entries()) {
    const form = dictionaryForm(token);
    const surface = token.surface_form;
    const hit = { index: token.word_position - 1, length: surface.length };

    if (token.pos === "動詞" && VERB_RULES[form]) {
      const rule = VERB_RULES[form];
      if (rule.skip?.(tokens, i)) continue;
      yield { ...hit, advice: rule.advice, replacement: rule.fix?.[surface] };
    } else if (isLeaning(tokens, i)) {
      yield { ...hit, advice: LEANING_ADVICE };
    } else if (isTestColor(tokens, i)) {
      yield { ...hit, advice: COLOR_ADVICE };
    } else if (isPin(tokens, i)) {
      yield { ...hit, advice: PIN_ADVICE, replacement: surface.toLowerCase() === "pin" ? "固定" : undefined };
    }
  }
}

function linter(context) {
  const { Syntax, RuleError, report, getSource, fixer, locator } = context;

  /** Report on the raw paragraph source, where the bold markers are still visible. */
  const checkLeadLabel = (node) => {
    const [label] = getSource(node).match(LEAD_LABEL) ?? [];
    if (!label) return;
    const range = [0, label.length];
    report(
      node,
      new RuleError(LEAD_LABEL_ADVICE, {
        padding: locator.range(range),
        fix: fixer.replaceTextRange(range, ""),
      }),
    );
  };

  return {
    // A list item holds its own Paragraph, so this covers bulleted labels too.
    [Syntax.Paragraph]: checkLeadLabel,
    async [Syntax.Str](node) {
      const tokens = await tokenize(maskUrls(getSource(node)));
      for (const { index, length, advice, replacement } of findMatches(tokens)) {
        const range = [index, index + length];
        // padding over index so the reported range covers the whole match.
        const options = { padding: locator.range(range) };
        if (replacement !== undefined) options.fix = fixer.replaceTextRange(range, replacement);
        report(node, new RuleError(advice, options));
      }
    },
  };
}

export default { linter, fixer: linter };
