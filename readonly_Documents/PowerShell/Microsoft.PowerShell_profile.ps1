###################################
# Oh-My-Posh
###################################
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
oh-my-posh init pwsh --config "~\.oh-my-posh\themes\mytheme2.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\hunk.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\montys.omp.json" | Invoke-Expression

# Add cwd to PATH
if(-not $env:path.Split(';').Contains('.')){
    $env:path += ";."
}

###################################
# Modules
###################################
Import-Module syntax-highlighting
#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module
# Import-Module -Name Microsoft.WinGet.CommandNotFound
#f45873b3-b655-43a6-b217-97c00aa0db58

# Import-Module -Name Terminal-Icons

# Completions
function Enable-Completion-Lazy {
    # Write-Host "Completions are being initialized..." -ForegroundColor Yellow

    # ---
    Import-Module posh-git
    # Import-Module git-completion
    Import-Module DockerCompletion
    Invoke-Expression -Command $(gh completion -s powershell | Out-String)
    Invoke-Expression -Command $(uv generate-shell-completion powershell | Out-String)
    Invoke-Expression -Command $(chezmoi completion powershell | Out-String)

    # WinGet
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    # ---

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
}

Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    Enable-Completion-Lazy
}

###################################
# Aleases
###################################
Set-Alias touch New-Item
Set-Alias ls Get-ChildItem
Set-Alias ll Get-ChildItem -Force
Set-Alias cat Get-Content
# New-Alias -Name grep -Value Select-String

function git-logout {
	cmdkey /delete:git:https://github.com
}

function export() {
    ($key, $value) = $args[0] -split "=";
    set-item "env:${key}" $value;
}

function unset() {
    $key = $args[0];
    remove-item "env:${key}";
}

Invoke-Expression (& {
    $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell | Out-String)
})

###################################
# FZF Functions
###################################

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
Set-Alias fd fcd

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
