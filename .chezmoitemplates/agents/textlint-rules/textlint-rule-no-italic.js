/**
 * Flag italic text (`*text*`, `_text_`) anywhere in a Japanese document: headings, list items and running text alike, since Japanese writing does not use italics.
 *
 * A document without any Japanese is left alone, so English READMEs and PR bodies keep their italics.
 */

const JAPANESE = /[぀-ヿ㐀-鿿]/;

const ADVICE =
  "イタリック → 日本語の文章ではイタリックを使わない。見出しなら `##` などの見出し記法、強調なら太字にするか、強調をやめて文で書く" +
  " (例: 「*背景*」→「## 背景」、「*必ず* 実行する」→「**必ず**実行する」)";

function linter(context) {
  const { Syntax, RuleError, report, getSource } = context;
  let japanese = false;

  return {
    [Syntax.Document](node) {
      japanese = JAPANESE.test(getSource(node));
    },
    [Syntax.Emphasis](node) {
      if (japanese) report(node, new RuleError(ADVICE));
    },
  };
}

export default { linter, fixer: linter };
