/**
 * Tests for the italic rule behind ~/.claude/hooks/check-writing-style.js and check-italic-reply.js.
 *
 *   bun run tests/textlint-rule-no-italic.js
 */
import { TextlintKernel } from "@textlint/kernel@15.8.0";
import markdownPlugin from "@textlint/textlint-plugin-markdown@15.8.0";
import rule from "../.chezmoitemplates/agents/textlint-rules/textlint-rule-no-italic.js";

const kernel = new TextlintKernel();

const options = {
  ext: ".md",
  plugins: [{ pluginId: "markdown", plugin: markdownPlugin.default ?? markdownPlugin }],
  rules: [{ ruleId: "no-italic", rule, options: true }],
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
  ["*背景*\n\n本文です。", ["*背景*"]],
  ["_背景_:\n本文です。", ["_背景_"]],
  ["本文の *強調* です。", ["*強調*"]],
  ["*これは注記です。*", ["*これは注記です。*"]],
  ["- *項目*\n- 項目2", ["*項目*"]],
  ["> *引用* の中", ["*引用*"]],
  ["## 見出しの *強調*", ["*強調*"]],
  ["| 列 |\n| --- |\n| *セル* |", ["*セル*"]],
  ["日本語の文と *English emphasis*", ["*English emphasis*"]],
  ["***太字斜体***", ["***太字斜体***"]],
  ["**太字**だけです。", []],
  ["`*code*` と snake_case_name です。", []],
  ["```\n*code*\n```\n\n本文です。", []],
  ["An *English* only document.", []],
];

for (const [text, expected] of cases) {
  check(text, await hits(text), expected);
}

console.log(`${checks - failures.length}/${checks} passed`);
for (const failure of failures) console.error(`  x ${failure}`);
if (failures.length > 0) process.exit(1);
