#!/usr/bin/env bun
/**
 * Block Claude-flavored Japanese phrasing before it lands in a document, a ticket, or a PR.
 *
 * Covers Markdown and plain-text writes, Jira / Confluence create-update-comment
 * calls, and the `gh` commands that post issue / PR / release bodies and comments.
 *
 * Every hit is denied rather than handed to the permission prompt, so the advice
 * always reaches the model. Repeating the identical call is the way to override a
 * hit that is a false positive or a deliberate choice.
 *
 * The rules themselves live in ./textlint-rules/ as a plain textlint rule, so the
 * same checks run from the CLI:
 *
 *   bunx --bun textlint --no-textlintrc --rulesdir ~/.claude/hooks/textlint-rules doc.md
 *
 * Dependencies are pinned in the import specifiers and installed on demand by
 * Bun, so there is no node_modules to keep in sync.
 */
import { TextlintKernel } from "@textlint/kernel@15.8.0";
import markdownPlugin from "@textlint/textlint-plugin-markdown@15.8.0";
import textPlugin from "@textlint/textlint-plugin-text@15.8.0";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import rule from "./textlint-rules/textlint-rule-ja-ai-phrasing.js";

const PROSE_SUFFIXES = [".md", ".markdown", ".mdx", ".txt"];

// How much of the offending line to quote back.
const LINE_EXCERPT = 120;

const GH_SUBCOMMAND = /\bgh\s+(?:pr|issue|release)\s+(?:create|edit|comment|review|reply|update)\b/;
const GH_API = /\bgh\s+api\b/;
const GH_API_WRITE =
  /(?:-X|--method)\s+(?:POST|PATCH|PUT|post|patch|put)\b|(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)/;

const MCP_ATLASSIAN = /^mcp__.*(?:jira|confluence|atlassian)/i;
const MCP_WRITE_OP = /(?:create|edit|update|add|post|comment)/i;

const FILE_FLAGS = ["--body-file", "-F", "--input"];

/** Split a command line the way a POSIX shell would. Null when the quoting is unbalanced. */
function splitWords(command) {
  const words = [];
  let word = null;
  let quote = null;
  for (let i = 0; i < command.length; i += 1) {
    const c = command[i];
    if (quote) {
      if (c === quote) quote = null;
      else if (quote === '"' && c === "\\" && i + 1 < command.length) word += command[++i];
      else word += c;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      word ??= "";
    } else if (c === "\\" && i + 1 < command.length) {
      word = (word ?? "") + command[++i];
    } else if (/\s/.test(c)) {
      if (word !== null) words.push(word);
      word = null;
    } else {
      word = (word ?? "") + c;
    }
  }
  if (quote) return null;
  if (word !== null) words.push(word);
  return words;
}

/** Pull in bodies passed by path. Heredocs break the splitter, so failures are ignored. */
function readBodyFiles(command, cwd) {
  const words = splitWords(command);
  if (!words) return [];

  const texts = [];
  for (const flag of FILE_FLAGS) {
    words.forEach((word, i) => {
      let target = null;
      if (word === flag && i + 1 < words.length) target = words[i + 1];
      else if (word.startsWith(`${flag}=`)) target = word.slice(flag.length + 1);
      if (!target || target === "-") return;

      const expanded = target.startsWith("~") ? path.join(os.homedir(), target.slice(1)) : target;
      try {
        texts.push(fs.readFileSync(path.resolve(cwd, expanded), "utf8"));
      } catch {
        // Unreadable or nonexistent paths are simply not scanned.
      }
    });
  }
  return texts;
}

function collectStrings(value) {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(collectStrings);
  if (value && typeof value === "object") return Object.values(value).flatMap(collectStrings);
  return [];
}

/** Return the texts worth scanning for this call, empty when the tool is out of scope. */
function targetTexts(toolName, toolInput, cwd) {
  const asMarkdown = (texts) => texts.map((text) => ({ text, ext: ".md" }));

  if (toolName === "Bash") {
    const command = toolInput.command ?? "";
    const isGhWrite =
      GH_SUBCOMMAND.test(command) || (GH_API.test(command) && GH_API_WRITE.test(command));
    if (!isGhWrite) return [];
    // The command line itself is not Markdown; backticks in it are not code spans.
    return [{ text: command, ext: ".txt" }, ...asMarkdown(readBodyFiles(command, cwd))];
  }

  if (toolName === "Write" || toolName === "Edit") {
    const filePath = (toolInput.file_path ?? "").toLowerCase();
    if (!PROSE_SUFFIXES.some((suffix) => filePath.endsWith(suffix))) return [];
    const text = toolInput.content || toolInput.new_string || "";
    return text ? asMarkdown([text]) : [];
  }

  if (MCP_ATLASSIAN.test(toolName) && MCP_WRITE_OP.test(toolName)) {
    return asMarkdown(collectStrings(toolInput));
  }

  return [];
}

const kernel = new TextlintKernel();

const lintOptions = (ext) => ({
  ext,
  plugins: [
    { pluginId: "markdown", plugin: markdownPlugin.default ?? markdownPlugin },
    { pluginId: "text", plugin: textPlugin.default ?? textPlugin },
  ],
  rules: [{ ruleId: "ja-ai-phrasing", rule: rule.linter, options: true }],
});

async function findIssues(targets) {
  const findings = [];
  const seen = new Set();
  for (const { text, ext } of targets) {
    const lines = text.split("\n");
    const { messages } = await kernel.lintText(text, lintOptions(ext));
    for (const message of messages) {
      const source = (lines[message.line - 1] ?? "").trim();
      const line = source.length > LINE_EXCERPT ? `${source.slice(0, LINE_EXCERPT)}…` : source;
      const hit = message.range ? text.slice(...message.range) : "";
      const key = `${message.message}\0${hit}\0${line}`;
      if (seen.has(key)) continue;
      seen.add(key);
      findings.push({ hit, line, advice: message.message });
    }
  }
  return findings;
}

// A denied call arms a one-shot pass keyed on its exact content, so repeating the
// same call goes through. That keeps the advice reaching the model on the first
// try while leaving a way past a false positive.
const OVERRIDE_DIR = path.join(os.homedir(), ".cache", "claude-writing-style");
const OVERRIDE_TTL_MS = 600_000;

function overrideKey(sessionId, toolName, targets) {
  const digest = createHash("sha256");
  for (const part of [sessionId, toolName, ...targets.map((t) => t.text)]) {
    digest.update(`${part}\0`);
  }
  return digest.digest("hex");
}

/** True when this exact call was denied a moment ago, so it is a deliberate retry. */
function consumeOverride(key) {
  const file = path.join(OVERRIDE_DIR, key);
  try {
    const fresh = Date.now() - fs.statSync(file).mtimeMs < OVERRIDE_TTL_MS;
    fs.rmSync(file);
    return fresh;
  } catch {
    return false;
  }
}

function armOverride(key) {
  try {
    fs.mkdirSync(OVERRIDE_DIR, { recursive: true });
    for (const name of fs.readdirSync(OVERRIDE_DIR)) {
      const stale = path.join(OVERRIDE_DIR, name);
      try {
        if (Date.now() - fs.statSync(stale).mtimeMs >= OVERRIDE_TTL_MS) fs.rmSync(stale);
      } catch {
        // Another process may have cleaned it up first.
      }
    }
    fs.writeFileSync(path.join(OVERRIDE_DIR, key), "");
  } catch {
    // The override is a convenience; losing it only costs one extra retry.
  }
}

function decide(decision, reason) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: decision,
        permissionDecisionReason: reason,
      },
    }),
  );
  process.exit(0);
}

async function main() {
  let payload;
  try {
    payload = JSON.parse(await Bun.stdin.text());
  } catch {
    return;
  }

  const toolName = payload.tool_name ?? "";
  const toolInput = payload.tool_input ?? {};
  const cwd = payload.cwd || process.cwd();

  const targets = targetTexts(toolName, toolInput, cwd);
  if (targets.length === 0) return;

  const findings = await findIssues(targets);
  if (findings.length === 0) return;

  const detail = findings
    .map(
      ({ hit, line, advice }, i) =>
        `${i + 1}. 該当: 「${hit}」\n   原文: 「${line}」\n   対応: ${advice}`,
    )
    .join("\n\n");
  const reason =
    "[言い回しの矯正]\n\n" +
    "曖昧・翻訳調な表現が含まれています。読み手が具体的な動作を想像できる書き方に直してください。\n\n" +
    `${detail}\n`;

  console.error(reason);

  const key = overrideKey(payload.session_id ?? "", toolName, targets);
  if (consumeOverride(key)) return;

  const command = toolName === "Bash" ? (toolInput.command ?? "") : "";
  if (process.env.FORCE_STYLE === "1" || command.includes("FORCE_STYLE=1")) return;

  armOverride(key);
  let hint =
    "\n表現を直して実行し直してください。" +
    "指摘が誤検知、または意図した表現である場合に限り、" +
    "同じ内容のまま同じ操作をもう一度実行すれば通過します。";
  if (toolName === "Bash") hint += "\nコマンド先頭に FORCE_STYLE=1 を付けても通過します。";
  decide("deny", reason + hint);
}

await main();
