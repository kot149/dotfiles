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
};

const COLOR_BASES = new Set(["緑", "赤", "赤い", "グリーン", "レッド"]);
const COLOR_TAILS = new Set(["なる", "まま", "返す", "保つ", "維持"]);
// Allows one intervening particle between the colour and the predicate.
const COLOR_WINDOW = 2;
const COLOR_ADVICE =
  "テストの赤/緑 → 「テストが通る/成功する」「テストが落ちる/失敗する」と書く" +
  " (例: 「全テストが緑のまま」→「全テストが通ったままで、退行を検出できない」)";

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
      yield { ...hit, advice: rule.advice, replacement: rule.fix?.[surface] };
    } else if (COLOR_BASES.has(form) && (token.pos === "名詞" || token.pos === "形容詞")) {
      const window = tokens.slice(i + 1, i + 1 + COLOR_WINDOW);
      if (window.some((t) => COLOR_TAILS.has(dictionaryForm(t)))) {
        yield { ...hit, advice: COLOR_ADVICE };
      }
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
