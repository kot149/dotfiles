###################################
# Oh-My-Posh
###################################
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "~\.oh-my-posh\themes\mytheme2.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\hunk.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\montys.omp.json" | Invoke-Expression

function Get-CachedShellInitPath {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string]$CacheName,

        [Parameter(Mandatory)]
        [scriptblock]$Generator,

        [string]$CacheVersion = '1'
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $command) {
        return $null
    }

    $commandInvoker = if ($command.CommandType -in 'Application', 'ExternalScript') {
        $command.Source
    } else {
        $CommandName
    }
    $commandIdentitySource = "${CacheVersion}:$($command.CommandType):$($command.Source):$($command.Definition)"
    try {
        $cacheDir = Join-Path $env:LOCALAPPDATA 'PowerShell\InitCache'
        $commandPathBytes = [System.Text.Encoding]::UTF8.GetBytes($commandIdentitySource)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $commandPathHash = $sha256.ComputeHash($commandPathBytes)
        } finally {
            $sha256.Dispose()
        }
        $commandIdentity = ([BitConverter]::ToString($commandPathHash) -replace '-', '').Substring(0, 12).ToLowerInvariant()
        $cachePath = Join-Path $cacheDir "$CacheName-$commandIdentity.ps1"
        $cacheFile = Get-Item -LiteralPath $cachePath -ErrorAction SilentlyContinue
        $refresh = -not $cacheFile

        if (-not $refresh) {
            $cacheTime = $cacheFile.LastWriteTimeUtc
            $sourceFile = Get-Item -LiteralPath $command.Source -ErrorAction SilentlyContinue
            if ($sourceFile -and $sourceFile.LastWriteTimeUtc -gt $cacheTime) {
                $refresh = $true
            }
        }

        if ($refresh) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            $tempPath = "$cachePath.$PID.tmp"
            try {
                $scriptText = & $Generator $commandInvoker | Out-String
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($scriptText)) {
                    return $null
                }
                [System.IO.File]::WriteAllText($tempPath, $scriptText, [System.Text.UTF8Encoding]::new($false))
                Move-Item -LiteralPath $tempPath -Destination $cachePath -Force | Out-Null
            } finally {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }

        return $cachePath
    } catch {
        return $null
    }
}

###################################
# Starship
###################################
# Agent CLIs (Codex, Claude Code, ...) spawn pwsh with TERM=dumb and a sandbox that
# denies writes to ~/.cache/starship, so starship prepends an error to every command's
# output. Skip the prompt entirely for those shells.
$script:IsAgentShell = ($env:TERM -eq 'dumb') -or [bool]$env:CODEX_SANDBOX -or [bool]$env:CLAUDECODE
$script:PowerShellCommandLine = [Environment]::CommandLine
$script:IsNonInteractive = $script:PowerShellCommandLine -match
    '(?i)(?:^|\s)-(?:NonInteractive|noni)\b'
$script:RunsCommand = $script:PowerShellCommandLine -match
    '(?i)(?:^|\s)-(?:Command|CommandWithArgs|EncodedCommand|File|c|cwa|ec|e|f)\b'
$script:KeepsShellOpen = $script:PowerShellCommandLine -match
    '(?i)(?:^|\s)-(?:NoExit|noe)\b'
$script:IsInteractiveShell = -not $script:IsAgentShell -and
    [Environment]::UserInteractive -and
    -not [Console]::IsInputRedirected -and
    -not $script:IsNonInteractive -and
    ($script:KeepsShellOpen -or -not $script:RunsCommand)

if ($script:IsInteractiveShell) {
    $starshipInitPath = Get-CachedShellInitPath -CommandName starship -CacheName starship -CacheVersion 'full-init-v1' -Generator {
        param($commandPath)
        & $commandPath init powershell --print-full-init
    }
    if ($starshipInitPath) {
        . $starshipInitPath
    } elseif (Get-Command starship -ErrorAction SilentlyContinue) {
        Invoke-Expression (&starship init powershell --print-full-init | Out-String)
    }
}

# Add cwd to PATH
if(-not $env:path.Split(';').Contains('.')){
    $env:path += ";."
}

$env:OPENCODE_CONFIG = "$HOME\.config\opencode\opencode.local.json"

###################################
# Modules
###################################
if ($script:IsInteractiveShell) {
    Import-Module syntax-highlighting -ErrorAction SilentlyContinue
}
$script:CanUsePSReadLine = $script:IsInteractiveShell -and
    [bool](Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)

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

if ($script:CanUsePSReadLine) {
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

function push {
    if ($args.Count -gt 0 -and $args[0] -eq '-f') {
        $rest = $args | Select-Object -Skip 1
        git push --force-with-lease --force-if-includes @rest
    } else {
        git push @args
    }
}

function sonnet { claude --model claude-sonnet-5 @args }
function opus { claude --model 'claude-opus-5[1m]' @args }
function fable { claude --model claude-fable-5 @args }

function Invoke-ClaudeGpt {
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Effort,
        [Parameter()][string]$SubagentModel,
        [Parameter()][string]$SubagentEffort,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$ClaudeArgs
    )

    if ([string]::IsNullOrWhiteSpace($SubagentModel)) {
        $SubagentModel = $Model
    }
    if ([string]::IsNullOrWhiteSpace($SubagentEffort)) {
        $SubagentEffort = $Effort
    }

    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:8317/v1/models' -Headers @{
            Authorization = 'Bearer sk-local-cliproxy'
        } -TimeoutSec 1 | Out-Null
    } catch {
        $proxy = Get-Command cli-proxy-api, server -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $proxy) {
            Write-Error 'CLIProxyAPI is not installed'
            return
        }
        $config = Join-Path $HOME '.config\cli-proxy-api\config.yaml'
        Start-Process -FilePath $proxy.Source -ArgumentList @('-config', $config) -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }

    $names = @(
        'ANTHROPIC_BASE_URL',
        'ANTHROPIC_AUTH_TOKEN',
        'CLAUDE_CODE_SUBAGENT_MODEL',
        'CLAUDE_CODE_ALWAYS_ENABLE_EFFORT',
        'CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY',
        'CLAUDE_CODE_MAX_CONTEXT_TOKENS',
        'ENABLE_TOOL_SEARCH'
    )
    $previous = @{}
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    try {
        $env:ANTHROPIC_BASE_URL = 'http://127.0.0.1:8317'
        $env:ANTHROPIC_AUTH_TOKEN = 'sk-local-cliproxy'
        $env:CLAUDE_CODE_SUBAGENT_MODEL = "$SubagentModel($SubagentEffort)"
        $env:CLAUDE_CODE_ALWAYS_ENABLE_EFFORT = '1'
        $env:CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY = '3'
        $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = '1050000'
        $env:ENABLE_TOOL_SEARCH = 'false'
        claude --model "$Model($Effort)" --effort $Effort @ClaudeArgs
    } finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

function luna { Invoke-ClaudeGpt -Model gpt-5.6-luna -Effort xhigh -ClaudeArgs $args }
function sol { Invoke-ClaudeGpt -Model gpt-5.6-sol -Effort medium -SubagentModel gpt-5.6-luna -SubagentEffort xhigh -ClaudeArgs $args }

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
if ($script:IsInteractiveShell) {
    $profile_dir = Split-Path -Parent $PROFILE
    $poshAbbrModule = "$profile_dir\posh-abbr\posh-abbr.psd1"
    if (Test-Path -LiteralPath $poshAbbrModule) {
        Import-Module $poshAbbrModule -Force

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
    }
}

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

if ($script:IsInteractiveShell) {
    $zoxideHook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
    $zoxideGenerator = {
        param($commandPath)
        & $commandPath init --hook $zoxideHook powershell
    }.GetNewClosure()
    $zoxideInitPath = Get-CachedShellInitPath -CommandName zoxide -CacheName "zoxide-$zoxideHook" -Generator $zoxideGenerator
    Remove-Variable zoxideGenerator
    if ($zoxideInitPath) {
        . $zoxideInitPath
    } elseif (Get-Command zoxide -ErrorAction SilentlyContinue) {
        Invoke-Expression (&zoxide init --hook $zoxideHook powershell | Out-String)
    }
}

# direnv hook
if ($script:IsInteractiveShell -and (Get-Command direnv -ErrorAction SilentlyContinue)) {
    if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
    if (-not $env:DIRENV_BASH) {
        $gitBash = $null
        $bashCommand = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue
        $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
        $gitBashFromPath = if ($gitCommand) {
            $gitPath = $gitCommand.Source
            $resolved = (Get-Item -Force $gitPath -ErrorAction SilentlyContinue).Target
            if ($resolved) { $gitPath = $resolved }
            $gitDir = Split-Path -Parent $gitPath
            Join-Path (Split-Path -Parent $gitDir) 'usr\bin\bash.exe'
        }
        $candidates = @(
            $gitBashFromPath
            if ($bashCommand -and
                $bashCommand.Source -notlike '*System32*' -and
                $bashCommand.Source -notlike '*WindowsApps*') {
                $bashCommand.Source
            }
            "$env:ProgramFiles\Git\usr\bin\bash.exe"
            "$env:ProgramFiles\Git\bin\bash.exe"
            "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
            "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
        )
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                $gitBash = $candidate
                break
            }
        }
        if (-not $gitBash) {
            $gitBash = Get-Command bash -All -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Source -notlike '*System32*' -and
                    $_.Source -notlike '*WindowsApps*' -and
                    (Test-Path -LiteralPath $_.Source)
                } |
                Select-Object -First 1 -ExpandProperty Source
        }
        if ($gitBash) { $env:DIRENV_BASH = $gitBash }
    }
    $direnvInitPath = Get-CachedShellInitPath -CommandName direnv -CacheName direnv -Generator {
        param($commandPath)
        & $commandPath hook pwsh
    }
    if ($direnvInitPath) {
        . $direnvInitPath
    } else {
        Invoke-Expression (&direnv hook pwsh | Out-String)
    }
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

if ($script:CanUsePSReadLine) {
    Set-PSReadLineKeyHandler -Chord Alt+h -ScriptBlock {
        Invoke-FzfHistory
    }

    Set-PSReadLineKeyHandler -Chord Alt+b -ScriptBlock {
        if (Get-Command fbr -ErrorAction SilentlyContinue) {
            fbr
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
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
            $branchName = (($branch -replace '^\*?\s*', '') -split '\s+')[0]
            if ($branchName) {
                git checkout $branchName
            }
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

# herdr: 現在のワークスペースを main(2分割) / sub(2分割) / nvim の3タブ構成にする
function hdr-init {
    if ($env:HERDR_ENV -ne "1") {
        Write-Host "hdr-init: not running inside a herdr session" -ForegroundColor Red
        return
    }
    if (-not (Get-Command herdr -ErrorAction SilentlyContinue)) {
        Write-Host "herdr: command not found" -ForegroundColor Red
        return
    }

    # herdr はUTF-8でJSONを返すので、コンソールがCP932だとパネル名などが壊れて
    # ConvertFrom-Json が失敗する
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    try {
        $ws = ((herdr workspace list | ConvertFrom-Json).result.workspaces |
               Where-Object { $_.focused }).workspace_id
        if (-not $ws) {
            Write-Host "hdr-init: could not resolve focused workspace" -ForegroundColor Red
            return
        }

        $panes = (herdr pane list | ConvertFrom-Json).result.panes
        $mainPane = ($panes | Where-Object { $_.workspace_id -eq $ws -and $_.focused })
        if (-not $mainPane) {
            Write-Host "hdr-init: could not resolve focused pane" -ForegroundColor Red
            return
        }
        $mainTab = $mainPane.tab_id

        # tab1: main (2分割)
        herdr tab rename $mainTab "main" | Out-Null
        herdr pane split $mainPane.pane_id --direction right --no-focus | Out-Null

        # tab2: sub (2分割)
        $subPane = (herdr tab create --workspace $ws --label "sub" --no-focus |
                    ConvertFrom-Json).result.root_pane.pane_id
        herdr pane split $subPane --direction right --no-focus | Out-Null

        # tab3: nvim
        $nvPane = (herdr tab create --workspace $ws --label "nvim" --no-focus |
                   ConvertFrom-Json).result.root_pane.pane_id
        herdr pane run $nvPane "nvim ." | Out-Null

        herdr tab focus $mainTab | Out-Null
    } finally {
        [Console]::OutputEncoding = $prevEncoding
    }
}

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
