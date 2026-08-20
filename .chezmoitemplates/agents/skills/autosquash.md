---
name: autosquash
description: 現在のブランチの fixup! / squash! コミットを `git rebase -i --autosquash` でまとめるスキル。ユーザーが「autosquashして」「fixupコミットをまとめて」「rebase --autosquashして」などと依頼した場合に使用する。マージ先ブランチは `origin/HEAD` と merge-base の距離からローカルで特定し、判断が割れる場合のみ PR 情報やユーザーへの確認で確定させる。
---

# autosquash

現在のブランチに積まれている `fixup!` / `squash!` コミットを、対応する元コミットへ `git rebase -i --autosquash` でまとめるスキル。

## ユーザーへの選択提示

このドキュメントで「選択提示」と書いてある箇所は、選択肢を提示してユーザーに選ばせることを指す。選択UIツール (`AskUserQuestion` など) が使える agent ではそれを使い、無い agent では同じ選択肢を番号付きリストのプレーンテキストで提示し、番号または自由記述で答えてもらう。どちらの場合も回答を得るまで次の手順へ進まない。

## 前提

- 作業ディレクトリが Git リポジトリ配下であること。
- `origin` リモートが設定されていること (base をローカルで特定するため)。

## 手順

### 1. 状態を確認する

以下を並列で実行し、現状を把握する:

- `git status --short` — 未コミット変更がないか確認 (あれば中断してユーザーに相談)
- `git rev-parse --abbrev-ref HEAD` — 現在のブランチ名
- `git log --oneline -30` — 直近のコミット履歴 (fixup!/squash! が何個あるか)

未コミット変更がある場合は、`git stash` するか事前にコミットするかをユーザーに確認する。勝手に stash しない。

### 2. マージ先ブランチ (base) を確定する

rebase の起点にするため base ブランチを決める。ローカルの情報だけで決まるので `gh` は必須にしない。**当てずっぽうで `main` を使わず、必ず下記の手順で根拠を持って決める。**

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
  - `gh` が使えない / PR が無い場合は候補を選択提示してユーザーに選ばせる
- 確定した base と根拠 (デフォルトブランチ / merge-base 距離 / PR) を、4. の承認依頼で明記する

`git merge-base --fork-point` は reflog 依存で、clone し直した環境や別マシンでは空振りするため確定の根拠には使わない。

rebase の起点を誤ると base 側のコミットまで書き換えてしまうため、base の確定に自信が持てない場合は 4. の承認時に必ずその旨を伝える。

#### 2-5. rebase の起点は base の先端ではなく merge-base にする

`origin/<BASE>` の先端を起点にすると、ブランチを切った後に進んだ base 側のコミットまで取り込まれてしまい、純粋な fixup の折りたたみではなくなる。autosquash はコミットのまとめだけを行うべきなので、**起点はブランチが分岐した時点のコミット (merge-base) に固定する**。

```bash
MB=$(git merge-base HEAD origin/<BASE>)
echo "$MB"
```

以降の手順ではこの `<MB>` を起点として使う。`<MB>` が `origin/<BASE>` の先端と一致しない場合 (base が先に進んでいる場合)、base の取り込みはこのスキルの担当外であり、必要ならユーザーが別途 rebase する旨を 4. の承認依頼で伝える。

### 3. fixup!/squash! コミットの有無を確認する

```bash
git log --oneline <MB>..HEAD
```

このリスト内に `fixup!` / `squash!` プレフィックスのコミットが存在するかを確認する。1件も無い場合は「autosquash 対象のコミットはありません」と報告して終了する。

### 4. rebase 内容をユーザーに提示して承認を得る

autosquash によってどのコミットがどこにまとめられるかを、`git log` の結果から抜粋してユーザーに提示する。破壊的操作 (履歴書き換え) なので **必ず承認を得てから実行する**。

提示例:
```
以下のコミットを autosquash で以下のようにまとめます:
- <sha> fixup! feat: add X → <sha> feat: add X に統合
- <sha> squash! fix: Y → <sha> fix: Y に統合
base: origin/<BASE> (起点: <MB> = ブランチ分岐時点のコミット)
実行してよろしいですか?
```

### 5. autosquash を実行する

承認後、エディタを開かず非対話で autosquash する:

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "$MB"
```

- `GIT_SEQUENCE_EDITOR=:` により todo リストは編集せずそのまま採用される (autosquash による並び替え・fixup 指定を活かす)。
- 起点は 2-5 で求めた merge-base であること。`origin/<BASE>` を直接渡すと base 側の更新まで取り込まれてしまうので使わない。
- コンフリクトが発生した場合は rebase を中断せず状況をユーザーに報告し、`git rebase --abort` するか手動解決するかを確認する。**勝手に `--abort` しない。**

### 6. 結果を確認する

```bash
git log --oneline <MB>..HEAD
```

fixup!/squash! コミットが消えて、対応する元コミットにまとまっていることを確認する。

### 7. force push はユーザーが行う

autosquash 後はリモートと履歴が乖離するため force push が必要だが、**AI は絶対に force push を実行しない**。ユーザー自身が実行する。

autosquash 完了時にユーザーへ以下を伝えるだけに留める:

- autosquash が完了したこと
- 必要に応じてユーザー自身で `git push --force-with-lease origin HEAD` を実行してほしいこと (`--force-with-lease` を推奨する旨だけ案内)

`git push` 系のコマンドはこのスキル内で実行しない。

## 注意事項

- **`main` / `master` などの保護ブランチ上では絶対に実行しない。** 現在ブランチがこれらの場合は中断してユーザーに確認する (PR の base ではなく、rebase 対象である HEAD 側のブランチをチェックする)。
- **他人が作業している共有ブランチには実行しない。** rebase 対象は自ブランチのみ。
- コンフリクト時に destructive な回復 (`--abort`, `reset --hard`) を勝手に実行しない。
- `--no-verify` などフック無効化フラグは使わない。
- **base の取り込み (base 側の新しいコミットを HEAD に載せること) はこのスキルでは行わない。** 起点は常に merge-base に固定し、fixup の折りたたみ以外の履歴変化を起こさない。
