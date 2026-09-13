---
name: trim-comments
description: Skill for shortening comments and docstrings in code, plus documents such as Markdown docs. Keep only non-obvious information that cannot be read from elsewhere, and delete what can be read. Consolidate duplicated explanations in one appropriate place. Use when the user asks things like "shorten the comments", "clean up the comments", "cut the redundant comments", "slim down the docstrings", "trim the docs", "make the README concise", "trim comments", 「コメントを短くして」「コメントを整理して」「冗長なコメントを削って」「docstringをスリムにして」「ドキュメントを削って」「READMEを簡潔にして」, or any similar phrasing in English or Japanese.
---

# trim-comments

Skill for trimming comments and docstrings in code, plus Markdown documents such as READMEs and design docs. One principle: **do not write what can be read elsewhere. Write only what cannot.**

For code targets, never change the code itself (logic, identifier names, signatures). Change only comments and docstrings. For document targets, keep the heading structure, figures, code examples, and other structure, and trim only redundant prose.

## Steps

### 1. Fix the scope

Priority:

1. If the user named files or directories, follow that.
2. With no scope and inside a Git repository, use files with uncommitted changes (`git status --short`). With no uncommitted changes, use files changed from the base on the current branch (`git diff --name-only origin/HEAD...HEAD`).
3. With neither, or outside Git, present the following to the user in Japanese to confirm the target. Never target the whole repository on your own.

  ```
  対象範囲を確認させてください。どのファイル・ディレクトリを対象にしますか? (リポジトリ全体は対象にしません)
  ```

When many files match (rule of thumb: over 20), show the file list and present the following to the user in Japanese to confirm before proceeding:

```
対象ファイルが<N>件あります:
- <file1>
- <file2>
- ...

この範囲で進めてよいですか?
```

READMEs, design docs, and other Markdown documents can be targets alongside code files. Determine the scope by the priority above without distinguishing code from prose.

### 2. Collect and classify comments and prose

For code files, classify each comment and docstring; for Markdown documents, each paragraph and bullet; into the following 4 buckets. For documents, read "readable from code" as "readable from other parts of the document (headings, other paragraphs, figures, code examples)".

#### Keep (non-obvious information)

- **Why**: the reason for the chosen implementation, rejected alternatives, counterintuitive behavior. When intentionally deviating from the spec, keep what is sacrificed too ("this fallback drops one label the original implementation shows")
- **Constraints / invariants**: premises invisible in the code (call order, thread safety, units, ranges)
- **Sentinel meaning**: when a return value can be `None`, an empty collection, `-1`, etc., what it represents. "A `None` from failure" and "a `None` that is the legitimate final answer" branch differently on the caller side. Do not drop these as collateral when cutting whole `Args:` / `Returns:` sections
- **External factors**: references to external system specs or bugs, issues/tickets/spec links, reasons for workarounds
- **Pitfalls**: why a seemingly correct change breaks things ("changing this to X breaks Y")
- **TODO / FIXME / HACK** with concrete content. When unverified values or provisional defaults remain, attach a trackable ticket ID (`TODO(ABC-123):`)

#### Cut (readable from code)

- Explanations that only trace what the code does (`// get the user` right above `getUser()`)
- Paraphrases of identifier names or signatures (`@param userId the user ID`)
- Play-by-play section headers (`// validation`, `// main logic`)
- Repeated type information (the equivalent of `@return {string}` in a language with type annotations)
- Trivial docstrings (getters/setters, helpers whose name says it all)
- The investigation path or process ("checked N sources", "the port origin had no such logic", "where I looked without finding it"). Keep only the conclusion
- Redefinitions of domain terms already covered by the terms used in the code

#### Shorten

- Items with keep-worthy information that are verbose. Compress the non-obvious part into 1-2 sentences.
- One paragraph = one claim. Reorder into "claim, reason, (supplement)". When a paragraph exceeds 5 lines, suspect 2 or more claims are mixed (a guideline, not a strict limit).
- Cut docstrings down to "one-line summary + non-obvious notes". From parameter lists, keep only what names and types do not tell you (units, null meaning, side effects, etc.).
- Keep sources to one pointer per claim (`entity_helper.py:73-152`, an issue number).

#### Move / consolidate (duplicates)

- When the same explanation appears in several places, keep it in the single best place and delete the rest. Placement criteria:
  - Implementation details go in the comment at the implementation
  - Contracts the caller must know (argument constraints, side effects, exceptions) go in the function/method docstring
  - Cross-module design decisions go in the module-top comment or the README/design doc (only when one already exists. Never create a new document on your own)
- When the criteria above do not settle it, keep it on the side that actually pays the constraint (the relevant branch/implementation) and delete it from the upper levels (module top, class, parent function).
- When a caller-side comment says the same thing as the callee docstring, delete the caller side.
- When the keep side lacks information, supplement it from the delete side before deleting.

#### Common collapse patterns

| Pattern | Fix |
|---|---|
| 2 or more claims in one paragraph ("A. And B...") | Split the paragraph. If one side is not a keeper, delete it |
| Tracing branches in prose ("when X..., otherwise...") | Delete it. The code already has it |
| One sentence appended per review comment | Remove the accretion marks and rewrite the paragraph |
| Long explanatory call conventions | Make it one prohibitive sentence ("Never pass a composite document") |

### 3. Things never to touch

Leave the following unchanged (not even formatting):

- License headers, copyright notices
- Tool-interpreted directives: lint suppressions (`eslint-disable`, `noqa`, `#[allow]`), `type: ignore`, `pragma`, shebangs, encoding declarations, `@ts-expect-error`, etc.
- Anything docs generation or tests interpret: doctests, required structure of docstrings extracted as public API docs (keep the structure when project conventions fix the format)
- Comments/docstrings that become an externally visible API contract (rendered into OpenAPI schemas, etc.). Their readers cannot read the code, so they are out of shortening scope; prioritize coverage of observable behavior
- Commented-out code (deletion is out of scope for this skill. Report it only)
- Anything uncertain (keep comments you are not confident about deleting, and mention them in the report)
- Markdown heading structure, code examples, figures/tables, front matter, history-keeping sections (CHANGELOG, ADR, meeting notes, etc.)

### 4. Apply

- Apply per file with file edit tools. Preserve the original prose language.
- When shortening English, never drop relative pronouns (`that`, `which`, etc.) to save characters. Keep sentences readable.
- If a deletion leaves an unnatural blank line, collapse it. Do not touch other whitespace or formatting.
- After applying, run a lightweight syntax check when the project has a handy one (e.g. `ruff check`, `tsc --noEmit`, a build). When none exists, skipping is fine (note the skip to the user in Japanese, e.g. `手軽な構文チェック手段が無いため、スキップしました。`). Running tests is not required.

### 5. Report

Present the following to the user in Japanese (fill in the counts, paths, and observations):

```
対象ファイル数: <N>件 (削除: 約<N>件 / 短縮: 約<N>件 / 移動: 約<N>件)
- 移動・一本化: <from> から <to> へ
- ...

削った内容のうち、コード外に残す価値があるもの:
- <内容> → <チケット / 設計ドキュメントなどの置き場の提案>

迷って残したもの・範囲外の気づき:
- <ファイル>: <内容> (理由: <判断に迷った / コメントアウトされたコードなど>)
- ...

構文チェック: <実行したコマンドと結果 / スキップした旨>
```

The report must cover only the following points:

- File count and approximate counts of deleted/shortened/moved comments
- For moved/consolidated items, state "from where, to where"
- Among the cut content, anything worth keeping outside the code (tickets, design docs)
- Items kept while unsure, commented-out code, and other out-of-scope observations

Commit only when the user asked for it.
