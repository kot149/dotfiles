/**
 * Flag Japanese bullet lists whose items are not parallel:
 *
 * - an item that opens with a connective (「つまり、」「そのため」「さらに」), so it continues the item before it instead of standing on its own
 * - a list that mixes item endings: noun-ending (体言止め), です・ます and だ・である
 *
 * The ending check compares only single-sentence items that end in Japanese. Items of more than one sentence, 「ラベル: 値」 items, items ending with a colon and items holding a nested list (labels for a group) are left out.
 */
import { tokenize } from "kuromojin@3.0.1";

const JAPANESE = /[぀-ヿ㐀-鿿]/;

// Openers kuromoji does not tag as 接続詞: a demonstrative or noun plus a particle that refers back to the previous item.
const CONNECTIVE_PHRASES = [
  "さらに",
  "加えて",
  "その結果",
  "結果として",
  "これにより",
  "それにより",
  "これによって",
  "それによって",
  "そのため",
  "このため",
  "それで",
  "そこで",
  "そのうえ",
  "その上",
  "それに",
  "逆に",
  "反対に",
  "同様に",
  "具体的には",
  "要するに",
  "言い換えると",
  "その場合",
  "この場合",
  "そうすると",
  "そうなると",
];

const CONNECTIVE_ADVICE =
  "箇条書きの項目が接続詞で始まり、前の項目の続きになっている → 項目を独立した内容にする。つながった説明なら箇条書きをやめて文章で書く" +
  " (例: 「- 設定が読まれない」「- つまり、再起動が必要」の2項目 →「設定が読まれないので、再起動が必要です。」の1文)";

const ENDING_LABELS = { noun: "体言止め", polite: "です・ます", plain: "だ・である" };
const endingAdvice = (counts) =>
  "箇条書きの文末の形がそろっていない (" +
  Object.entries(counts)
    .map(([kind, n]) => `${ENDING_LABELS[kind]} ${n}件`)
    .join("、") +
  ") → 並列な項目は文末を体言止めか文のどちらかにそろえ、文なら です・ます と だ・である も混ぜない";

const TRAILING_PUNCTUATION = /[\s。．.、,!！?？]+$/;
const PARENTHETICAL = /[（(][^（）()]*[）)]/g;
const QUOTE = /「[^「」]*」|『[^『』]*』/g;
const LABEL_END = /[:：]$/;
// 「原因: …」「**対象:** …」: the labels are what the items share, so their values may take any form.
const LABELED = /^[^。\n]{1,40}?[:：]/;
// More than one sentence, or more than one line, makes an item a short paragraph rather than a list entry.
const SENTENCE_BREAK = /[。．！？!?\n]/;

/** The plain text of an inline node; code and other non-text inline content reads as a noun. */
function inlineText(node, Syntax) {
  if (node.type === Syntax.Str) return node.value;
  if (node.type === Syntax.Code) return "コード";
  if (node.type === Syntax.Break) return "\n";
  if (node.children) return node.children.map((c) => inlineText(c, Syntax)).join("");
  return "";
}

/** The item text without parentheticals and trailing punctuation, so the last word is the ending. Quotes read as a noun. */
function endingText(text) {
  let rest = text.replace(QUOTE, "「引用」");
  for (let before = ""; before !== rest; ) {
    before = rest;
    rest = rest.replace(PARENTHETICAL, "");
  }
  return rest.replace(TRAILING_PUNCTUATION, "");
}

const POLITE_AUXILIARIES = new Set(["です", "ます"]);
// 「〜してください」ends in a verb, not in です / ます.
const POLITE_VERBS = new Set(["くださる", "下さる"]);
// では and には only set the scope, so the particle must follow a non-particle.
const SUBJECT_PARTICLES = new Set(["は/係助詞", "も/係助詞"]);
const omitsSuru = (t) => t.pos === "助詞" && !["連体化", "並立助詞"].includes(t.pos_detail_1);

/** noun, polite or plain for the item; null when it cannot be told. */
function endingKind(tokens) {
  const words = tokens
    .filter((t) => t.pos !== "記号" && t.pos_detail_1 !== "終助詞")
    // kuromoji reads the counter in 「4つ」 as an auxiliary.
    .map((t, i, all) => (t.surface_form === "つ" && all[i - 1]?.pos_detail_1 === "数" ? { ...t, pos: "名詞", pos_detail_1: "接尾" } : t));
  const last = words.at(-1);
  if (!last) return null;
  // Only the auxiliaries after the last content word count, so a quoted 「〜あります」と書く stays plain.
  const head = words.findLastIndex((t) => t.pos !== "助動詞");
  const auxiliaries = words.slice(head + 1);
  if (auxiliaries.some((t) => POLITE_AUXILIARIES.has(t.basic_form))) return "polite";
  if (POLITE_VERBS.has(last.basic_form)) return "polite";
  // 「中央揃え」「フィルタあり」「権限なし」 end like nouns.
  if (last.pos === "動詞" && last.conjugated_form === "連用形") return "noun";
  if (last.pos === "形容詞" && last.conjugated_form === "文語基本形") return "noun";
  if (last.pos === "名詞") {
    // 「〜が必要」 is a predicate with だ left out, not a noun ending.
    if (last.pos_detail_1 === "形容動詞語幹") return "plain";
    // 「XをYに変更」「ので削除」「すべて削除」 leave out する; 「ロール削除」「Xの削除」 are nouns.
    const prev = words.at(-2);
    if (last.pos_detail_1 === "サ変接続" && prev && (omitsSuru(prev) || prev.pos === "副詞" || prev.pos_detail_1 === "副詞可能")) return "plain";
    // 「AC 3は確認済み」「Xも完了」 are sentences with だ left out. A verb after the particle makes the noun the head of a clause instead (「当面はXを出さない案」). が is left out, since 「Xが無効の組織」 is a noun phrase. The な of 「一般的な語」 joins nouns like の.
    const subject = words.findLastIndex((t, i) => SUBJECT_PARTICLES.has(`${t.basic_form}/${t.pos_detail_1}`) && words[i - 1]?.pos !== "助詞");
    const nounPhrase = (t) => ["名詞", "助詞", "接頭詞"].includes(t.pos) || (t.pos === "助動詞" && t.conjugated_form === "体言接続");
    if (subject >= 0 && words.slice(subject + 1).every(nounPhrase)) return "plain";
    return "noun";
  }
  if (["動詞", "形容詞", "助動詞"].includes(last.pos)) return "plain";
  return null;
}

/** Length of the connective an item opens with, or 0. */
function connectiveLength(text, tokens) {
  // 「この場合の返り方」「その結果が」「それについて」「そこでは」 use the words as nouns.
  const phrase = CONNECTIVE_PHRASES.find((p) => text.startsWith(p) && !/^[のはがをつ]/.test(text.slice(p.length)));
  if (phrase) return phrase.length;
  const [first, second] = tokens;
  if (first?.pos !== "接続詞") return 0;
  // A connective followed by a particle or an auxiliary is a misparse, as in 「じゃ/ん/け/ん」.
  return ["助詞", "助動詞"].includes(second?.pos) ? 0 : first.surface_form.length;
}

function linter(context) {
  const { Syntax, RuleError, report, getSource, locator } = context;

  const checkList = async (list) => {
    const items = [];
    for (const item of list.children) {
      const paragraph = item.children?.find((c) => c.type === Syntax.Paragraph);
      if (!paragraph) continue;
      const text = inlineText(paragraph, Syntax).trim();
      if (!JAPANESE.test(text)) continue;
      const [first] = paragraph.children;
      const tokens = await tokenize(text);
      const length = first?.type === Syntax.Str ? connectiveLength(first.value.trimStart(), tokens) : 0;
      if (length > 0) {
        const offset = first.value.length - first.value.trimStart().length;
        const padding = locator.range([offset, offset + length]);
        report(paragraph, new RuleError(CONNECTIVE_ADVICE, { padding }));
      }
      // An item holding a nested list heads a group, like a label.
      if (item.children.some((c) => c.type === Syntax.List)) continue;
      if (LABEL_END.test(getSource(paragraph).trim()) || LABELED.test(text)) continue;
      const body = endingText(text);
      if (SENTENCE_BREAK.test(body)) continue;
      // An English item that only quotes Japanese has no Japanese ending to compare.
      if (!JAPANESE.test(body.at(-1) ?? "")) continue;
      const kind = endingKind(await tokenize(body));
      if (kind) items.push({ paragraph, kind });
    }

    const counts = {};
    for (const { kind } of items) counts[kind] = (counts[kind] ?? 0) + 1;
    if (Object.keys(counts).length < 2) return;
    // The most common ending is the list's form; ties go to the first item's.
    const major = Object.keys(counts).reduce((a, b) => (counts[b] > counts[a] ? b : a), items[0].kind);
    const advice = endingAdvice(counts);
    for (const { paragraph, kind } of items) {
      if (kind === major) continue;
      const source = getSource(paragraph).trimEnd();
      const line = source.split("\n").at(-1);
      const padding = locator.range([source.length - line.length, source.length]);
      report(paragraph, new RuleError(advice, { padding }));
    }
  };

  return {
    [Syntax.List]: checkList,
  };
}

export default { linter, fixer: linter };
