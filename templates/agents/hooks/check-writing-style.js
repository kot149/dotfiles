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

// Codex edits files by emitting a patch document instead of Claude's Write / Edit
// calls. Prose lives in the added / changed lines, one "+ text" or "- text" pair
// per line under a *** Add File / *** Update File header.
const PATCH_FILE = /^\*{3} (?:Add|Update) File: (.+)$/;

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
// gh fields take name=value, and read the value from a file when it is written name=@path.
const FIELD_FLAGS = ["-f", "-F", "--field", "--raw-field"];
// `-f body="$(cat reply.md)"` hands gh the prose without ever putting it on the command line,
// so the path inside the substitution is the only thing left to scan.
const SUBSTITUTED_PATH = /\$\(\s*(?:cat\s+|<\s*)([^)]+?)\s*\)|`\s*cat\s+([^`]+?)\s*`/g;
// Leading VAR=value assignments, so a path built from one can still be resolved.
const ASSIGNMENT = /(?:^|[\s;&|])([A-Za-z_]\w*)=("[^"]*"|'[^']*'|[^\s;&|]*)/g;
// `cd` into the directory a body file is written to, so a relative path still resolves.
const CD = /(?:^|[\s;&|(])cd\s+(?!-(?:\s|$))("[^"]*"|'[^']*'|[^\s;&|)]+)/g;

const unquote = (value) => value.replace(/^(['"])(.*)\1$/s, "$2");

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

/** The value a flag carries, whether spelled `--flag value` or `--flag=value`. */
const flagValue = (words, i, flag) => {
  const word = words[i];
  if (word === flag) return words[i + 1] ?? null;
  return word.startsWith(`${flag}=`) ? word.slice(flag.length + 1) : null;
};

/** The path in a `name=@path` field value, which gh reads the field from. */
const fieldFile = (value) => value?.match(/^[^=]*=@(.+)$/)?.[1] ?? null;

// `-F key=value` is a field for gh api and a file for gh pr / issue; the `key=@path`
// form is already resolved by fieldFile, so a leftover name=value is never a path.
const FIELD_SPEC = /^[A-Za-z_][\w.[\]-]*=/;

/**
 * Drop heredoc bodies. A heredoc carries data, not command words: a script written with
 * one can mention `--body-file path` without this call ever reading that path.
 */
function stripHeredocBodies(command) {
  const kept = [];
  let terminator = null;
  for (const line of command.split("\n")) {
    if (terminator !== null) {
      if (line.trim() === terminator) terminator = null;
      continue;
    }
    kept.push(line);
    const opener = line.match(/<<(?!<)-?\s*(['"]?)([A-Za-z_]\w*)\1/);
    if (opener) terminator = opener[2];
  }
  return kept.join("\n");
}

/** Every path this command could be reading a body from. Duplicates and nulls are fine. */
function bodyPaths(rawCommand) {
  const command = stripHeredocBodies(rawCommand);
  // The opening line survives the strip, so a heredoc-fed gh call still exposes its flags.
  const words = splitWords(command) ?? [];
  const paths = words.flatMap((_, i) => [
    ...FILE_FLAGS.map((flag) => flagValue(words, i, flag)),
    ...FIELD_FLAGS.map((flag) => fieldFile(flagValue(words, i, flag))),
  ]);
  for (const match of command.matchAll(SUBSTITUTED_PATH)) paths.push(match[1] ?? match[2]);
  return paths
    .map((target) => target && unquote(target))
    .filter((target) => target && target !== "-" && !FIELD_SPEC.test(target));
}

function shellVariables(command) {
  const variables = new Map();
  for (const [, name, raw] of command.matchAll(ASSIGNMENT)) {
    const value = unquote(raw);
    // A value that is itself substituted cannot be resolved, and is never a plain path.
    if (!/[$`]/.test(value)) variables.set(name, value);
  }
  return variables;
}

const expand = (target, variables) =>
  target.replace(
    /\$\{(\w+)\}|\$(\w+)/g,
    (whole, braced, bare) => variables.get(braced ?? bare) ?? whole,
  );

const expandHome = (target) =>
  target.startsWith("~") ? path.join(os.homedir(), target.slice(1)) : target;

/** The directories the command runs in: the cwd it starts in, plus every one it cd's into. */
function baseDirs(command, cwd, variables) {
  const bases = [cwd];
  for (const [, raw] of command.matchAll(CD)) {
    const target = expand(unquote(raw), variables);
    if (target.includes("$")) continue;
    bases.push(path.resolve(bases.at(-1), expandHome(target)));
  }
  return bases;
}

const readFrom = (bases, target) => {
  for (const base of bases) {
    try {
      return fs.readFileSync(path.resolve(base, target), "utf8");
    } catch {
      // Try the next directory the command runs in.
    }
  }
  return null;
};

/**
 * Pull in bodies passed by path, looking each path up in every directory the command
 * runs in. Paths that stay unreadable are reported so the call can be denied instead
 * of passing unchecked.
 */
function readBodyFiles(command, cwd) {
  const variables = shellVariables(command);
  const bases = baseDirs(command, cwd, variables);
  const texts = [];
  const unreadable = [];
  for (const target of new Set(bodyPaths(command))) {
    const resolved = expand(target, variables);
    const text = resolved.includes("$") ? null : readFrom(bases, expandHome(resolved));
    if (text === null) unreadable.push(resolved);
    else texts.push(text);
  }
  return { texts, unreadable };
}

function collectStrings(value) {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(collectStrings);
  if (value && typeof value === "object") return Object.values(value).flatMap(collectStrings);
  return [];
}

/**
 * The prose a body file carries, as separate texts.
 *
 * A JSON body holds its prose in string values, and the punctuation around them belongs
 * to the format rather than to the author. Read as one Markdown document, those braces
 * and quotes pair up with the backticks inside the prose, and a review payload of a few
 * hundred lines hides most of its sentences in phantom code spans. Splitting on the
 * string values gives every sentence a scope of its own.
 */
function bodyProse(text) {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object") return collectStrings(parsed);
  } catch {
    // Not JSON, so the file already is the prose.
  }
  return [text];
}

/**
 * Return the texts worth scanning for this call, and the body paths that could not be
 * read. Both are empty when the tool is out of scope.
 */
function targetTexts(toolName, toolInput, cwd) {
  const asMarkdown = (texts) => texts.map((text) => ({ text, ext: ".md" }));
  const scan = (targets) => ({ targets, unreadable: [] });

  if (toolName === "Bash") {
    const command = toolInput.command ?? "";
    const isGhWrite =
      GH_SUBCOMMAND.test(command) || (GH_API.test(command) && GH_API_WRITE.test(command));
    if (!isGhWrite) return scan([]);
    const { texts, unreadable } = readBodyFiles(command, cwd);
    const prose = texts.flatMap(bodyProse);
    // The command line itself is not Markdown; backticks in it are not code spans.
    return { targets: [{ text: command, ext: ".txt" }, ...asMarkdown(prose)], unreadable };
  }

  if (toolName === "Write" || toolName === "Edit") {
    const filePath = (toolInput.file_path ?? "").toLowerCase();
    if (!PROSE_SUFFIXES.some((suffix) => filePath.endsWith(suffix))) return scan([]);
    const text = toolInput.content || toolInput.new_string || "";
    return scan(text ? asMarkdown([text]) : []);
  }

  if (MCP_ATLASSIAN.test(toolName) && MCP_WRITE_OP.test(toolName)) {
    return scan(asMarkdown(collectStrings(toolInput)));
  }
  if (toolName === "apply_patch") {
    // Codex edits files by emitting a patch document instead of Claude's Write /
    // Edit calls. Prose lives in the added / removed lines under a file header.
    const targets = [];
    let currentFile = null;
    let currentText = "";
    const flush = () => {
      const filePath = (currentFile ?? "").toLowerCase();
      if (currentText && PROSE_SUFFIXES.some((suffix) => filePath.endsWith(suffix))) {
        targets.push({ text: currentText, ext: ".md" });
      }
      currentFile = null;
      currentText = "";
    };
    for (const line of String(toolInput.command ?? "").split("\n")) {
      const header = line.match(PATCH_FILE);
      if (header) {
        flush();
        currentFile = header[1];
        continue;
      }
      if (currentFile && (line.startsWith("+") || line.startsWith("-"))) {
        currentText += `${line.slice(1)}\n`;
      }
    }
    flush();
    return scan(targets);
  }

  return scan([]);
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

  const { targets, unreadable } = targetTexts(toolName, toolInput, cwd);
  if (targets.length === 0) return;

  const findings = await findIssues(targets);
  if (findings.length === 0 && unreadable.length === 0) return;

  const detail = findings
    .map(
      ({ hit, line, advice }, i) =>
        `${i + 1}. 該当: 「${hit}」\n   原文: 「${line}」\n   対応: ${advice}`,
    )
    .join("\n\n");
  const parts = ["[言い回しの矯正]\n"];
  if (findings.length > 0) {
    parts.push(
      "曖昧・翻訳調な表現が含まれています。読み手が具体的な動作を想像できる書き方に直してください。\n",
      `${detail}\n`,
    );
  }
  if (unreadable.length > 0) {
    parts.push(
      "本文を渡しているファイルを読めず、表現を確認できませんでした: " +
        unreadable.map((target) => `「${target}」`).join(", ") +
        "\n本文ファイルを先に別のコマンドで書き出してから、絶対パスを渡して投稿し直してください。\n",
    );
  }
  const reason = parts.join("\n");

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
