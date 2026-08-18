---
name: fixup
description: 現在の未コミット変更を、既存の適切なコミットへ fixup するスキル。ユーザーが「fixupして」「fixupコミット作って」「既存のコミットに紛れ込ませて」「適切なコミットにfixup」などと依頼した場合に使用する。適用方式は `git commit --fixup=<sha>` (fixup コミットを積むだけ) と `git history fixup <sha>` (git 2.55 以降、その場で履歴を書き換え) から選ばせる。引数に `--autosquash` を渡された場合は方式 A で fixup コミットを積んだ後、続けて autosquash も実行する。変更の帰属先コミットは `git blame` / `git log -p` で機械的に特定し、必ずユーザーに提示して承認を得てから実行する。
---

# fixup

未コミットの変更 (staged / unstaged) を解析し、それぞれの変更がどの既存コミットに属すべきかを特定して fixup するスキル。

適用方式は 2 つあり、ユーザーに選ばせる (詳細は「5. 適用方式を選ぶ」)。

| 方式 | コマンド | 履歴の書き換え |
| --- | --- | --- |
| A: fixup コミット方式 | `git commit --fixup=<sha>` | しない (後で autosquash が必要) |
| B: 履歴書き換え方式 | `git history fixup <sha>` | その場で行う (autosquash 不要) |

方式 A では autosquash による履歴のまとめ直しは既定ではこのスキルの責務ではない。fixup コミットを積むところまでで終了し、ユーザーが続けて autosquash したい場合は [[autosquash]] スキルへ誘導する。ただし `--autosquash` 引数が渡された場合のみ、このスキルが続けて autosquash まで実行する (「引数」参照)。

## 引数

`--autosquash` (単独でも他の指示と併記でも可):

- 適用方式の質問 (手順 5) をスキップし、**方式 A を選択したものとして扱う**
- 手順 6 の計画提示では「fixup コミットを積んだ後、続けて autosquash も実行する」ことを明示して承認を得る
- 手順 7-A で fixup コミットを積んだ後、手順 8 の確認を経て [[autosquash]] スキルを実行する (手順 10)

引数がない場合は従来どおり手順 5 で方式を選ばせ、autosquash は実行しない。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること
- 現在ブランチが保護ブランチ (`main` / `master` / `develop` など) でないこと
- 方式 B を選ぶ場合は git 2.55 以降であること (`git --version` で確認する)

## 手順

### 1. 状態を確認する

以下を並列で実行し、現状を把握する:

- `git status --short` — 未コミット変更のファイル一覧
- `git rev-parse --abbrev-ref HEAD` — 現在のブランチ名
- `git diff --stat` — unstaged の差分サマリ
- `git diff --cached --stat` — staged の差分サマリ
- `git --version` — 方式 B (`git history fixup`) が使えるかの判定用

未コミット変更が何もない場合は「fixup 対象の変更がありません」と報告して終了する。

現在ブランチが `main` / `master` / `develop` などの保護ブランチである場合は中断してユーザーに確認する。

### 2. マージ先ブランチ (base) を確定する

fixup 対象にできるコミット範囲を確定するため base ブランチを決める。ローカルの情報だけで決まるので `gh` は必須にしない。

#### 2-1. リモート追跡refを最新化する

```bash
git fetch --prune origin
```

#### 2-2. デフォルトブランチを取得する

```bash
git rev-parse --abbrev-ref origin/HEAD
```

`origin/HEAD` が未設定で失敗する場合は `git remote set-head origin -a` を実行してから再取得する。

#### 2-3. merge-base が最も近いリモートブランチを求める

stacked ブランチ (base が `main` ではなく別の feature ブランチ) を拾うため、候補ごとに HEAD からの距離を測る。現在ブランチ自身の追跡ref は候補から除外する。

```bash
CUR=$(git rev-parse --abbrev-ref HEAD)
UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
for r in $(git for-each-ref --format='%(refname:short)' --exclude=refs/remotes/origin/HEAD refs/remotes/origin/); do
  [ "$r" = "origin/$CUR" ] && continue
  [ "$r" = "$UP" ] && continue
  mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
  [ "$mb" = "$(git rev-parse HEAD)" ] && continue
  echo "$(git rev-list --count "$mb"..HEAD) $r"
done | sort -n | head -5
```

先頭 (HEAD までの距離が最小) が base の最有力候補。

#### 2-4. 確定させる

- ユーザーが base を明示している場合はそれを採用し、2-2 / 2-3 は検証にだけ使う
- 2-2 と 2-3 の結果が一致すればそれを `<BASE>` として確定する
- 食い違う場合、または 2-3 で同距離の候補が複数並ぶ場合のみ判断材料を増やす:
  - `gh` が使えるなら `gh pr view --json baseRefName,headRefName,number,title,url` の `baseRefName` を優先する。PR の base は宣言された正解なので、ローカルのヒューリスティックより信頼できる
  - `gh` が使えない / PR が無い場合は `AskUserQuestion` で候補を提示して選ばせる
- どの経路で決めた場合も、確定した base と根拠 (デフォルトブランチ / merge-base 距離 / PR) を計画提示時に明記する

`git merge-base --fork-point` は reflog 依存で、clone し直した環境や別マシンでは空振りするため確定の根拠には使わない。

### 3. fixup 対象コミットの候補を取得する

```bash
git log --oneline origin/<BASE>..HEAD
```

これがブランチ上で fixup 可能なコミット群。既に `fixup!` / `squash!` プレフィックスが付いたコミットは fixup 対象から除外する (それらはさらに元のコミットに紐づいているため)。

候補コミットが 0 件の場合は「このブランチには fixup 可能なコミットがありません。通常の `git commit` を使ってください」と案内して終了する。

### 4. 変更ごとに帰属先コミットを特定する

**staged / unstaged の両方を対象にする。** ただし混在していると解析しにくいので、事前に状態を整理する:

- staged と unstaged が両方ある場合は、まず現状をユーザーに提示し、
  - (a) staged 分だけを fixup 化する
  - (b) 一旦 `git add -u` 相当で全てを staged にしてから fixup 化する
  - (c) いったん中断してユーザーが整理する
  のどれかを `AskUserQuestion` で確認する。**勝手に `git add` / `git reset` しない。**

対象範囲が決まったら、変更ごとに以下の方法で帰属先コミットを推定する:

#### 4-1. ファイル単位の粗い推定

各変更ファイルについて:

```bash
git log --oneline origin/<BASE>..HEAD -- <FILE>
```

このファイルを触っている候補コミットを列挙する。1件しか無ければ、そのコミットが第一候補。

#### 4-2. 行単位の精密な推定 (推奨)

変更行がどのコミットで導入されたかを `git blame` で辿る:

```bash
git diff [--cached] -U0 <FILE>
```

の各 hunk について、変更対象行 (削除行 / 変更前の周辺行) の由来を:

```bash
git blame -L <start>,<end> HEAD -- <FILE>
```

で確認する。blame 結果のコミット SHA が `origin/<BASE>..HEAD` の範囲内なら、それが fixup 先の最有力候補。範囲外 (base より前のコミット) なら、そのファイルを触っている最新のブランチ内コミットへ fixup する提案に切り替える。

**新規追加行のみの hunk** は blame で辿れないので、4-1 のファイル単位候補から選ぶ。

#### 4-3. 判断が割れる場合

1つのファイル内で複数のコミットへ fixup すべき変更が混在している場合は、hunk ごとに fixup 先を分ける。この場合、staged 状態を hunk 単位で組み替える必要があるので、A-2 の分割手順に従う。

### 5. 適用方式を選ぶ

**`--autosquash` 引数が渡されている場合はこの手順をスキップし、方式 A で進める。**

`AskUserQuestion` で以下から選ばせる。選択肢の提示前に、同じターンの Markdown で両方式の違い (履歴を書き換えるか、autosquash が必要か、force push が必要か) を説明しておく。**`options` 配列は必ず方式A、方式Bの順で渡す** (逆順や B を先頭にした提示はしない)。

- **方式 A: fixup コミットを積む (`git commit --fixup`)** — 履歴は書き換えず `fixup!` コミットを積むだけ。内容をレビューしてから [[autosquash]] でまとめられる。既存の履歴に手を入れないので巻き戻しやすい。
- **方式 B: その場で履歴を書き換える (`git history fixup`)** — 対象コミットへ直接取り込み、子孫コミットを replay する。autosquash 不要。ただし git 2.55 で導入された **EXPERIMENTAL** なコマンドで、マージコミットを含む履歴では使えず、コンフリクトすると abort する。

`git --version` が 2.55 未満の場合は方式 B を選択肢に出さず、方式 A で進める旨を伝える。

ユーザーが方式を明示している場合 (「git history fixup で」「fixup コミットだけ積んで」など) は質問せずそれに従う。

### 6. ユーザーに fixup 計画を提示して承認を得る

以下のような形式で、どの変更をどのコミットに fixup するかを一覧化する。方式によって末尾の注意書きを変える:

```
以下の内容で fixup します (方式: A / fixup コミットを積む):

[1] fixup → <sha1> feat: add user model
    - src/models/user.ts (全変更)
    - src/models/user.test.ts (全変更)

[2] fixup → <sha2> fix: handle empty payload
    - src/api/handler.ts の hunk @@ -42,7 +42,10 @@ のみ

base: origin/<BASE>
作成後、履歴を実際にまとめるには別途 autosquash が必要です。
実行してよろしいですか?
```

`--autosquash` 指定時は末尾を次に差し替える:

```
base: origin/<BASE>
fixup コミットを積んだ後、続けて autosquash で履歴をまとめます (SHA が変わり force push が必要になります)。
実行してよろしいですか?
```

方式 B の場合は末尾を次に差し替える:

```
方式: B / git history fixup (履歴をその場で書き換えます)
- 対象コミット以降の子孫コミットは SHA が変わります
- 書き換え前に backup ブランチを作成します
- 完了後は force push (--force-with-lease) が必要です
```

**必ず承認を得てから次に進む。** 承認前に `git commit` / `git add` / `git reset` / `git history` を実行しない。

### 7-A. 方式 A: fixup コミットを作成する

#### A-1. 単一コミットに全変更を fixup する場合

対象変更が既に staged なら、そのまま:

```bash
git commit --fixup=<TARGET_SHA>
```

unstaged 分も含める場合、staged 化してから実行する (ユーザー承認済みの範囲で):

```bash
git add <FILES...>
git commit --fixup=<TARGET_SHA>
```

`git add -A` / `git add .` は使わず、必要なファイルだけを明示的に指定する (無関係な untracked ファイルを巻き込まないため)。

#### A-2. 複数コミットに分けて fixup する場合

対象コミットごとに、以下を繰り返す:

1. 現在の index をいったんクリア: `git reset` (ワーキングツリーはそのまま)
2. コミット [n] に含める変更だけを staged 化する
   - ファイル全体なら: `git add <FILE>`
   - hunk 単位なら: `git add -p <FILE>` は対話式なので使わず、patch を経由する:
     ```bash
     git diff <FILE> > /tmp/hunk-N.patch  # 事前にエディタで該当 hunk だけ残す形はAIには不向き
     ```
     hunk 単位の分割は誤りやすいので、hunk 分割が必要な場合は **ユーザーに `git add -p` を手動で実行してもらい、その後にこのスキルへ戻ってくる** よう案内する。勝手に hunk を書き換えない。
3. `git commit --fixup=<TARGET_SHA_n>` を実行
4. 次のコミットへ

各ステップで `git status --short` を確認し、想定外のファイルが混入していないことを検証する。

### 7-B. 方式 B: `git history fixup` で履歴を書き換える

`git history fixup <commit>` は **index に staged された変更** を対象コミットへ直接取り込み、子孫コミットを replay する。コミットメッセージと author は保持される。

#### B-1. バックアップを取る

書き換え前に必ずバックアップブランチを作る。

```bash
git rev-parse HEAD
git branch backup/fixup-$(date +%Y%m%d-%H%M%S)
```

作成したブランチ名と元の HEAD SHA をユーザーに伝える。

#### B-2. 適用順序を決める

複数のコミットへ fixup する場合は **新しいコミットから順に (HEAD 側から base 側へ)** 処理する。子孫コミットは replay されて SHA が変わるが、祖先コミットの SHA は変わらないため、後続の対象 SHA が無効にならない。

#### B-3. 対象ごとに適用する

対象コミットごとに以下を繰り返す:

1. index をクリアする: `git reset` (ワーキングツリーはそのまま)
2. そのコミットに取り込む変更だけを staged 化する (方式 A の A-2 と同じ制約。`git add -A` / `git add .` は使わない。hunk 単位はユーザーに `git add -p` を委ねる)
3. `git status --short` で staged 内容を検証する
4. dry-run で結果を確認する:
   ```bash
   git history fixup --dry-run --empty=abort --update-refs=head <TARGET_SHA>
   ```
   `--dry-run` は ref を更新せず、更新予定の ref を出力するだけ。エラーになる場合はここで止めて原因をユーザーに報告する。
5. 本実行する:
   ```bash
   git history fixup --empty=abort --update-refs=head <TARGET_SHA>
   ```
6. 次の対象へ

#### B-4. オプションの扱い

- `--empty=abort` を既定で付ける。fixup によって対象コミットや子孫コミットが空になる場合に黙って消えるのを防ぐ。abort した場合は状況をユーザーに報告し、意図的に消したいなら `--empty=drop` (コマンドの既定値) を使うか確認する。
- `--update-refs=head` を既定で付ける。既定値の `branches` だと、対象コミットの子孫を指す **ローカルブランチすべて** (B-1 で作ったバックアップブランチを含む) が書き換わってしまう。バックアップは書き換え前の SHA を指し続ける必要があるため、`branches` は使わず常に `head` を指定する。他のローカルブランチも書き換えたい意図が明確にある場合のみ、ユーザーに確認した上で `--update-refs=branches` を使う。
- `--reedit-message` は使わない。メッセージを変えたい場合は `git history reword` を別途案内する。

#### B-5. 失敗時の対応

`git history fixup` はコンフリクトすると abort し、履歴は変更されない。この場合:

- 帰属先コミットの推定が間違っている可能性を検討し、候補を見直してユーザーに再提示する
- どうしても取り込めない場合は方式 A (`git commit --fixup`) に切り替えるか、通常のコミットにする選択肢を提示する
- **勝手に別のコミットへ fixup し直さない。** 必ずユーザーの承認を得る

履歴が壊れたと判断した場合は自分で復旧を試みず、B-1 のバックアップブランチ名と元の HEAD SHA を提示して復旧方法 (`git reset --hard <元のSHA>`) を案内する。

### 8. 結果を確認する

```bash
git log --oneline origin/<BASE>..HEAD
git status --short
```

方式 A の場合:

- 期待した数の `fixup!` コミットが積まれていること
- ワーキングツリーがクリーン (残余の未コミット変更がない) であること (残す場合は事前にユーザー合意済みのはず)

方式 B の場合:

- `fixup!` コミットが積まれていないこと (履歴に取り込まれているはず)
- コミット数がバックアップ時点と一致すること (`--empty=abort` を付けているので減っていないはず)
- 意図した変更が対象コミットに入っていること: `git show --stat <新しいSHA>`
- バックアップブランチとワーキングツリーの内容が一致すること:
  ```bash
  git diff <BACKUP_BRANCH> HEAD
  ```
  fixup した変更分だけが差分として出るのが期待値。それ以外の差分があればユーザーに報告する (**勝手に修正しない**)。

### 9. 完了報告

方式 A の場合:

- 作成した fixup コミットの一覧 (`<sha> fixup! <元コミットのタイトル>`)
- 履歴を実際にまとめるには `autosquash` スキルを使う旨 (`--autosquash` 指定時は手順 10 へ進むので不要)
- force push はユーザー自身で行う必要がある旨 (このスキルでは行わない)

方式 B の場合:

- 書き換え後の `git log --oneline origin/<BASE>..HEAD`
- バックアップブランチ名と元の HEAD SHA (復旧用)
- SHA が変わったので push には `git push --force-with-lease` が必要な旨。**push はユーザーの責務であり、このスキルでは行わない**
- 問題なければバックアップブランチはユーザー自身で削除してよい旨

### 10. `--autosquash` 指定時: 続けて autosquash する

`--autosquash` が渡されていた場合のみ実行する。手順 8 の確認が通り、ワーキングツリーに想定外の残余がないことを確かめたうえで、[[autosquash]] スキルを起動して履歴をまとめる。手順 2 で確定した base を autosquash 側へ引き継ぎ、base の再確定をやり直させない。

autosquash が途中で失敗した場合 (コンフリクト等) は、autosquash スキル側の失敗時手順に従う。**fixup コミット自体は既に作成済みなので、勝手に取り消さない。**

完了後は autosquash 後の `git log --oneline origin/<BASE>..HEAD` と、force push が必要な旨を報告する。**push はこのスキルでは行わない。**

## 注意事項

- **保護ブランチ上では実行しない。** 現在ブランチが `main` / `master` / `develop` などの場合は中断する。
- **base より前のコミットには fixup しない。** origin/<BASE>..HEAD の範囲外は他人の履歴なので触らない。範囲外にしか帰属先が無い変更は、通常のコミットにするようユーザーに提案する。
- **既存の `fixup!` / `squash!` コミットには fixup しない。** それらはさらに元のコミットへ紐づいているため、二重 fixup は混乱の元。
- **hunk 単位の複雑な分割は AI 側で自動化しない。** 誤って別の hunk を巻き込むリスクが高いので、ユーザーに `git add -p` を委ねる。
- **`git add -A` / `git add .` は使わない。** 常にファイルを明示指定する (`.env` などの誤コミット防止)。
- **force push はしない。** autosquash 後 / 履歴書き換え後の push はユーザーの責務。
- **方式 B は履歴を破壊的に書き換える。** 実行前に必ずバックアップブランチを作り、`--dry-run` で確認する。マージコミットを含む履歴では使えないので、`git log --merges origin/<BASE>..HEAD` にヒットする場合は方式 A に切り替える。
- **方式 B では `--update-refs=head` を既定で使う。** 既定値の `--update-refs=branches` だと、B-1 で作成したバックアップブランチが対象コミットと同じ SHA を指しているため、バックアップごと書き換わってしまい復旧不能になる。バックアップを保護するため常に `--update-refs=head` を指定する。
- 帰属先が本当にわからない変更は「新規コミットにする」選択肢を必ず残す。無理に既存コミットへ紛れ込ませない。
