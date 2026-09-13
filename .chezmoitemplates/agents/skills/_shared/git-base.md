#### 2-1. Update the remote-tracking refs

```bash
git fetch --prune origin
```

#### 2-2. Get the default branch

```bash
git rev-parse --abbrev-ref origin/HEAD
```

If `origin/HEAD` is unset and this fails, run `git remote set-head origin -a` and fetch it again.

#### 2-3. Find the remote branch with the closest merge-base

To pick up stacked branches (where the base is another feature branch rather than `main`), measure the distance from HEAD for each candidate. Exclude the current branch's own tracking ref from the candidates.

In repositories with hundreds of remote branches, iterating over all of them can take tens of seconds in git process startup time alone, so narrow the candidates down by recency.

```bash
CUR=$(git rev-parse --abbrev-ref HEAD)
UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
HEAD_SHA=$(git rev-parse HEAD)
for r in $(git for-each-ref --format='%(refname:short)' --sort=-committerdate --count=50 --exclude=refs/remotes/origin/HEAD refs/remotes/origin/); do
  [ "$r" = "origin/$CUR" ] && continue
  [ "$r" = "$UP" ] && continue
  mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
  [ "$mb" = "$HEAD_SHA" ] && continue
  echo "$(git rev-list --count "$mb"..HEAD) $r"
done | sort -n | head -5
```

The base candidate almost always falls within `--count=50`, but if the default branch from 2-2 does not appear in the results, rerun without `--count`.

The top entry (shortest distance to HEAD) is the leading base candidate.

#### 2-4. Settle on the base

- If the user explicitly named a base, adopt it and use 2-2 / 2-3 only for verification
- If the results of 2-2 and 2-3 agree, settle on it as `<BASE>`
- If they disagree, or if 2-3 yields multiple candidates at the same distance, gather more evidence:
  - If `gh` is available, prefer the `baseRefName` from `gh pr view --json baseRefName,headRefName,number,title,url`. The PR's base is the declared answer, so it is more trustworthy than the local heuristic
  - If `gh` is unavailable or there is no PR, present the candidates as a selection prompt to the user in Japanese, e.g.:

```
マージ先ブランチの候補が複数あります。どれをベースにしますか:
1. origin/<CANDIDATE_1> (分岐点からの距離: <N> コミット)
2. origin/<CANDIDATE_2> (分岐点からの距離: <N> コミット)
番号でお知らせください。
```

- Whichever path settled it, state the settled base and the evidence (default branch / merge-base distance / PR) in the approval request or plan. Present that rationale to the user in Japanese, e.g.:

```
ベースブランチ: origin/<BASE>
根拠: <EVIDENCE>
```

Do not use `git merge-base --fork-point` as evidence for the decision, since it depends on the reflog and misses on freshly cloned environments or other machines.

#### 2-5. Use the merge-base as the start point, not the tip of the base

Starting from the tip of `origin/<BASE>` pulls in base-side commits made after the branch was cut, causing changes beyond the intended history rewrite. **Always pin the start point to the commit where the branch forked (the merge-base).**

```bash
MB=$(git merge-base HEAD origin/<BASE>)
echo "$MB"
```

Use `<MB>` as the start point from here on. If `<MB>` does not match the tip of `origin/<BASE>` (i.e. the base has moved ahead), incorporating the base is out of scope for this skill; note it in the approval request with the following Japanese message.

```
ベース側に新しいコミットがありますが、このスキルでは取り込みません。必要であれば別途リベースしてください。
```

Picking the wrong start point rewrites base-side commits as well, so if you are not confident about the base, always note it in the approval request with the following Japanese message.

```
ベースブランチの特定に確信がありません。候補: <CANDIDATES_AND_EVIDENCE>。実行前にご確認ください。
```
