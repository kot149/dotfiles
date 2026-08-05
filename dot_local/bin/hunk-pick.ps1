#!/usr/bin/env pwsh
# Pick a diff range with fzf and open it in hunk. Quitting hunk returns to the
# picker; leave for good with Esc, q or Left arrow there.
Set-StrictMode -Version Latest

# The labels use box-drawing characters, so both sides of every pipe to and
# from a native command have to agree on UTF-8.
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding
[Console]::InputEncoding = $OutputEncoding

git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine('hunk-pick: not inside a git repository')
    exit 1
}

$defaultBase = git symbolic-ref --short refs/remotes/origin/HEAD 2>$null
if ($LASTEXITCODE -ne 0 -or -not $defaultBase) {
    $defaultBase = 'origin/main'
}

$maxBaseCandidates = 50

# Refs that could be the branch point, in preference order for ties: the
# repository default branch first, then recently updated local and origin
# branches.
function Get-BaseCandidates {
    $refs = @($defaultBase)
    $branches = @(git for-each-ref --sort=-committerdate --count=$maxBaseCandidates `
        --format='%(refname:short)' refs/heads refs/remotes/origin 2>$null)
    if ($LASTEXITCODE -eq 0) { $refs += $branches }
    return $refs
}

# The branch the current one was most likely created from: the candidate with
# the fewest commits between its merge base and HEAD. Ancestors of HEAD win over
# diverged branches, so a base that has moved on does not beat the real one.
function Get-DetectedBase {
    $current = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $current = '' }

    $bestBase = ''
    $bestRank = 0
    $bestAhead = 0

    foreach ($cand in Get-BaseCandidates) {
        if (-not $cand) { continue }
        if ($cand -eq $current -or $cand -eq "origin/$current" -or $cand -eq 'origin/HEAD') { continue }

        git rev-parse --verify --quiet "$cand^{commit}" *> $null
        if ($LASTEXITCODE -ne 0) { continue }

        # Commits HEAD has that the candidate does not. Zero means HEAD is
        # already contained in it, so there is no branch diff to show.
        $ahead = git rev-list --count "$cand..HEAD" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $ahead = [int]$ahead
        if ($ahead -le 0) { continue }

        git merge-base --is-ancestor $cand HEAD *> $null
        $rank = if ($LASTEXITCODE -eq 0) { 0 } else { 1 }

        if (-not $bestBase -or $rank -lt $bestRank -or ($rank -eq $bestRank -and $ahead -lt $bestAhead)) {
            $bestBase = $cand
            $bestRank = $rank
            $bestAhead = $ahead
        }
    }

    if ($bestBase) { return $bestBase }
    return $defaultBase
}

# HUNK_PICK_BASE overrides the detection, e.g. when the branch point is
# ambiguous.
$base = if ($env:HUNK_PICK_BASE) { $env:HUNK_PICK_BASE } else { Get-DetectedBase }

$labels = @(
    'Uncommitted changes (unstaged + staged)'
    ' ├─ Unstaged changes'
    ' └─ Staged changes'
    "Branch changes ($base...HEAD)"
    " ├─ Branch changes + uncommitted changes ($base)"
)

$maxCommits = 50

# Commits on the current branch, newest first. Falls back to recent history
# when the branch has no commits ahead of the base (e.g. sitting on main).
$commits = @(git log --format='%h %s' -n $maxCommits "$base..HEAD" 2>$null)
if ($LASTEXITCODE -ne 0) { $commits = @() }

if ($commits.Count -eq 0) {
    $commits = @(git log --format='%h %s' -n $maxCommits HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $commits = @() }
}

# Render the commits as the remaining children of "Branch changes".
$commitLabels = @()
for ($i = 0; $i -lt $commits.Count; $i++) {
    $prefix = if ($i -eq $commits.Count - 1) { ' └─ ' } else { ' ├─ ' }
    $commitLabels += "$prefix$($commits[$i])"
}

if ($commits.Count -eq 0) {
    $labels[4] = " └─ Branch changes + uncommitted changes ($base)"
}

$items = @($labels) + $commitLabels

# The entries fzf shows for a query. --no-sort keeps them in input order, which
# is what the interactive picker displays too.
function Get-FilteredItems {
    param([string]$Query)

    if ([string]::IsNullOrEmpty($Query)) { return $items }

    $filtered = @($items | fzf --filter=$Query --no-sort)
    if ($LASTEXITCODE -ne 0) { return @() }
    return $filtered
}

# 1-based position of an entry among the filtered ones, so the cursor can be
# restored when the picker reopens.
function Get-CursorPosition {
    param([string]$Target, [string]$Query)

    $filtered = @(Get-FilteredItems -Query $Query)
    for ($i = 0; $i -lt $filtered.Count; $i++) {
        if ($filtered[$i] -eq $Target) { return $i + 1 }
    }
    return 1
}

$query = ''
$position = 1

while ($true) {
    # --print-query puts the query on the first line, the selection on the
    # second. pos() needs the result event because filtering is not done yet on
    # start.
    $output = @($items | fzf `
        --prompt='hunk diff > ' --height=100% --reverse --no-sort --sync `
        --print-query --query=$query `
        --bind='q:abort,left:abort' `
        --bind="result:pos($position)+unbind(result)")
    if ($LASTEXITCODE -ne 0) { exit 0 }

    $query = if ($output.Count -ge 1) { $output[0] } else { '' }
    $choice = if ($output.Count -ge 2) { $output[1] } else { '' }
    $position = Get-CursorPosition -Target $choice -Query $query

    $diffArgs = @()
    if ($choice -eq '') {
        exit 0
    } elseif ($choice -eq $labels[0]) {
        $diffArgs = @('HEAD')
    } elseif ($choice -eq $labels[1]) {
        $diffArgs = @()
    } elseif ($choice -eq $labels[2]) {
        $diffArgs = @('--staged')
    } elseif ($choice -eq $labels[3]) {
        $diffArgs = @("$base...HEAD")
    } elseif ($choice -eq $labels[4]) {
        $diffArgs = @($base)
    } else {
        $sha = ($choice -replace '^.*?─ ', '') -split ' ' | Select-Object -First 1
        git rev-parse --verify --quiet "$sha^{commit}" *> $null
        if ($LASTEXITCODE -ne 0) { continue }

        git rev-parse --verify --quiet "$sha^" *> $null
        if ($LASTEXITCODE -eq 0) {
            $diffArgs = @("$sha^..$sha")
        } else {
            $emptyTree = @() | git hash-object -t tree --stdin
            $diffArgs = @("$emptyTree..$sha")
        }
    }

    & hunk diff @diffArgs
    $status = $LASTEXITCODE
    if ($status -ne 0) {
        [Console]::Error.WriteLine("hunk-pick: hunk exited with status $status")
        exit $status
    }
}
