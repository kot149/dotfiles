/**
 * Tests for the opencode guard plugin, private_dot_config/opencode/plugins/guards.ts.tmpl.
 *
 *   bun run tests/opencode-guards.js
 *
 * The template is rendered with `chezmoi execute-template`, its hook directory is
 * pointed at a temporary copy of .chezmoitemplates/agents/, and tool.execute.before
 * is called with opencode-shaped tool calls. The hooks' own cases live in
 * tests/hooks.py and tests/writing-style.sh; these check the opencode mapping.
 * Skipped on Windows, where the plugin is not installed.
 */
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
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-guards-"));
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

const { GuardsOpenCodePlugin } = await import(pluginFile);
const before = (await GuardsOpenCodePlugin({ directory: uvProject }))["tool.execute.before"];

const prose = "判断は安全側に" + "倒す。";
// [expected, opencode tool, args, reason substring when blocked]
const cases = [
  ["pass", "bash", { command: "git status" }],
  ["block", "bash", { command: "pip install requests" }, "Package Manager Mismatch"],
  ["block", "bash", { command: "rtk pip install requests" }, "Package Manager Mismatch"],
  ["block", "bash", { command: "git status && FOO=1 rtk pip install requests" }, "Package Manager Mismatch"],
  ["block", "bash", { command: "rtk proxy pip install requests" }, "Package Manager Mismatch"],
  ["pass", "bash", { command: "pip install requests", workdir: plain }],
  ["block", "bash", { command: `gh pr create --title t --body "${prose}"` }, "倒す"],
  ["block", "write", { filePath: "/tmp/a.md", content: prose }, "倒す"],
  ["pass", "write", { filePath: "/tmp/a.ts", content: prose }],
  ["block", "edit", { filePath: "/tmp/a.md", oldString: "x", newString: prose }, "倒す"],
  ["block", "apply_patch", { patchText: `*** Begin Patch\n*** Add File: a.md\n+${prose}\n*** End Patch` }, "倒す"],
  ["pass", "read", { filePath: "/tmp/a.md" }],
];

let failures = 0;
for (const [expected, tool, args, reason] of cases) {
  // A fresh session each case: writing-style passes an identical retry in the same session.
  const input = { tool, sessionID: `opencode-guards-${crypto.randomUUID()}`, callID: "c" };
  let actual = "pass";
  let message = "";
  try {
    await before(input, { args: { ...args } });
  } catch (error) {
    actual = "block";
    message = String(error?.message ?? error);
  }
  const ok = actual === expected && (actual === "pass" || message.includes(reason));
  if (!ok) failures++;
  console.log(`${ok ? "OK  " : "FAIL"} ${tool} ${JSON.stringify(args)} -> ${actual}${ok ? "" : `: ${message}`}`);
}

console.log(`${cases.length - failures}/${cases.length} passed`);
process.exit(failures ? 1 : 0);
