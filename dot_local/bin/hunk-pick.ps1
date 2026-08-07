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

$emptyTree = @() | git hash-object -t tree --stdin

# A repository without any commit has no HEAD, and no base branch to compare
# against, so the entries that need a revision are built accordingly.
git rev-parse --verify --quiet HEAD *> $null
$hasHead = $LASTEXITCODE -eq 0

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
$base = if ($env:HUNK_PICK_BASE) {
    $env:HUNK_PICK_BASE
} elseif ($hasHead) {
    Get-DetectedBase
} else {
    $defaultBase
}

$hasBase = $false
if ($hasHead) {
    git rev-parse --verify --quiet "$base^{commit}" *> $null
    $hasBase = $LASTEXITCODE -eq 0
}

# Parallel lists: $labels[$i] is shown by fzf, $actions[$i] holds the arguments
# passed to `hunk diff` ($null for a non-selectable header).
$labels = [System.Collections.Generic.List[string]]::new()
$actions = [System.Collections.Generic.List[object]]::new()

function Add-Entry {
    param([string]$Label, [object]$Action)

    $labels.Add($Label)
    $actions.Add($Action)
}

if ($hasHead) {
    Add-Entry 'Uncommitted changes (unstaged + staged)' @('HEAD')
} else {
    Add-Entry 'Uncommitted changes (unstaged + staged)' @($emptyTree)
}
Add-Entry ' ├─ Unstaged changes' @()
Add-Entry ' └─ Staged changes' @('--staged')

$maxCommits = 50

# Commits on the current branch, newest first. Falls back to recent history
# when the branch has no commits ahead of the base (e.g. sitting on main).
$commits = @()
if ($hasHead) {
    $range = if ($hasBase) { "$base..HEAD" } else { 'HEAD' }
    $commits = @(git log --format='%h %s' -n $maxCommits $range 2>$null)
    if ($LASTEXITCODE -ne 0) { $commits = @() }

    if ($commits.Count -eq 0 -and $hasBase) {
        $commits = @(git log --format='%h %s' -n $maxCommits HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { $commits = @() }
    }
}

# Children of the branch section: the combined branch + uncommitted entry
# followed by the individual commits.
$childLabels = [System.Collections.Generic.List[string]]::new()
$childActions = [System.Collections.Generic.List[object]]::new()

if ($hasBase) {
    $childLabels.Add("Branch changes + uncommitted changes ($base)")
    $childActions.Add(@($base))
}

foreach ($commit in $commits) {
    $sha = ($commit -split ' ' | Select-Object -First 1)
    git rev-parse --verify --quiet "$sha^" *> $null
    if ($LASTEXITCODE -eq 0) {
        $childActions.Add(@("$sha^..$sha"))
    } else {
        $childActions.Add(@("$emptyTree..$sha"))
    }
    $childLabels.Add($commit)
}

if ($childLabels.Count -gt 0) {
    if ($hasBase) {
        Add-Entry "Branch changes ($base...HEAD)" @("$base...HEAD")
    } else {
        Add-Entry 'Commits' $null
    }

    for ($i = 0; $i -lt $childLabels.Count; $i++) {
        $prefix = if ($i -eq $childLabels.Count - 1) { ' └─ ' } else { ' ├─ ' }
        Add-Entry "$prefix$($childLabels[$i])" $childActions[$i]
    }
}

$items = @($labels)

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
    if ($choice -eq '') { exit 0 }
    $position = Get-CursorPosition -Target $choice -Query $query

    $index = $labels.IndexOf($choice)
    if ($index -lt 0) { continue }

    $diffArgs = $actions[$index]
    if ($null -eq $diffArgs) { continue }

    & hunk diff @diffArgs
    $status = $LASTEXITCODE
    if ($status -ne 0) {
        [Console]::Error.WriteLine("hunk-pick: hunk exited with status $status")
        exit $status
    }
}
