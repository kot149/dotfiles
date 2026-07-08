###################################
# Oh-My-Posh
###################################
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "~\.oh-my-posh\themes\mytheme2.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\hunk.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\montys.omp.json" | Invoke-Expression

###################################
# Starship
###################################
Invoke-Expression (&starship init powershell)

# Add cwd to PATH
if(-not $env:path.Split(';').Contains('.')){
    $env:path += ";."
}

###################################
# Modules
###################################
Import-Module syntax-highlighting

# Import-Module -Name Terminal-Icons

# Completions
$script:__completionInitialized = @{
    git     = $false
    docker  = $false
    gh      = $false
    uv      = $false
    chezmoi = $false
    winget  = $false
}

function Initialize-CompletionForCommand {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('git', 'docker', 'gh', 'uv', 'chezmoi', 'winget')]
        [string]$Command
    )

    if ($script:__completionInitialized[$Command]) {
        return
    }

    function Invoke-CompletionScriptAsGlobal {
        param(
            [Parameter(Mandatory)]
            [string]$ScriptText
        )

        $rewritten = $ScriptText -replace '(?m)^\s*(function|filter)\s+(?!global:)([\w:-]+)\s*\{', '$1 global:$2 {'
        Invoke-Expression -Command $rewritten
    }

    switch ($Command) {
        'git' {
            Import-Module posh-git -ErrorAction SilentlyContinue
        }
        'docker' {
            Import-Module DockerCompletion -ErrorAction SilentlyContinue
        }
        'gh' {
            try {
                $scriptText = gh completion -s powershell | Out-String
                Invoke-CompletionScriptAsGlobal -ScriptText $scriptText
            } catch {
            }
        }
        'uv' {
            try {
                Invoke-Expression -Command $(uv generate-shell-completion powershell | Out-String)
            } catch {
            }
        }
        'chezmoi' {
            try {
                $scriptText = chezmoi completion powershell | Out-String
                Invoke-CompletionScriptAsGlobal -ScriptText $scriptText
            } catch {
            }
        }
        'winget' {
            try {
                Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
                    param($wordToComplete, $commandAst, $cursorPosition)
                    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
                    $Local:word = $wordToComplete.Replace('"', '""')
                    $Local:ast = $commandAst.ToString().Replace('"', '""')
                    winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
                }
            } catch {
            }
        }
    }

    $script:__completionInitialized[$Command] = $true
}

function Get-CurrentCommandNameForCompletion {
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ([string]::IsNullOrEmpty($line)) {
        return $null
    }

    if ($cursor -lt 0) {
        $cursor = 0
    }
    if ($cursor -gt $line.Length) {
        $cursor = $line.Length
    }

    $prefix = $line.Substring(0, $cursor)

    $lastSep = [Math]::Max($prefix.LastIndexOf(';'), $prefix.LastIndexOf('|'))
    if ($lastSep -ge 0) {
        $prefix = $prefix.Substring($lastSep + 1)
    }

    $prefix = $prefix.TrimStart()
    if ($prefix.StartsWith('&')) {
        $prefix = $prefix.Substring(1).TrimStart()
    }

    $m = [regex]::Match($prefix, '^(\S+)')
    if (-not $m.Success) {
        return $null
    }

    return $m.Groups[1].Value
}

Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    $cmd = Get-CurrentCommandNameForCompletion
    switch ($cmd) {
        'git'     { Initialize-CompletionForCommand -Command 'git' }
        'docker'  { Initialize-CompletionForCommand -Command 'docker' }
        'gh'      { Initialize-CompletionForCommand -Command 'gh' }
        'uv'      { Initialize-CompletionForCommand -Command 'uv' }
        'chezmoi' { Initialize-CompletionForCommand -Command 'chezmoi' }
        'winget'  { Initialize-CompletionForCommand -Command 'winget' }
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
}

###################################
# Aleases
###################################
function mkcd {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

function mtouch {
    param([Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    } else {
        (Get-Item $Path).LastWriteTime = Get-Date
    }
}

Set-Alias touch mtouch
Remove-Item Alias:ls -Force -ErrorAction Ignore
Remove-Item Alias:ll -Force -ErrorAction Ignore

function ls {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    eza -1 -F=auto --group-directories-first @Args
}

function ll {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    eza -1 -l -F=auto --group-directories-first --header --time-style=long-iso @Args
}

function la {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    eza -a -1 -F=auto --group-directories-first @Args
}

function lla {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    eza -1 -la -F=auto --group-directories-first --header --time-style=long-iso @Args
}
Remove-Item Alias:rm -Force -ErrorAction Ignore
function rm {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $filtered = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in $Args) {
        if ($arg -eq '-r' -or $arg -eq '-R' -or $arg -eq '--recursive') {
            continue
        } elseif ($arg -match '^-[^-]') {
            $newArg = '-' + ($arg.Substring(1) -replace '[rR]', '')
            if ($newArg -ne '-') {
                $filtered.Add($newArg)
            }
        } else {
            $filtered.Add($arg)
        }
    }
    rip @filtered
}

Set-Alias cat Get-Content
# New-Alias -Name grep -Value Select-String

function force-push { git push --force-with-lease --force-if-includes @args }

function sonnet { claude --model claude-sonnet-5 @args }
function opus { claude --model 'claude-opus-4-7[1m]' @args }
function fable { claude --model claude-fable-5 @args }

function git-logout {
	cmdkey /delete:git:https://github.com
}

# .git/info/exclude にローカル限定の無視パターンを追加する
function local-ignore {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Patterns)

    if (-not $Patterns -or $Patterns.Count -eq 0) {
        Write-Host "Usage: local-ignore <pattern>..." -ForegroundColor Yellow
        return
    }

    $gitDir = git rev-parse --git-dir 2>$null
    if (-not $gitDir) {
        Write-Host "fatal: Not a git repository." -ForegroundColor Red
        return
    }

    $infoDir = Join-Path $gitDir "info"
    $excludeFile = Join-Path $infoDir "exclude"
    if (-not (Test-Path $infoDir)) {
        New-Item -ItemType Directory -Path $infoDir -Force | Out-Null
    }

    $existing = @()
    if (Test-Path $excludeFile) {
        $existing = @(Get-Content $excludeFile)
    }

    foreach ($pattern in $Patterns) {
        if ($existing -contains $pattern) {
            Write-Host "Already ignored: $pattern"
        } else {
            Add-Content -Path $excludeFile -Value $pattern
            Write-Host "Added to local ignore: $pattern"
        }
    }
}

function export() {
    ($key, $value) = $args[0] -split "=";
    set-item "env:${key}" $value;
}

function unset() {
    $key = $args[0];
    remove-item "env:${key}";
}

# posh-abbr
$profile_dir = Split-Path -Parent $PROFILE
Import-Module "$profile_dir\posh-abbr\posh-abbr.psd1" -Force

abbr g git
abbr gi git
abbr gti git
abbr 'git cl' 'git clone'
abbr 'git st' 'git status'
abbr 'git sw' 'git switch'
abbr 'git co' 'git checkout'
abbr 'git ch' 'git checkout'
abbr 'git m' 'git checkout main'
abbr 'git br' 'git branch'
abbr 'git fe' 'git fetch'
abbr 'git pl' 'git pull'
abbr 'git pul' 'git pull'
abbr 'git ad' 'git add'
abbr 'git cm' 'git commit -m "%"'
abbr 'git cmm' 'git commit -m "%"'
abbr 'git cmt' 'git commit -m "%"'
abbr 'git mg' 'git merge'
abbr 'git mr' 'git merge'
abbr 'git ps' 'git push'
abbr 'git ph' 'git push'
abbr 'git psh' 'git push'
abbr 'git pb' 'git publish'
abbr 'git pub' 'git publish'

abbr lg lazygit

abbr cz 'chezmoi'
abbr cza 'chezmoi add'
abbr 'chezmoi a' 'chezmoi add'
abbr 'chezmoi ad' 'chezmoi add'

abbr va '.venv\Scripts\activate'

abbr mb 'mise build'
abbr ur 'uv run'
abbr cm 'cargo make'
abbr pnpn pnpm
abbr pmpn pnpm
abbr pmpm pnpm

abbr ag Antigravity

abbr hd herdr
abbr herder herdr
abbr hdr herdr
abbr hrd herdr
abbr hrdr herdr

# Remove conflicting aliases
Remove-Item Alias:ni -Force -ErrorAction Ignore

###################################
# Auto cd
###################################
$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param($commandName, $commandLookupEventArgs)
    if (Test-Path -PathType Container $commandName) {
        $commandLookupEventArgs.CommandScriptBlock = { Set-Location $commandName }.GetNewClosure()
        $commandLookupEventArgs.StopSearch = $true
    }
}

function global:TabExpansion2 {
    [CmdletBinding(DefaultParameterSetName = 'ScriptInputSet')]
    param(
        [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$inputScript,

        [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 1)]
        [int]$cursorColumn,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 0)]
        [System.Management.Automation.Language.Ast]$ast,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 1)]
        [System.Management.Automation.Language.Token[]]$tokens,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 2)]
        [System.Management.Automation.Language.IScriptPosition]$positionOfCursor,

        [Parameter(ParameterSetName = 'ScriptInputSet', Position = 2)]
        [Parameter(ParameterSetName = 'AstInputSet', Position = 3)]
        [Hashtable]$options = $null
    )

    if ($PSCmdlet.ParameterSetName -eq 'ScriptInputSet') {
        $result = [System.Management.Automation.CommandCompletion]::CompleteInput(
            $inputScript, $cursorColumn, $options
        )
        $textBeforeCursor = $inputScript.Substring(0, [Math]::Min($cursorColumn, $inputScript.Length))
    } else {
        $result = [System.Management.Automation.CommandCompletion]::CompleteInput(
            $ast, $tokens, $positionOfCursor, $options
        )
        $textBeforeCursor = $positionOfCursor.Line.Substring(0, $positionOfCursor.ColumnNumber - 1)
    }

    if ($textBeforeCursor -match '^([^\s|;&`]*)$' -and $matches[1] -ne '') {
        $partial = $matches[1]
        $fakeScript = "Set-Location $partial"
        $dirResult = [System.Management.Automation.CommandCompletion]::CompleteInput(
            $fakeScript, $fakeScript.Length, $options
        )
        if ($dirResult.CompletionMatches.Count -gt 0) {
            $existing = @($result.CompletionMatches | ForEach-Object { $_.CompletionText })
            foreach ($c in $dirResult.CompletionMatches) {
                if ($c.CompletionText -notin $existing) {
                    $result.CompletionMatches.Add($c)
                }
            }
        }
    }

    return $result
}

###################################
# FZF
###################################

Invoke-Expression (& {
    $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell | Out-String)
})

# direnv hook
if (Get-Command direnv -ErrorAction SilentlyContinue) {
    if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
    if (-not $env:DIRENV_BASH) {
        $gitBash = $null
        $candidates = @(
            (Get-Command bash -All -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -notlike "*System32*" -and $_.Source -notlike "*WindowsApps*" } |
                Select-Object -ExpandProperty Source)
            (Get-Command git -ErrorAction SilentlyContinue | ForEach-Object {
                $src = $_.Source
                $resolved = (Get-Item -Force $src -ErrorAction SilentlyContinue).Target
                if ($resolved) { $src = $resolved }
                $gitDir = Split-Path -Parent $src
                Join-Path (Split-Path -Parent $gitDir) 'usr\bin\bash.exe'
            })
            "$env:ProgramFiles\Git\usr\bin\bash.exe"
            "$env:ProgramFiles\Git\bin\bash.exe"
            "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
            "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
        )
        foreach ($c in $candidates) {
            if ($c -and (Test-Path $c)) { $gitBash = $c; break }
        }
        if ($gitBash) { $env:DIRENV_BASH = $gitBash }
    }
    Invoke-Expression "$(direnv hook pwsh)"
}

function Invoke-FzfHistory {
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (-not (Test-Path $historyPath)) {
        return
    }

    $lines = [System.IO.File]::ReadAllLines($historyPath)
    if (-not $lines -or $lines.Count -eq 0) {
        return
    }

    [array]::Reverse($lines)
    $selected = $lines | fzf --no-sort --expect=tab
    if (-not $selected) {
        return
    }

    $parts = $selected -split "`n", 2
    $key = $parts[0]
    $cmd = $null
    if ($parts.Length -gt 1) {
        $cmd = $parts[1]
    }

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        return
    }

    if ($key -eq 'tab') {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $cmd
        }
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($cmd)
}

Set-PSReadLineKeyHandler -Chord Alt+h -ScriptBlock {
    Invoke-FzfHistory
}

Set-PSReadLineKeyHandler -Chord Alt+d -ScriptBlock {
    if (Get-Command fcd -ErrorAction SilentlyContinue) {
        fcd
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

Set-PSReadLineKeyHandler -Chord Alt+e -ScriptBlock {
    if (Get-Command superfile -ErrorAction SilentlyContinue) {
        & superfile
    }
}

Set-PSReadLineKeyHandler -Chord Alt+f -ScriptBlock {
    if (Get-Command fz -ErrorAction SilentlyContinue) {
        fz
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

Set-PSReadLineKeyHandler -Chord Alt+g -ScriptBlock {
    if (Get-Command lazygit -ErrorAction SilentlyContinue) {
        & lazygit
    }
}

# fzf enhanced cd function
function fcd() {
    param([string]$Path = ".")

    $dir = Get-ChildItem -Path $Path -Directory -Recurse -ErrorAction SilentlyContinue |
           ForEach-Object { $_.FullName } |
           fzf --height=40% --reverse --border

    if ($dir) {
        Set-Location $dir
    }
}

# Git branch checkout with fzf
function fbr() {
    $branches = git branch -vv
    if ($branches) {
        $branch = $branches | fzf --height=40% --reverse --border
        if ($branch) {
            $branchName = ($branch -split '\s+')[0] -replace '^\*?\s*', ''
            git checkout $branchName
        }
    }
}
Set-Alias fch fbr

# Git branch checkout (including remote branches)
function fbrm() {
    $branches = git branch --all | Where-Object { $_ -notmatch "HEAD" }
    if ($branches) {
        $branch = $branches | fzf --height=40% --reverse --border
        if ($branch) {
            $branchName = ($branch -replace '.*/([^/]+)$', '$1') -replace '^\*?\s*', ''
            git checkout $branchName
        }
    }
}

# Git add with fzf
function fadd() {
    do {
        $files = git status --short |
                 Where-Object { $_.Substring(1,1) -ne ' ' } |
                 ForEach-Object { $_.Substring(3) } |
                 fzf --multi --height=40% --reverse --border --expect=ctrl-d

        if ($files) {
            $lines = $files -split "`n"
            $key = $lines[0]
            $selectedFiles = $lines[1..($lines.Length-1)] | Where-Object { $_ }

            if ($selectedFiles) {
                if ($key -eq "ctrl-d") {
                    git diff --color=always $selectedFiles | less
                } else {
                    git add $selectedFiles
                    Write-Host "Added: $($selectedFiles -join ', ')" -ForegroundColor Green
                }
            }
        }
    } while ($files -and ($key -eq "ctrl-d"))
}
Set-Alias fad fadd

# Git log browser with fzf
function fshow() {
    $commits = git log --graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr"
    if ($commits) {
        $commit = $commits | fzf --ansi --no-sort --reverse --height=40% --border
        if ($commit) {
            $hash = ($commit | Select-String -Pattern '[a-f0-9]{7}').Matches[0].Value
            if ($hash) {
                git show --color=always $hash | less
            }
        }
    }
}

# Git worktree navigation with fzf
function cdworktree() {
    try {
        git rev-parse --git-dir 2>&1 | Out-Null
        $worktrees = git worktree list
        if ($worktrees) {
            $selected = $worktrees | fzf --height=40% --reverse --border
            if ($selected) {
                $path = ($selected -split '\s+')[0]
                Set-Location $path
            }
        }
    } catch {
        Write-Host "fatal: Not a git repository." -ForegroundColor Red
    }
}

Set-Alias fz zi
Set-Alias fzz fz

function Remove-Nul {
    $targetPath = "."
    $files = Get-ChildItem $targetPath -Force
    $nulFile = $files | Where-Object { $_.Name -eq 'nul' }

    if ($nulFile) {
        $extendedPath = "\\?\$($nulFile.FullName)"
        [System.IO.File]::Delete($extendedPath)
        Write-Host "Removed: $($nulFile.FullName)"
    } else {
        Write-Host "Nul file not found"
    }
}
