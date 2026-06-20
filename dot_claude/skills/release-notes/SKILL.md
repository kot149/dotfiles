---
name: release-notes
description: Write the body of a GitHub release. Targets the current draft release by default; if none is found, ask the user which release to target. Compares against the previous release to summarize changes, follows the existing release-notes format in the repository, and respects any pre-existing body content in the target release. Always preserves the draft state — never publishes a draft. Invoke for requests like "リリースノート書いて", "draftのリリース本文書いて", "write release notes", or similar in any language.
---

# GitHub Release Notes Writer

Write the body of a GitHub release for the current repository, following the repo's existing style.

## Steps

1. **Locate the target release** using `gh release list --limit 20 --json name,tagName,isDraft,isPrerelease,publishedAt,createdAt`:
   - If exactly one release is in draft state (`isDraft: true`): that is the target.
   - If multiple drafts exist: list them and ask the user which one to use via `AskUserQuestion`.
   - If no draft exists: ask the user which release/tag to write notes for (offer the most recent releases as options), or whether to create a new draft. Do NOT create a release without confirmation.

2. **Fetch the target release's current state**:
   `gh release view <tag> --json name,tagName,body,isDraft,targetCommitish`
   - Record whether `isDraft` is true — it MUST remain true after the update if it was true before.
   - If `body` is non-empty, treat it as either (a) a partial draft the user has already started, or (b) a structural template to follow. Preserve its sections, headings, and any hand-written prose; only fill in / expand the change list.

3. **Find the previous release** to diff against:
   - Run `gh release list --limit 30 --json name,tagName,isDraft,publishedAt --jq 'map(select(.isDraft == false))'` and pick the most recent non-draft release whose `publishedAt` precedes the target (or the most recent published release if the target has no `publishedAt` yet).
   - If none exists (first release), diff from the repo's first commit instead.

4. **Collect changes between the previous release tag and the target ref**:
   - Target ref: the target release's `tagName` if the tag already exists, otherwise `targetCommitish` (often `main`), otherwise `HEAD`.
   - Verify the tag exists: `git rev-parse --verify <tag> 2>/dev/null`. If the target tag does not exist yet, use the branch/HEAD.
   - Run in parallel:
     - `git log <prev-tag>..<target-ref> --pretty=format:'%h %s (%an)' --no-merges`
     - `git log <prev-tag>..<target-ref> --pretty=format:'%h %s%n%b%n---' --no-merges` (for bodies, to catch `BREAKING CHANGE:` / co-author hints / linked issues)
     - `gh pr list --state merged --search "merged:>=<prev-release-date>" --limit 100 --json number,title,labels,author,mergedAt,url` to enrich with PR titles and labels when commits map to squash-merges.
   - Cross-reference commits to PRs by the `(#123)` suffix typical of squash merges.

5. **Study the repo's existing release-notes format** to match it exactly:
   - `gh release view <prev-tag> --json body --jq .body` for the immediate predecessor.
   - If the predecessor's body looks auto-generated or sparse, also inspect 1–2 earlier non-draft releases.
   - Identify:
     - Language (English / Japanese / mixed).
     - Section headings (e.g. `## Features`, `### 🚀 新機能`, `What's Changed`, Conventional-Commit grouping, etc.).
     - Whether entries link PRs (`#123`), commit SHAs, or contributor handles.
     - Whether a "Full Changelog" compare link is appended (`**Full Changelog**: https://github.com/OWNER/REPO/compare/<prev>...<target>`).
     - Bullet style, emoji usage, ordering.

6. **Draft the release body**:
   - Top priority: match the repo's established format. If the target release already has a partial body, layer on top of that structure rather than replacing it.
   - Group commits/PRs by type (features, fixes, refactors, docs, chore, etc.) using whatever taxonomy the prior releases use; fall back to Conventional Commits if there is no precedent.
   - Skip noise: pure CI tweaks, lockfile bumps, and merge commits unless the prior releases include them.
   - Call out breaking changes prominently if any commit/PR body contains `BREAKING CHANGE:` or `!:` Conventional-Commit markers.
   - Append the Full Changelog compare link if the previous releases do.
   - Write in the same language as the prior releases (default to Japanese if the repo's commit history and prior notes are Japanese, English otherwise).

7. **Show the draft to the user** before applying:
   - Print the full proposed body in a fenced block.
   - Note the target release tag, whether it is currently draft, and the previous release used for the diff.
   - Use `AskUserQuestion` to ask whether to (a) apply as-is, (b) edit and apply, or (c) cancel. Recommend (a) by listing it first with `(Recommended)`.

8. **Apply the update**, preserving draft state:
   - Write the body to a temp file in the scratchpad to avoid shell-escaping issues with multi-line content.
   - Run `gh release edit <tag> --notes-file <path>`.
   - **CRITICAL**: If the release was in draft state, do NOT pass `--draft=false` and do NOT pass any flag that would publish it. `gh release edit` preserves draft status by default — verify with `gh release view <tag> --json isDraft` after the edit and report the result to the user.
   - If the release was already published, edit it in place the same way (still no draft-state changes).

## Notes

- Never run `gh release create` or `gh release delete` as part of this skill unless the user explicitly asks to create a new release.
- Never publish a draft. If the user wants to publish, that is a separate manual step.
- If `$ARGUMENTS` is provided, treat it as a hint (e.g. a specific tag name, a theme to emphasize, or extra context to weave in).
- If the repo has no prior releases AND no body on the draft, ask the user for a preferred format (Conventional Commits grouping is the safe default) before drafting.
