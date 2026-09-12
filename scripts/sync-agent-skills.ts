#!/usr/bin/env bun
/**
 * Sync third-party agent skills pinned in config/agent-skills.toml.
 *
 * For each [[agent_skills]] entry, downloads the pinned GitHub tarball,
 * extracts only prefix/name, and places it under ~/.agents/skills/<name>
 * and/or ~/.claude/skills/<name> according to `agents`.
 *
 * Usage:
 *   bun scripts/sync-agent-skills.ts          # sync missing or changed pins
 *   bun scripts/sync-agent-skills.ts --refresh # re-download everything
 *   bun scripts/sync-agent-skills.ts --list   # print planned actions only
 *   bun scripts/sync-agent-skills.ts --check  # exit 1 if any skill is missing or outdated
 *   bun scripts/sync-agent-skills.ts --only <name[,name...]>  # sync subset
 */
import { $ } from "bun";
import { join } from "node:path";
import { tmpdir, homedir } from "node:os";
import { mkdtemp, rm, mkdir, cp } from "node:fs/promises";

const ROOT = join(import.meta.dir, "..");
const SKILLS_TOML = join(ROOT, "config", "agent-skills.toml");

type AgentSkill = {
  repo: string;
  rev: string;
  prefix: string;
  names: string[];
  agents: string[];
  flat?: boolean;
};

function storeDir(agent: string): string {
  const home = process.env.HOME ?? homedir();
  if (agent === "agents") return join(home, ".agents", "skills");
  if (agent === "claude") return join(home, ".claude", "skills");
  throw new Error(`unknown agent store: ${agent}`);
}

async function loadSkills(): Promise<AgentSkill[]> {
  const text = await Bun.file(SKILLS_TOML).text();
  const parsed = Bun.TOML.parse(text) as { agent_skills: AgentSkill[] };
  return parsed.agent_skills;
}

const PIN_FILE = ".mise-skill-pin.json";

function pin(skill: AgentSkill, name: string): string {
  return JSON.stringify([skill.repo, skill.rev, skill.prefix, skill.flat ?? false, name]);
}

export async function isCurrent(skill: AgentSkill, name: string, target: string): Promise<boolean> {
  if (!(await Bun.file(join(target, "SKILL.md")).exists())) return false;
  const marker = Bun.file(join(target, PIN_FILE));
  return await marker.exists() && await marker.text() === pin(skill, name);
}

export async function syncOne(skill: AgentSkill, name: string, target: string, dryRun: boolean) {
  const parts: string[] = [
    ...(skill.prefix ? skill.prefix.split("/") : []),
    ...(skill.flat ? [] : [name]),
  ];
  const url = `https://github.com/${skill.repo}/archive/${skill.rev}.tar.gz`;
  console.log(`${target} <- ${skill.repo}@${skill.rev.slice(0, 12)} [${parts.join("/") || "."}]`);
  if (dryRun) return;

  const work = await mkdtemp(join(tmpdir(), "agent-skills-"));
  try {
    const tgz = join(work, "repo.tar.gz");
    const res = await fetch(url);
    if (!res.ok) throw new Error(`download failed: ${url}: ${res.status}`);
    await Bun.write(tgz, res);
    const list = (await $`tar -tzf ${tgz}`.text()).trim().split("\n");
    const top = list[0].split("/")[0];
    await $`tar -xzf ${tgz} -C ${work}`;
    const src = join(work, top, ...parts);
    if (!(await Bun.file(join(src, "SKILL.md")).exists())) {
      throw new Error(`archive is missing ${parts.join("/")}/SKILL.md`);
    }
    await rm(target, { recursive: true, force: true });
    await mkdir(target, { recursive: true });
    await cp(src, target, { recursive: true });
    await Bun.write(join(target, PIN_FILE), pin(skill, name));
    console.log(`  synced ${target}`);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--list");
  const check = args.includes("--check");
  const refresh = args.includes("--refresh");
  const onlyIndex = args.indexOf("--only");
  const onlyFlag = onlyIndex >= 0 ? (args[onlyIndex + 1] ?? "") : "";
  const only = new Set(onlyFlag.split(",").filter(Boolean));

  const skills = await loadSkills();
  if (check) {
    // Skill outputs live outside [dotfiles], so drift/deletion is invisible to
    // `mise bootstrap dotfiles status`. This mode detects it.
    const missing: string[] = [];
    for (const skill of skills) {
      for (const agent of skill.agents) {
        for (const name of skill.names) {
          if (only.size > 0 && !only.has(name)) continue;
          if (!(await isCurrent(skill, name, join(storeDir(agent), name)))) missing.push(`${agent}/skills/${name}`);
        }
      }
    }
    if (missing.length > 0) {
      console.error(`missing or outdated skills:\n${missing.map((m) => `  ${m}`).join("\n")}`);
      console.error("run: mise run sync-agent-skills");
      process.exit(1);
    }
    console.log("all pinned skills current");
    process.exit(0);
  }
  for (const skill of skills) {
    for (const agent of skill.agents) {
      for (const name of skill.names) {
        if (only.size > 0 && !only.has(name)) continue;
        if (!refresh && !dryRun && await isCurrent(skill, name, join(storeDir(agent), name))) {
          console.log(`${agent}/skills/${name} present, skipping`);
          continue;
        }
        await syncOne(skill, name, join(storeDir(agent), name), dryRun);
      }
    }
  }
}
