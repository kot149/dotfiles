import { strict as assert } from "node:assert";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { $ } from "bun";
import { isCurrent, syncOne } from "../scripts/sync-agent-skills";

const work = await mkdtemp(join(tmpdir(), "skill-sync-test-"));
const originalFetch = globalThis.fetch;
try {
  const source = join(work, "repo/skills/example");
  const target = join(work, "installed");
  const archive = join(work, "repo.tar.gz");
  await mkdir(source, { recursive: true });
  await Bun.write(join(source, "SKILL.md"), "pinned skill");
  await $`tar -czf ${archive} -C ${work} repo`;
  globalThis.fetch = (async () => new Response(Bun.file(archive))) as typeof fetch;
  const skill = { repo: "owner/repo", rev: "first", prefix: "skills", names: ["example"], agents: ["agents"] };
  await Bun.write(join(target, "SKILL.md"), "legacy skill");
  assert.equal(await isCurrent(skill, "example", target), false);
  await syncOne(skill, "example", target, false);
  assert.equal(await isCurrent(skill, "example", target), true);
  const updated = { ...skill, rev: "second" };
  assert.equal(await isCurrent(updated, "example", target), false);
  await syncOne(updated, "example", target, false);
  assert.equal(await isCurrent(updated, "example", target), true);
  assert.equal(await isCurrent({ ...updated, repo: "other/repo" }, "example", target), false);
  await assert.rejects(syncOne({ ...updated, prefix: "missing" }, "example", target, false));
  assert.equal(await Bun.file(join(target, "SKILL.md")).text(), "pinned skill");
  assert.equal(await isCurrent(updated, "example", target), true);
  await rm(join(target, "SKILL.md"));
  assert.equal(await isCurrent(updated, "example", target), false);
  console.log("skill sync regression tests passed");
} finally {
  globalThis.fetch = originalFetch;
  await rm(work, { recursive: true, force: true });
}
