---
name: deep-review
description: 複数の観点別レビュワーsubagentを並列実行し、judge subagentが各指摘を実コードで検証してから、妥当な指摘を修正して再レビューするループ型の深掘りコードレビュー。security/quality/naming/perf/a11y/test/arch/meta/spec の9視点を独立コンテキストでレビューし、PR本文からJira/Confluence等の仕様ドキュメントも取得して仕様整合性まで見る。ユーザーが「deep review」「PRをレビュー」「差分を多角的にレビュー」「レビューして修正して」などと依頼した場合、またはPR番号・差分範囲を指定してレビューを求めた場合に使用する。指摘をPRのpendingレビューコメントとして投稿することもできる。
---

# Deep Review

複数のレビュワーsubagentに異なる視点からコードレビューを並列実行させ、judge subagentが妥当性を評価し、妥当な指摘を修正してから再レビューするループを最大5回繰り返す。

## Target

$ARGUMENTS

## 設計の前提

- レビュワーは `Agent` ツールを単一メッセージ内で並列呼び出しすることで同時起動する
- 各subagentは最終応答テキストを返却する。オーケストレーター（自分）はその文字列を直接パースする
- レビュワーはコードを読むだけなので `subagent_type: Explore` を使う（読み取り専用・高速）
- judgeは対象ファイルを読んで妥当性判定するため `Explore` を使う
- 修正は必ずオーケストレーター自身が行う（subagentに書き換えさせない）
- 並列実行の上限は1メッセージ内のAgentツール呼び出し数で制御する

## Reviewers (9視点)

| ラベル | 視点 | チェック項目 |
|---|---|---|
| security | セキュリティ | インジェクション, 認証・認可, 機密情報露出, 入力バリデーション, XSS/CSRF, 安全でない暗号化 |
| quality | コード品質 | 可読性, 関数の責務分離, エラーハンドリング, DRY, 不変性, ネストの深さ, マジックナンバー |
| naming | 命名 | 名前から内容・役割が推測できるか, 誤解を招く名前, 既存の他機能・役割との名前被り・紛らわしさ, 同一概念の表記ゆれ, スコープに対する情報量の過不足。※casing規約 (camelCase/snake_case等) の違反はチェック対象外 |
| perf | パフォーマンス | N+1, 不要な再レンダリング, メモリリーク, 計算量, キャッシュ漏れ, バンドルサイズ, 不要なループ |
| a11y | アクセシビリティ | WCAG 2.2, aria属性, キーボード操作, スクリーンリーダー, コントラスト, フォーカス管理 |
| test | テスト品質 | カバレッジの漏れ, 境界値, 実装依存の脆さ, モック過多, AAAパターン, テスト名の明瞭さ |
| arch | アーキテクチャ | レイヤー違反, 依存方向, 循環依存, 責務肥大, インターフェース設計, モジュール凝集度 |
| meta | アプローチ妥当性 | YAGNI違反, より単純な代替, スコープ, 段階的アプローチ, 既存資産, 技術選択 |
| spec | 仕様整合性 | PR本文にリンクされたJira/Confluence/PRD/設計資料等との整合性, 実装が仕様要件を満たすか, 仕様で言及されたエッジケース/受け入れ条件の網羅, 仕様自体の妥当性（矛盾・抜け漏れ・前提誤り） |

## Phase 0: Preparation

1. **レビュー対象を特定する** — `$ARGUMENTS`の内容に応じて:
   - PR番号/URL指定: `gh pr diff <number>` でdiffを取得。`gh pr view <number> --json body,title` でPR説明文も取得
   - ファイルパス指定: そのファイルを読む
   - 未指定: `git diff HEAD` でステージ済み+未ステージの変更。差分がなければ `git diff HEAD~1`
   - 取得したdiffを `$DIFF`、変更ファイル一覧を `$FILES`、変更の意図を `$PURPOSE` として保持

2. **リンクされた仕様ドキュメントの取得** — PR本文（`$PURPOSE`/PR description）から以下のリンクを抽出し、本文を取得して `$SPEC_DOCS` として保持する:
   - Jira issue (`*.atlassian.net/browse/XXX-###`, `ABC-123` 形式のキー): `mcp__claude_ai_Atlassian__getJiraIssue` で本文+コメントを取得
   - Confluenceページ (`*.atlassian.net/wiki/...`): `mcp__claude_ai_Atlassian__getConfluencePage` で本文を取得
   - Google Docs/Drive (`docs.google.com`, `drive.google.com`): `mcp__claude_ai_Google_Drive__read_file_content` で取得（権限があれば）
   - Notion (`notion.so/...`): Notion MCPで取得
   - その他PRD/設計資料/Figma/Slack/Lucid等のリンク: 可能な範囲で対応するMCPツールで取得。取得不能なら「リンクのみ確認、本文未取得」として記録
   - 取得した各ドキュメントは `title`, `url`, `body`（重要部分の抜粋でも可）の形でまとめる
   - 仕様ドキュメントが**1つも見つからない**場合は `$SPEC_DOCS = "(no linked spec documents)"` とし、後述のspecレビュワーには「仕様リンクなし。実装の意図が自明か、PR本文の説明だけで十分かを評価せよ」と指示する

3. **diffサイズの判断** — `$DIFF`が500行を超える場合は、各subagentにはdiff全文ではなく要約+`$FILES`を渡し、「対象ファイルを直接読んでレビューしてください」と指示する

4. **ループカウンタ初期化** — `ROUND=1`, `MAX_ROUNDS=5`

## Phase 1: Parallel Detail Review (8視点)

security/quality/naming/perf/a11y/test/arch/spec の8つのAgent呼び出しを **単一メッセージで並列発行** する。

各Agentの呼び出しテンプレート:

```
Agent(
  description: "<視点名> review round $ROUND",
  subagent_type: "Explore",
  prompt: """
あなたは<視点名>専門のコードレビュワーです。以下の変更を<視点名>の観点のみからレビューしてください。
他視点（例: <視点名>以外のセキュリティ・品質・パフォーマンス等）の指摘は出さないでください。

チェック項目: <上のReviewers表のチェック項目>

指摘がある場合、以下の形式で1件ごとに区切って返してください:
---
FINDING: <指摘タイトル>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
FILE: <ファイルパス>
LINE: <行番号(わかれば)>
DESCRIPTION: <問題の説明>
SUGGESTION: <具体的な修正案>
---

指摘がない場合は単独行で「LGTM」とだけ返してください。

変更の意図: $PURPOSE
変更ファイル: $FILES

対象diff (500行超なら要約のみ。必要に応じて自分でファイルを読むこと):
$DIFF
"""
)
```

並列呼び出しの注意:
- 8件すべてを **同一のアシスタント応答内** で `Agent` ツールとして並べる。順次発行は避ける（直列化されて遅くなる）
- 各subagentは独立コンテキストなので、共有の前提知識は明示的にpromptに含める
- `naming` のpromptには追加で次の2点を含める: 「既存の他機能・役割との名前被りや紛らわしさは、GrepやGlobでコードベース内の類似名を実際に検索して確認すること」「camelCase/snake_case等のcasing規約違反は指摘しないこと」

### spec レビュワー専用プロンプト

`spec` は他6人と同じテンプレートではなく、以下の専用プロンプトを使う:

```
Agent(
  description: "spec review round $ROUND",
  subagent_type: "Explore",
  prompt: """
あなたは仕様整合性レビュワーです。PR本文にリンクされた仕様ドキュメント（Jira/Confluence/PRD/設計資料等）と実装の整合性を評価し、さらに仕様自体の妥当性も評価してください。

評価軸:
A. 仕様↔実装の整合性
   1. 仕様で求められている機能・要件をすべて実装しているか（抜けはないか）
   2. 仕様にない機能を勝手に追加していないか（スコープ逸脱）
   3. 仕様で定義された受け入れ条件 (Acceptance Criteria)・エッジケース・エラー仕様を満たすか
   4. データモデル・APIシグネチャ・画面要素・命名等が仕様と一致するか
   5. 仕様で定義された非機能要件（性能・セキュリティ・互換性等）に反していないか

B. 仕様自体の妥当性（仕様が間違っている可能性も指摘してよい）
   1. 仕様内に矛盾・曖昧さ・抜け漏れがないか
   2. 仕様の前提が現状のシステム/コードベース/運用と矛盾していないか
   3. ユーザー体験・業務フロー上の論理的破綻はないか
   4. セキュリティ・プライバシー・コンプライアンス観点で仕様自体に問題はないか
   5. 仕様で選択された方針が、より良い代替案と比べて劣っていないか

指摘がある場合、以下の形式で1件ごとに区切って返してください:
---
FINDING: <指摘タイトル>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
CATEGORY: SPEC_MISMATCH|SPEC_MISSING_IMPL|SPEC_SCOPE_CREEP|SPEC_FLAW|SPEC_AMBIGUOUS|SPEC_OUTDATED
SPEC_REF: <該当する仕様ドキュメントのtitle/URL/該当箇所>
FILE: <ファイルパス(仕様自体への指摘なら空可)>
LINE: <行番号(あれば)>
DESCRIPTION: <問題の説明。仕様と実装どちらの問題かを明示>
SUGGESTION: <修正案。仕様側を直すべきか実装側を直すべきかを明示>
---

仕様ドキュメントが取得できなかった場合は、PR本文の説明だけで実装意図が自明か評価し、不明瞭ならその旨をMEDIUMで指摘してください。
問題がなければ単独行で「LGTM 仕様と実装は整合しています」と返してください。

変更の意図 (PR本文より): $PURPOSE
変更ファイル: $FILES

リンクされた仕様ドキュメント:
$SPEC_DOCS

対象diff:
$DIFF
"""
)
```

## Phase 1b: Meta Review (アプローチ妥当性)

`meta` は他8人と並列で良いが、promptが異なる。Phase 1と同じメッセージ内に9つ目のAgent呼び出しとして含めてよい。

```
Agent(
  description: "meta review round $ROUND",
  subagent_type: "Explore",
  prompt: """
あなたはアプローチそのものを評価するメタレビュワーです。コードの細部ではなく「このアプローチが適切か」を問います。

変更の意図・目的: $PURPOSE

以下6観点で評価してください:
1. 過剰設計 (YAGNI違反) — 現時点で不要な抽象化・将来のためだけの設計
2. より単純な代替手段 — ライブラリ活用・既存機能流用・パターン簡略化で同目的を達成できるか
3. スコープの妥当性 — 別PR/タスクに分割すべき変更が混在していないか
4. 段階的アプローチ — 一度に全実装するのではなく分割リリースできる点はないか
5. 既存資産の見落とし — プロジェクト内に同等機能が既存していないか（grepで探すこと）
6. 技術選択の妥当性 — 規模・用途に対してライブラリ/フレームワーク/パターンが適切か

指摘がある場合、以下の形式で返してください:
---
FINDING: <指摘タイトル>
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
CATEGORY: YAGNI|SIMPLER_ALTERNATIVE|SCOPE_CREEP|INCREMENTAL|REINVENTION|TECH_CHOICE
DESCRIPTION: <問題の説明>
SUGGESTION: <代替アプローチの提案>
---

問題がなければ「LGTM アプローチは妥当です」とだけ返してください。

変更ファイル: $FILES
対象diff:
$DIFF
"""
)
```

## Phase 2: Collect & Aggregate

**重要**: 9つのAgent呼び出しの **全て** が完了するまで次のPhaseに進んではならない。1つでも未完了のレビュワーがある状態でPhase 3以降に進むことを禁止する。Phase 1とPhase 1bは同一メッセージ内で9並列発行し、全Agentツール結果が揃うまでオーケストレーターは判断を保留する。

全9件のAgent結果が揃ったら:

1. 各レビュワーの返答をパースし、`FINDING`ブロックを抽出
2. 全員が「LGTM」ならその旨をユーザーに報告して終了
3. それ以外はfindingsを集約。各findingに `reviewer: <ラベル>` を付与してリスト化

## Phase 3: Judge Findings (複数Agent並列)

judgeは **必ず複数Agentに分割して並列実行** する。単一Agentに全件を渡すと、指摘1件あたりにコードを読む深さが浅くなり、誤判定（false positiveの見逃し / 真の問題のINVALID化）が増えるため。

### 分割戦略

集約後のfindings総数 `N` に応じて分割方針を選ぶ。両方式とも **同一メッセージ内で全judgeを並列発行** する。

1. **観点別分割 (デフォルト, N ≤ 24)** — レビュワーラベルごとにjudgeを分ける:
   - `judge-security`, `judge-quality`, `judge-naming`, `judge-perf`, `judge-a11y`, `judge-test`, `judge-arch`, `judge-spec`, `judge-meta` の最大9並列
   - そのラベルでfindingsが0件のjudgeは起動しない
   - 各judgeは自分の観点の指摘だけを精査するため、コードのどこを読めばよいか集中しやすい

2. **指摘数分割 (N > 24, または1観点に10件以上集中)** — findingsをチャンク化:
   - 1チャンク 5〜8件を目安に分割（同一ファイルへの指摘は同じチャンクに寄せる）
   - チャンク数は最大8並列まで。N > 64 の場合は8並列で割り当て、各judgeが ceil(N/8) 件を担当
   - チャンク化する場合でも `spec` と `meta` は他観点と混ぜず独立chunkにする（評価軸が違うため）

3. **クロスチェック (オプション, 高重要度PR時)** — 上記に加えて全findingsを1人のmeta-judgeに渡し、観点別judgeの判定結果と突き合わせる。観点別judgeとmeta-judgeで判定が割れたものだけユーザー提示時に「judge間で意見が割れた指摘」として別枠で表示する

オーケストレーターは Phase 2 でfindings集約直後に N を計算し、上記から分割方式を決定して **どの方式を採用したかをログ出力** する。

### 各judgeのプロンプトテンプレート

```
Agent(
  description: "judge <観点 or chunk#> round $ROUND",
  subagent_type: "Explore",
  prompt: """
あなたはコードレビュー指摘を精査するjudgeです。担当する指摘群について、必ず以下の手順を踏んで判定してください。

【必須手順 — 省略禁止】
1. 各指摘について、`FILE` と `LINE` で示された箇所を **必ず Read ツールで実ファイルを開いて確認** する。指摘文だけ読んで判定してはならない
2. 周辺コード（前後30行程度、必要なら呼び出し元・型定義・関連モジュール）も読む。指摘の前提が現コードベースで成立しているかを確認する
3. specの指摘の場合は、加えて提供された仕様ドキュメント本文の該当箇所も読み返し、本当に乖離があるかを検証する
4. metaの指摘の場合は、grepで「同等機能の既存実装」「過去の類似アプローチ」を確認した上で判定する
5. コードを読まずに、または読んでも該当箇所が見つからずに判定した場合は、VERDICT行の直後に `EVIDENCE: UNVERIFIED` と必ず付記する

【判定基準】
- VALID: 実コードを読んで、指摘内容が実際に成立すると確認できたもの
- INVALID: 実コードを読んだ結果、誤検知・前提誤り・既に対処済み等で成立しないと判断したもの
- DUPLICATE: 他の指摘と実質同一（統合先のORIGINAL_FINDINGをDUPLICATE_OF行で示す）

【出力形式】各指摘について:
---
VERDICT: VALID|INVALID|DUPLICATE
ORIGINAL_FINDING: <元の指摘タイトル>
REVIEWER: <security|quality|naming|perf|a11y|test|arch|spec|meta>
FIX_TARGET: <CODE|SPEC|EITHER|N/A>  # specの指摘のみ
SEVERITY: CRITICAL|HIGH|MEDIUM|LOW
FILE: <ファイルパス>
LINE: <行番号>
EVIDENCE: VERIFIED|UNVERIFIED  # 実コード/仕様文を読んで判定したかを必ず明示
EVIDENCE_NOTES: <読んだファイル・行範囲・引用した実コードの要点を1〜3行で>
REASON: <判定理由。実コードのどの構造から VALID/INVALID と言えるかを具体的に>
SUGGESTION: <VALIDの場合の修正案>
DUPLICATE_OF: <DUPLICATEのときのみ統合先のORIGINAL_FINDING>
---

担当指摘がすべてINVALIDなら単独行で「ALL_CLEAR」と返してください。

担当指摘:
<該当チャンクのfindingsをここに貼る>

参考情報:
- 変更ファイル一覧: $FILES
- 変更の意図: $PURPOSE
- リンクされた仕様ドキュメント (spec担当のみ): $SPEC_DOCS
"""
)
```

### 結果の集約

- 全judge Agentの結果が揃うまで Phase 3b に進まない
- 各judgeの出力をパースして1つのリストに統合する
- `EVIDENCE: UNVERIFIED` の指摘は **デフォルトでユーザー提示時に「未検証」マークを付ける**。CRITICAL/HIGH の場合は再判定のため該当指摘だけを別Agentに再投入して再判定する（最大1回）
- DUPLICATE判定は `DUPLICATE_OF` を辿って統合先にマージ
- クロスチェック方式採用時は、observation別judgeとmeta-judgeの判定差分を抽出し「意見が割れた指摘」リストを別途生成

## Phase 3b: User Confirmation (修正に進むかどうかの確認)

**修正に入る前に必ずユーザーへ確認する**。judgeの結果に関わらず、`ALL_CLEAR` でない限りこのフェーズは省略しない。

### 🚨 絶対厳守ルール（Phase 3b全体）

**レビュー結果をユーザーに提示する前に `AskUserQuestion` を呼び出すことを固く禁止する。** 過去に2回、同種の不具合が発生した:

- 不具合1: レビュー結果を出さずにいきなり対応方針をAskUserQuestionで訊いた
- 不具合2: 一覧テキストを出力した後、同一ターン内でダミーのツール呼び出し（`Bash true` 等）を挟んでから `AskUserQuestion` を呼んだ。ツール呼び出し間のテキストはユーザーに表示されないことがあるため、結果的に「一覧を見せずにAskUserQuestionした」のと同じ状態になった

以下の順序を必ず守ること:

1. まずPhase 3b-1として、VALIDな指摘の全件一覧を **通常のアシスタントテキスト（Markdown）で出力し、そのテキストをターンの最終出力にしてターンを終了する**。一覧テキストの後に **いかなるツール呼び出しも行ってはならない**（`AskUserQuestion` はもちろん、`Bash` 等のダミー呼び出しでメッセージを分割する回避策も禁止）
2. ユーザーが一覧に反応した **次のターン以降** に、Phase 3b-2の `AskUserQuestion` を呼び出す。ユーザーの応答が既に対応方針を明示している場合（例:「全部修正して」）は `AskUserQuestion` を省略してその指示に従ってよい

**同一ターン内で「一覧提示 + AskUserQuestion」を行うのは、間に何を挟んでも禁止**。ターンを完全に終了してユーザーに読む機会を渡すことでのみ、一覧提示が完了したとみなせる。

### Phase 3b-1: VALIDな指摘の一覧提示（無条件・必須・ターン終了）

**`AskUserQuestion` を呼び出す前に、必ずこのステップを実行し、一覧テキストでターンを終了する**。VALIDな指摘が0件であっても「VALIDな指摘は0件です」と明示的にユーザーへ提示する。このステップを省略して直接 `AskUserQuestion` に進むことは禁止する。

以下を通常テキスト（Markdown）で出力する:

1. judgeがVALIDと判定した指摘の **全件一覧**（reviewer / severity / file:line / title / description / suggestion をテーブル or 箇条書きで、1件も省略せずに列挙）
   - `EVIDENCE: UNVERIFIED` のものは「未検証」マークを付けて明示
   - severity順（CRITICAL → HIGH → MEDIUM → LOW）で並べる
2. INVALID/DUPLICATEとして除外された件数（参考情報として合計のみ）
3. metaの指摘があれば、それを別セクションで明示（CATEGORYと提案を含める）
4. specの指摘があれば、それも別セクションで明示（CATEGORY / SPEC_REF / FIX_TARGET を含める）。特に `FIX_TARGET=SPEC` のものは「仕様側の修正が必要」として目立たせる

一覧提示テキストの末尾では、対応方針の確認に進む旨を1行だけ添え（例: 「上記VALID指摘について対応方針を確認します。続行の合図をください」）、そこで **ターンを終了する**。

### Phase 3b-2: 対応方針の確認

Phase 3b-1の一覧に対する **ユーザーの応答を受けた後のターン** で、以下の選択肢をユーザーに提示（ユーザーの応答が方針を既に明示していればこのAskUserQuestionは省略してよい）:

```
このラウンドで判定されたVALIDな指摘について、対応方針を選んでください:

A. 全てのVALID指摘を自動修正する（CRITICAL/HIGHは必須、MEDIUMも可能なら修正、LOWは報告のみ）
B. 指摘を選んで修正する（修正対象の番号を指定）
E. VALIDな指摘をPRのレビューコメントとして投稿する（Phase 4b へ。pending状態のインラインコメント。レビュー対象がPRの場合のみ提示する）

metaの指摘がVALIDで残っている場合は追加で:
  M1. アプローチ変更を受け入れて修正に含める
  M2. アプローチは現状維持（metaの指摘はスキップ）
  M3. アプローチ再検討のため中断（終了）

specの指摘がVALIDで残っている場合は追加で:
  S1. 実装を仕様に合わせる（コード修正）
  S2. 仕様を実装に合わせる（仕様ドキュメント側の更新が必要 — オーケストレーターは仕様の更新は行わず、「要仕様改訂」としてユーザーに伝える。ただしJira/Confluence編集権限があるなら別途ユーザーに確認の上で更新提案を行う）
  S3. specの指摘はスキップ（実装も仕様も現状維持）
  S4. 仕様自体の再検討が必要なため中断（終了）
```

`AskUserQuestion` ツールを用いて選択を受け付ける。複数質問が必要な場合（修正方針 + meta方針）は同一の `AskUserQuestion` 呼び出しに複数questionを含めて1度で訊く。

ユーザー選択結果に応じて:
- A / B / M1 / S1: Phase 4 (Fix) へ
- E: Phase 4b (Post Pending PR Review) へ。投稿後は結果を報告して終了（修正は行わない。投稿と修正を両方行いたい場合はユーザーがその旨を明示したときのみ、投稿→修正の順で実行する）
- M3 / S4: 中断理由を報告して終了
- M2 / S3: 該当する指摘のみスキップして、他の指摘の修正方針（A/B/E）に従う
- S2: 実装側は触らず、「仕様改訂が必要な指摘」としてユーザーへの最終報告に含める（仕様ドキュメント自動更新は行わない）

## Phase 4: Fix Valid Findings

Phase 3bでユーザーが修正を選んだ指摘のみ対象。

1. 修正粒度はユーザー選択に従う:
   - 選択A（全自動）: CRITICAL/HIGH必須、MEDIUM可能なら修正、LOW報告のみ
   - 選択B（個別選択）: ユーザーが指定した指摘番号のみ修正
   - M1選択時はmetaの指摘も含める
2. 修正はオーケストレーター（自分）が `Edit`/`Write` で直接行う。subagentに書き換えさせない
3. 修正完了後、`ROUND++`
4. `ROUND > MAX_ROUNDS` なら最大ラウンド到達として修正内容のサマリーを報告して終了
5. それ以外なら `git diff HEAD` で `$DIFF` を更新し、Phase 1 へ戻る（次ラウンドのレビュー前にもPhase 3bでユーザー確認する）

**次ラウンドへ進むかどうかも確認する**: 修正完了後、再レビューを行うか終了するかをユーザーに `AskUserQuestion` で確認する:

```
ラウンド$ROUNDの修正が完了しました。次の対応を選んでください:
1. 再レビューする（次ラウンドへ）
2. 終了する
```

## Phase 4b: Post Pending PR Review

Phase 3bでユーザーが選択Eを選んだ場合のみ実行する。投稿手順は `pending-review-comments` スキルに委譲する（`Skill` ツールで呼び出す）。手順・pending維持のルール・エラー処理はそちらが持つ。

deep-review側の前提として、スキルに渡す入力を次のとおり整える:

- **対象はVALIDと判定された指摘のみ**。INVALID/UNCERTAINは渡さない
- 各指摘は `FILE` / `LINE` / タイトル / `DESCRIPTION` / `SUGGESTION` / `<reviewer>` / `<SEVERITY>` を揃えて渡す。コメント先頭のラベルは `[<reviewer> / <SEVERITY>]`（例: `[quality / LOW]`）
- レビュー対象がPRでない場合（ローカルdiffやファイル指定）はそもそも選択Eを提示しない

投稿後は結果を報告して終了する。修正は行わない（投稿と修正を両方行う場合はユーザーが明示したときのみ、投稿→修正の順）。

## Error Handling

- **subagent応答のパース失敗**: 該当レビュワーをそのラウンドだけスキップして続行。同じレビュワーが2ラウンド連続でパース不能なら以後そのラウンド以降は除外
- **a11y該当なし**: UI変更がない場合 a11y は LGTM を返す想定
- **test該当なし**: テストファイル変更がない場合 test は「テスト追加推奨」程度の指摘に留まる想定
- **judgeのタイムアウト/失敗**: 全findingsをVALIDとみなして修正に進む（保守的に倒す）
- **subagentが指定フォーマットを守らない**: 返答内の `FINDING:` 行を緩くマッチして抽出。完全に取れなければそのレビュワーの結果は破棄
- **仕様ドキュメントの取得失敗**: 権限不足/URL不正/MCP未接続でドキュメント取得に失敗した場合は、specレビュワーへのpromptに「リンク先取得失敗、URLのみ提供」と明記して続行。specの指摘はMEDIUM以下に格下げして扱う
- **PR本文にリンクが一切ない**: specレビュワーは「仕様リンクなし。PR本文の説明だけで意図が伝わるかを評価」モードで動作。実装意図が不明瞭ならMEDIUMで指摘する
