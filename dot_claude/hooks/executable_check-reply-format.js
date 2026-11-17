#!/usr/bin/env bun
/**
 * Stop hook: when the final Japanese reply uses italics or a bullet list whose items are not parallel, block the stop and ask Claude to rewrite the reply.
 *
 * The checks are textlint rules check-writing-style.js also applies to written documents, so replies and files follow the same rules.
 */
import { TextlintKernel } from "@textlint/kernel@15.8.0";
import markdownPlugin from "@textlint/textlint-plugin-markdown@15.8.0";
import fs from "node:fs";
import parallelListRule from "./textlint-rules/textlint-rule-ja-parallel-list.js";
import italicRule from "./textlint-rules/textlint-rule-no-italic.js";

const textOf = (content) => {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block?.type === "text")
    .map((block) => block.text ?? "")
    .join("\n");
};

/** The last assistant text in the transcript, for Claude Code versions without last_assistant_message. */
function lastReply(transcriptPath) {
  let lines;
  try {
    lines = fs.readFileSync(transcriptPath, "utf8").split("\n");
  } catch {
    return "";
  }
  for (const line of lines.reverse()) {
    try {
      const entry = JSON.parse(line);
      const text = textOf(entry.message?.content);
      if (entry.type === "assistant" && text.trim()) return text;
    } catch {
      // A partial line at the end of the file.
    }
  }
  return "";
}

let payload;
try {
  payload = JSON.parse(await Bun.stdin.text());
} catch {
  process.exit(0);
}
if (payload.stop_hook_active) process.exit(0);

const reply = payload.last_assistant_message || lastReply(payload.transcript_path ?? "");
if (!reply.trim()) process.exit(0);

const { messages } = await new TextlintKernel().lintText(reply, {
  ext: ".md",
  plugins: [{ pluginId: "markdown", plugin: markdownPlugin.default ?? markdownPlugin }],
  rules: [
    { ruleId: "no-italic", rule: italicRule.linter, options: true },
    { ruleId: "ja-parallel-list", rule: parallelListRule.linter, options: true },
  ],
});
if (messages.length === 0) process.exit(0);

const findings = messages
  .map((m, i) => `${i + 1}. 該当: 「${reply.slice(...m.range)}」\n   対応: ${m.message}`)
  .join("\n");
console.log(
  JSON.stringify({
    decision: "block",
    reason:
      "直前の返信の書式に指摘があります。\n" +
      `${findings}\n` +
      "指摘に従って同じ返信を書き直してください。作業やツール呼び出しはやり直さないでください。",
  }),
);
