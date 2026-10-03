---
name: pr-brief
description: >-
  Skill for organizing background knowledge about a target PR.
  Collects the PR body, linked Jira tickets (including parent epics and related
  tickets), and design documents in the repository in parallel, then reports the
  PR's positioning, feature big picture, glossary, and known intentional debt in Japanese.
  Use when asked things like "explain the background of PR #NNN", "organize the
  prerequisite knowledge for this PR", "get the big picture of the PR",
  "pr brief".
  Does not evaluate the diff itself (that belongs to code-review skills).
---

# PR Background Brief

Collect background knowledge about the target PR and organize everything needed
before starting to read the diff into a single document.

## Subagents

{{ includeTemplate "agents/skills/_shared/subagents.md" . }}

## Asking the user to choose

{{ includeTemplate "agents/skills/_shared/user-choice.md" . }}

## Confirming Input

1. Identify the PR number (and repository if needed). When only a number is
   given, resolve it with `gh` in the current directory (`cd` into the relevant
   sub-repository for meta-repos).
2. If ambiguous, list candidates with `gh pr list --search` and present the
   following to the user in Japanese and take the choice with a selection
   prompt:

   ```
   対象のPRが複数見つかりました。どれを対象にしますか?
   - <候補1: 番号 / タイトル>
   - <候補2: 番号 / タイトル>
   ```

## Step 1: Fetch PR Information (run yourself)

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,url,commits
```

Format with `jq` and extract the following from the body:

- Linked Jira ticket keys (`browse/XXX-NNN` style URLs). Note every related
  ticket mentioned in the body, not just the main one
- Merge target branch (straight to develop vs. an integration branch)
- Whether production is affected, and the release type
- Paths of design documents referenced by the PR body (`docs/`, `specs/`, etc.)
- Technical terms and abbreviations in the PR body (internal notations such as
  QD-x or slice numbers S0-S7)

## Step 2: Parallel Research (delegate to subagents)

**Launch two subagents in parallel.**

### Research A: Jira Research (research role)

Include in the prompt:

- State that Jira access uses the Atlassian MCP tools (ticket fetch / JQL
  search, plus fetching accessible resources if needed). Note that tool names
  differ per agent, and agents with lazy loading must load the tool definitions
  first
- Main ticket: fetch the body and all comments
- Parent epic and related tickets: fetch the body or summary (note that 1-2
  lines of positioning are enough for related tickets)
- Instruct them to extract definitions of technical terms and abbreviations in
  the tickets
- State explicitly: "if it cannot be fetched, search with JQL. Never fabricate
  by guessing"

### Research B: Repository Design-Document Research (read-only exploration role)

Include in the prompt:

- The absolute path of the target repository and the PR's head/base branch names
- **Because the worktree HEAD may be stale, read files on the PR branch with
  `git show origin/<branch>:<path>`** (run `git fetch origin <branch>` first if
  a fetch is needed)
- Research targets:
  - The service/module big picture (README, `docs/architecture/`, etc.) plus
    layer structure and dependency rules
  - Design documents and specs referenced by the PR body
  - Existing type definitions and established patterns the PR's new types and
    functions depend on (existing code described in the PR body as "same shape
    as ~")
  - The mechanism the PR's changes plug into, such as error handling or routing
- Instruct: "no need to paste full file contents. Explain at a granularity
  that conveys concepts and contracts, with `path:line` references"

## Step 3: Write the Background Brief

Cross-check both subagents' results against the PR body and present the
following to the user in Japanese:

```
1. **PRの位置づけ**: このPRが追加する内容、規模、作成者、本番影響、
   マージ先、配線状況(組み込み済みか未配線か)など、このPRの重みを決める前提
2. **機能全体像**: 親チケットのゴールと、その中でこのPRが担うスライス/フェーズ
3. **PRの構成要素**: ファイルと役割の対応、主要な設計判断、契約変更
4. **用語集**: PR本文・チケット・コードに登場する技術用語や内部略語。
   出典が見つからない略語は、見つからなかったことを明記する
5. **既知の意図的な負債**: PR本文やコードで自己申告された制限と、
   分割されたフォローアップチケット
```

## Notes

- This skill does not evaluate the diff itself. After presenting the brief,
  present the following to the user in Japanese as a one-line next step
  (read the diff, review, etc.):

  ```
  次に差分を読みますか? レビューに進めますか?
  ```
- Do not take subagent reports at face value; cross-check anything clearly
  contradictory against the source data (PR body, tickets)
