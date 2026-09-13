---
name: dedup
description: Detect duplicate/similar code using the `similarity` NixOS package, let the user select which duplicates to fix, then refactor and commit each one. Use when asked to find or fix duplicate code, reduce code duplication, or DRY up the codebase.
---

# Dedup — Detect and Fix Duplicate Code

Scan the current project for duplicate code using `similarity` (NixOS), present prioritized findings, let the user pick which ones to fix, then refactor and commit each selection.

## Asking the user to choose

Where this document says "ask the user to choose", present the options and wait for a decision. On agents with a selection UI tool (`AskUserQuestion` and similar), use it; on agents without one, present the same options as a numbered plain-text list and let the user reply with numbers or free text. Either way, do not proceed until the user has answered.

## Step 0: Verify context

Confirm we are in a git repository:

```bash
git rev-parse --show-toplevel
```

If not a git repo, present the following to the user in Japanese and stop:

```
Git リポジトリ内ではないため、中止しました。
```

## Step 1: Detect project languages

Count source files by extension to determine which analyzers to run:

```bash
# Count files per extension (skip node_modules, .git, dist, build, target, vendor)
find . \( \
  -path ./node_modules -o \
  -path ./.git -o \
  -path ./dist -o \
  -path ./build -o \
  -path ./target -o \
  -path ./vendor \
) -prune -o -type f -print \
| grep -oE '\.[a-zA-Z0-9]+$' \
| sort | uniq -c | sort -rn | head -20
```

Based on the counts, select the analyzers to run:

| Extensions | Analyzer binary |
|---|---|
| `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs` | `similarity-ts` |
| `.py` | `similarity-py` |
| `.rs` | `similarity-rs` |
| `.go` | `similarity-generic --language go` |
| `.java` | `similarity-generic --language java` |
| `.c`, `.h` | `similarity-generic --language c` |
| `.cpp`, `.cc`, `.cxx`, `.hpp` | `similarity-generic --language cpp` |
| `.cs` | `similarity-generic --language csharp` |
| `.rb` | `similarity-generic --language ruby` |
| `.css`, `.scss`, `.sass` | `similarity-css` |
| `.php` | `similarity-php` |
| `.ex`, `.exs` | `similarity-elixir` |

Only run analyzers for languages with 5+ source files. Skip test files if they are isolated to a `test/` or `__tests__/` tree (exclude via `--exclude`).

## Step 2: Run analyzers

For each selected analyzer, run via `nix shell nixpkgs#similarity --command <binary>`:

```bash
# Example for TypeScript/JavaScript:
nix shell nixpkgs#similarity --command similarity-ts \
  --min-lines 5 \
  --exclude node_modules \
  --exclude dist \
  --exclude build \
  --exclude .git \
  .

# Example for Python:
nix shell nixpkgs#similarity --command similarity-py \
  --min-lines 5 \
  .

# Example for generic (Go):
nix shell nixpkgs#similarity --command similarity-generic \
  --language go \
  --threshold 0.85 \
  .
```

Capture all output. If a tool takes longer than 60 seconds, kill it and note the timeout.

## Step 3: Parse and score findings

Parse the raw output. Each finding is one of:

- **Cluster**: a group of N functions that are all similar to each other
- **Pair**: two functions that are similar

Compute a **priority score** for each finding:

```
priority_score = similarity_pct × best_score × cluster_size_bonus
  where cluster_size_bonus = log2(N) for cluster of N functions, 1.0 for pair
```

Fields to extract per finding:
- `type`: `cluster` or `pair`
- `language`: which analyzer found it
- `similarity_pct`: the similarity percentage (e.g. 95.56)
- `best_score`: the score printed by the tool (larger = more code)
- `locations`: list of `{file, start_line, end_line, function_name}` entries
- `cluster_size`: number of functions (1 for pair → treat as 2)
- `priority_score`: computed above
- `estimated_lines_saved`: `(cluster_size - 1) × avg_function_lines`

Sort all findings descending by `priority_score`. Take the top 20 (or fewer if less exist).

Deduplicate: if the same file+line range appears in multiple findings, merge them into one.

## Step 4: Present findings to user

Format findings as a numbered list. For each finding show:
- **Priority rank** and estimated lines saved
- Similarity percentage and score
- List of duplicate locations (file:line_range function_name)
- A one-line description of what is duplicated

Example output to user (present the following to the user in Japanese):

```
重複コードの検出結果（優先度順）：

1. [TS] 95.6% 類似 — 推定 62行削減
   - routes/fileUpload.ts:75-107  handleXmlUpload
   - routes/fileUpload.ts:109-139 handleYamlUpload
   → XMLとYAMLのアップロードハンドラーがほぼ同一ロジック

2. [TS] 93.1% 類似 — クラスタ5件、推定 56行削減
   - routes/updateProductReviews.ts:14-30  updateProductReviews
   - data/static/codefixes/forgedReviewChallenge_1.ts:1-15
   - data/static/codefixes/forgedReviewChallenge_2_correct.ts:1-15
   - data/static/codefixes/noSqlReviewsChallenge_2.ts:1-14
   - data/static/codefixes/noSqlReviewsChallenge_3_correct.ts:1-20
   → レビュー更新関数が複数ファイルに重複
...
```

Then ask the user to choose which ones to fix, allowing multiple selections (present the question and options to the user in Japanese):

- question: `どの重複を修正しますか？（複数選択可）`
- one option per finding: `#{rank}. {short description}`, annotated with `{similarity}% 類似, 推定{N}行削減`

If the user selects nothing or cancels, present the following to the user in Japanese and stop gracefully:

```
何も選択されなかったため、中止しました。修正は行っていません。
```

## Step 5: Fix each selected duplicate

For each selected finding, fix it in order. **Read all involved files in full before editing.**

### Fixing strategy

**Pair (2 functions)**:
1. Read both functions carefully.
2. Identify the differences (usually 1–3 variable names or small logic branches).
3. Extract a shared helper function that accepts the differing parts as parameters.
4. Replace both originals with calls to the helper.
5. Place the helper in the same file (near the callers), or in a shared utility module if it belongs to a different concern.

**Cluster (3+ functions)**:
1. Read all functions.
2. Find the common pattern and all variations.
3. Extract a single shared function that covers all cases (using parameters or a strategy/options object for variations).
4. Update all call sites.

### Rules for refactoring

- **Do not change behavior** — the refactored code must be functionally identical.
- **Do not rename existing exported symbols** unless they were the duplicated functions themselves.
- **Name the extracted helper descriptively** — not `common`, `shared`, or `util`.
- **If test files exist for the affected code**, update imports/calls in tests too.
- **Immutability**: never mutate parameters; create new objects.
- **No new comments** unless the extracted logic has a non-obvious invariant.

### Apply edits

Apply edits with file edit tools. Verify with a quick `grep` that all old function names at the old locations have been replaced.

After each finding is fixed, run the project's test command if one exists:

```bash
# Detect test runner
if [ -f package.json ]; then
  npm test 2>&1 | tail -20
elif [ -f Cargo.toml ]; then
  cargo test 2>&1 | tail -20
elif [ -f go.mod ]; then
  go test ./... 2>&1 | tail -20
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  python -m pytest 2>&1 | tail -20
fi
```

If tests fail, investigate and fix before continuing to the next item. Do not commit broken code.

## Step 6: Commit each fix

After each fixed finding passes tests, commit it as a separate commit using the `commit` skill logic:

- Determine commit type: almost always `refactor:`
- Subject: describe what was extracted (e.g. `refactor: extract shared upload handler from handleXmlUpload and handleYamlUpload`)
- Keep under 72 characters

```bash
git add -p   # or stage specific files
git commit -m "refactor: <description>"
```

One commit per selected finding. Do NOT bundle multiple fixes into one commit.

## Step 7: Report

After all selected fixes are committed, present the following to the user in Japanese (fill in the numbers, hashes, and reasons):

```
重複の修正が完了しました。
- 修正件数: <N>件
- 削減行数（推定）: <N>行
- 作成コミット:
  - <sha> <subject>
  - ...
- スキップした項目:
  - <finding> — <理由>
```

The report must cover only the following points:

- How many duplicates were fixed
- Total lines removed (estimate)
- Commits created (hashes + subjects)
- Any findings that were skipped (with reason)

---

## Notes

- If `nix` is not available, present the following to the user in Japanese and stop:

  ```
  `nix` が利用できないため、中止しました。Nix をインストールするか、`nixpkgs#similarity` を環境に追加してください。
  ```

- If a finding spans auto-generated files (e.g. `*.pb.go`, `*.generated.ts`), skip it automatically and note the skip in Japanese (e.g. `自動生成ファイルのためスキップしました: <path>`).
- If the duplicated code is in test fixtures or intentionally varied examples (e.g. `codefixes/` directory for a CTF), present the following to the user in Japanese and confirm before fixing — it may be intentional:

  ```
  意図的な重複の可能性があります。修正してよいですか?: <finding> (<path>)
  ```
- If `$ARGUMENTS` is provided, treat it as a path to limit the scan scope (e.g. `src/`, `lib/`).
