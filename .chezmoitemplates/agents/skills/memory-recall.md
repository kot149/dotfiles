---
name: memory-recall
description: >-
  Search and recall relevant memories from past sessions via memsearch.
  Use when the user's question could benefit from historical context, past
  decisions, debugging notes, previous conversations, or project knowledge --
  especially questions like "what did I decide about X", "why did we do Y",
  "have I seen this before". Also use when a `[memsearch] Recall available if
  needed` capability hint was injected at session start or prompt submit.
  Typical flow: search for 3-5 chunks, expand the most relevant, optionally
  deep-drill into the original transcript via the anchor.
  Skip when the question is purely about current code state (read/grep the
  repository instead), purely about today's task, or the user asked to ignore
  memory.
allowed-tools: Bash
---

# memory-recall

Retrieve context from memsearch memory (`<project>/.memsearch/memory/*.md`,
indexed into Milvus) and return only what is useful for the current question.

This is memsearch memory, which is separate from the host agent's own memory
system.

## Running in a Subagent

Wherever this document says "subagent", it means delegating the retrieval to a
child agent with an independent context. Map it to whatever mechanism the
running agent provides.

- Claude Code: the `Agent` tool with `subagent_type: "Explore"`
- Codex CLI: `spawn_agent` (requires `features.multi_agent`), picking a
  read-only role from `[agents]` in `config.toml`

Run steps 1-4 in a subagent when one is available, so raw search output stays
out of the main conversation and only the curated summary comes back. Without a
subagent mechanism, run them inline and keep the output short.

## The memsearch Command

Use `memsearch` if it is on `PATH`, otherwise `uvx --from 'memsearch[onnx]' memsearch`.

## Project Collection

Memory is per-project, and every command needs that project's collection name.
Derive it once, from the skill's own directory (`<skill-dir>` below is the
directory this `SKILL.md` lives in):

```sh
bash -c 'if [ -n "${MEMSEARCH_DIR:-}" ]; then bash <skill-dir>/scripts/derive-collection.sh "$MEMSEARCH_DIR"; else root=$(git rev-parse --show-toplevel 2>/dev/null || true); bash <skill-dir>/scripts/derive-collection.sh ${root:+"$root"}; fi'
```

## Steps

1. **Search**: `memsearch search "<query>" --top-k 5 --json-output --default-collection <collection>`.
   Build the query from the core intent of the user's question, not its wording.
2. **Evaluate**: drop chunks that are clearly irrelevant or too generic.
3. **Expand**: for each surviving hit,
   `memsearch expand <chunk_hash> --default-collection <collection>` for the
   full markdown section.
   If expand fails with a lock or permission error (sandboxed Milvus Lite), read
   the source file directly instead: the search result carries `source`,
   `start_line` and `end_line`.
4. **Deep drill (optional)**: if an expanded chunk carries a transcript anchor
   (an HTML comment naming a transcript/rollout file and a turn) and the
   original conversation matters, run
   `memsearch transcript <path> --turn <uuid> --context 3` (the format is
   auto-detected; `--turn` may be omitted when the anchor has no turn cursor).
   If the format is not recognized, read the referenced file directly and locate
   the turn by the identifiers in the anchor.
5. **Report**: a curated summary, ordered by relevance. Per memory, the key
   content (decision, pattern, solution, context) plus its source file and date.
   If nothing relevant turned up, say so in one line.

## When the Query Is Unclear

If the question is too vague to form a search query, browse the raw markdown
first -- it is the source of truth, the index is derived from it:

```sh
MDIR="${MEMSEARCH_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.memsearch}"
ls -t "$MDIR/memory/" | head -10                      # recent daily logs
grep -h "^## " "$MDIR/memory/"*.md | sort -u | tail -40   # session headings
cat "$MDIR/memory/<YYYY-MM-DD>.md"                    # one day in full
```

Once a concrete topic surfaces, go back to `memsearch search`.
