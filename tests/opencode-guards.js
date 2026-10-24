/**
 * Tests for the opencode guard plugin, private_dot_config/opencode/plugins/guards.ts.tmpl.
 *
 *   bun run tests/opencode-guards.js
 *
 * The template is rendered with `chezmoi execute-template`, its hook directory is
 * pointed at a temporary copy of .chezmoitemplates/agents/, and execute.before
 * is called with opencode-shaped tool calls. The hooks' own cases live in
 * tests/hooks.py and tests/writing-style.sh; these check the opencode mapping.
 * Skipped on Windows, where the plugin is not installed.
 */
import assert from "node:assert/strict";
import { $ } from "bun";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform === "win32") {
  console.log("SKIP opencode guards: the plugin is not installed on Windows");
  process.exit(0);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const bodies = path.join(root, ".chezmoitemplates", "agents");
// realpathSync: on macOS os.tmpdir() is /var/folders/..., while a process started
// there reports the resolved /private/var/folders/... from process.cwd().
const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "opencode-guards-")));
// Runs on every exit path, including the early process.exit calls and a thrown error.
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const hookDir = path.join(tmp, "hooks");
fs.cpSync(bodies, hookDir, { recursive: true });

const render = Bun.spawnSync(
  ["chezmoi", "--source", root, "execute-template", "-f", "private_dot_config/opencode/plugins/guards.ts.tmpl"],
  { cwd: root },
);
if (render.exitCode !== 0) {
  console.error(`render failed: ${render.stderr}`);
  process.exit(1);
}
const homeDirs = /\[[^\]]*\]\.map\(\(dir\) => path\.join\(homedir\(\), dir\)\)/;
const source = render.stdout.toString();
if (!homeDirs.test(source)) {
  console.error("HOOK_DIRS definition not found in the rendered plugin");
  process.exit(1);
}
const pluginFile = path.join(tmp, "guards.ts");
fs.writeFileSync(pluginFile, source.replace(homeDirs, JSON.stringify([hookDir])));

// A uv project, where the package-manager guard denies pip.
const uvProject = path.join(tmp, "uvproj");
fs.mkdirSync(uvProject);
fs.writeFileSync(path.join(uvProject, "uv.lock"), "");
fs.writeFileSync(path.join(uvProject, "pyproject.toml"), "");
const plain = path.join(tmp, "plain");
fs.mkdirSync(plain);

async function register(plugin, directory) {
  assert.equal(typeof plugin.id, "string");
  assert.ok(plugin.id.length > 0);
  const registrations = [];
  await plugin.setup({
    location: { directory },
    tool: { hook: async (name, callback) => {
      assert.equal(name, "execute.before");
      registrations.push(callback);
      return { dispose() {} };
    } },
  });
  assert.equal(registrations.length, 1, `${plugin.id} registers one v2 hook`);
  return registrations[0];
}
const { default: guards } = await import(pluginFile);
assert.equal(guards.id, "guards");
const before = await register(guards, uvProject);

const prose = "判断は安全側に" + "倒す。";
// [expected, opencode tool, args, reason substring when blocked]
const cases = [
  ["pass", "shell", { command: "git status" }],
  ["block", "shell", { command: "pip install requests" }, "Package Manager Mismatch"],
  ["block", "shell", { command: "rtk pip install requests" }, "Package Manager Mismatch"],
  ["block", "shell", { command: "git status && FOO=1 rtk pip install requests" }, "Package Manager Mismatch"],
  ["block", "shell", { command: "rtk proxy pip install requests" }, "Package Manager Mismatch"],
  ["pass", "shell", { command: "pip install requests", workdir: plain }],
  ["block", "shell", { command: `gh pr create --title t --body "${prose}"` }, "倒す"],
  ["block", "write", { path: "/tmp/a.md", content: prose }, "倒す"],
  ["pass", "write", { path: "/tmp/a.ts", content: prose }],
  ["block", "edit", { path: "/tmp/a.md", oldString: "x", newString: prose }, "倒す"],
  ["block", "patch", { patchText: `*** Begin Patch\n*** Add File: a.md\n+${prose}\n*** End Patch` }, "倒す"],
  ["pass", "read", { path: "/tmp/a.md" }],
];

let failures = 0;
for (const [expected, tool, args, reason] of cases) {
  // A fresh session each case: writing-style passes an identical retry in the same session.
  const event = { tool, sessionID: `opencode-guards-${crypto.randomUUID()}`, id: "c", input: { ...args } };
  let actual = "pass";
  let message = "";
  try {
    await before(event);
  } catch (error) {
    actual = "block";
    message = String(error?.message ?? error);
  }
  const ok = actual === expected && (actual === "pass" || message.includes(reason));
  if (!ok) failures++;
  console.log(`${ok ? "OK  " : "FAIL"} ${tool} ${JSON.stringify(args)} -> ${actual}${ok ? "" : `: ${message}`}`);
}

console.log(`${cases.length - failures}/${cases.length} guard cases passed`);

// A deterministic hook checks the exact bridge payload and deny/ask handling.
const fixture = path.join(hookDir, "fixture.js");
fs.writeFileSync(fixture, `
const input = await Bun.stdin.json();
if (input.tool_input.command === "timeout") await Bun.sleep(60_000);
if (input.tool_input.command === "empty") process.exit(0);
if (input.tool_input.command === "invalid") { console.log("not JSON"); process.exit(0); }
console.log(JSON.stringify({ hookSpecificOutput: {
  permissionDecision: input.tool_input.command === "ask" ? "ask" : "deny",
  permissionDecisionReason: JSON.stringify({ payload: input, processCwd: process.cwd() }),
} }));
`);
const fixtureFile = path.join(tmp, "fixture-guards.ts");
fs.writeFileSync(fixtureFile, source
  .replace(homeDirs, JSON.stringify([hookDir]))
  .replace(/^const HOOKS: Hook\[\] = .*$/m, `const HOOKS: Hook[] = ${JSON.stringify([
    { name: "fixture", file: "fixture.js", runner: "bun", tools: ["bash", "write", "edit", "apply_patch"] },
  ])}`));
const fixtureBefore = await register((await import(fixtureFile)).default, uvProject);
for (const [tool, input, toolName, toolInput] of [
  ["shell", { command: "rtk proxy git status", workdir: "../plain" }, "Bash", { command: "git status" }],
  ["write", { path: "a.md", content: "text" }, "Write", { file_path: "a.md", content: "text" }],
  ["edit", { path: "a.md", oldString: "old", newString: "new", replaceAll: true }, "Edit", { file_path: "a.md", old_string: "old", new_string: "new" }],
  ["patch", { patchText: "patch document" }, "apply_patch", { command: "patch document" }],
]) {
  const cwd = tool === "shell" ? plain : uvProject;
  await assert.rejects(fixtureBefore({ tool, input, sessionID: "fixture-session" }), (error) => {
    assert.deepEqual(JSON.parse(error.message), {
      payload: { hook_event_name: "PreToolUse", session_id: "fixture-session", cwd, tool_name: toolName, tool_input: toolInput },
      processCwd: cwd,
    });
    return true;
  });
}
await assert.rejects(fixtureBefore({ tool: "shell", input: { command: "ask" } }), /user's confirmation/);
for (const input of [undefined, null, "invalid", {}]) {
  await before({ tool: "shell", input });
}
console.log("OK   v2 payload mapping, cwd, session ID, deny, ask, malformed input");
for (const command of ["empty", "invalid"]) {
  await fixtureBefore({ tool: "shell", input: { command } });
}
const timeoutFile = path.join(tmp, "timeout-guards.ts");
const fixtureSource = fs.readFileSync(fixtureFile, "utf8");
assert.ok(fixtureSource.includes("const TIMEOUT_MS = 30_000"));
fs.writeFileSync(timeoutFile, fixtureSource.replace("const TIMEOUT_MS = 30_000", "const TIMEOUT_MS = 100"));
const timeoutBefore = await register((await import(timeoutFile)).default, uvProject);
const warnings = [];
const warn = console.warn;
console.warn = (message) => warnings.push(message);
try {
  await timeoutBefore({ tool: "shell", input: { command: "timeout" } });
} finally {
  console.warn = warn;
}
assert.ok(warnings.some((message) => message.includes("timed out after 100 ms")));
console.log("OK   empty/invalid output and timeout retain fail-open behavior");

// A fake executable keeps RTK coverage independent of installed rewrite rules.
const sentinel = path.join(tmp, "should-not-exist");
const literalCommand = `echo $(touch ${sentinel})`;
const bin = path.join(tmp, "bin");
fs.mkdirSync(bin);
fs.writeFileSync(path.join(bin, "rtk"), '#!/bin/sh\n[ "$2" = "empty" ] && exit 0\n[ "$2" = "fail" ] && exit 1\nprintf "rtk proxy %s\\n" "$2"\n', { mode: 0o755 });
const { default: rtk } = await import(path.join(root, "private_dot_config/opencode/plugins/rtk.ts"));
assert.equal(rtk.id, "rtk");
$.env({ ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}` });
try {
  const rewrite = await register(rtk, uvProject);
  for (const [tool, command, expected] of [
    ["shell", "git status", "rtk proxy git status"],
    ["shell", literalCommand, `rtk proxy ${literalCommand}`],
    ["shell", "empty", "empty"],
    ["shell", "fail", "fail"],
    ["read", "git status", "git status"],
  ]) {
    const event = { tool, input: { command } };
    await rewrite(event);
    assert.equal(event.input.command, expected);
  }
  for (const input of [undefined, null, "invalid", {}, { command: 123 }]) {
    await rewrite({ tool: "shell", input });
  }
} finally {
  $.env(process.env);
}
assert.equal(fs.existsSync(sentinel), false);
console.log("OK   RTK v2 registration, mutable input, literal command, passthrough");
process.exit(failures ? 1 : 0);
