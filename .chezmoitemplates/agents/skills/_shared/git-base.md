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

#### 2-4. base を確定させる

- ユーザーが base を明示している場合はそれを採用し、2-2 / 2-3 は検証にだけ使う
- 2-2 と 2-3 の結果が一致すればそれを `<BASE>` として確定する
- 食い違う場合、または 2-3 で同距離の候補が複数並ぶ場合のみ判断材料を増やす:
  - `gh` が使えるなら `gh pr view --json baseRefName,headRefName,number,title,url` の `baseRefName` を優先する。PR の base は宣言された正解なので、ローカルのヒューリスティックより信頼できる
  - `gh` が使えない / PR が無い場合は候補を選択提示してユーザーに選ばせる
- どの経路で決めた場合も、確定した base と根拠 (デフォルトブランチ / merge-base 距離 / PR) をユーザーへの承認依頼・計画提示で明記する

`git merge-base --fork-point` は reflog 依存で、clone し直した環境や別マシンでは空振りするため確定の根拠には使わない。

#### 2-5. 起点は base の先端ではなく merge-base にする

`origin/<BASE>` の先端を起点にすると、ブランチを切った後に進んだ base 側のコミットまで巻き込まれ、意図した履歴操作以外の変化が起きる。**起点はブランチが分岐した時点のコミット (merge-base) に固定する。**

```bash
MB=$(git merge-base HEAD origin/<BASE>)
echo "$MB"
```

以降 `<MB>` を起点として使う。`<MB>` が `origin/<BASE>` の先端と一致しない場合 (base が先に進んでいる場合)、base の取り込みはこのスキルの担当外であり、必要ならユーザーが別途 rebase する旨を承認依頼で伝える。

起点を誤ると base 側のコミットまで書き換えてしまうため、base の確定に自信が持てない場合は承認依頼でその旨を必ず伝える。
