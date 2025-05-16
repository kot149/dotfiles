###################################
# Oh-My-Posh
###################################
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme2.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\hunk.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\montys.omp.json" | Invoke-Expression

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Add cwd to PATH
if(-not $env:path.Split(';').Contains('.')){
    $env:path += ";."
}

###################################
# Modules
###################################
Import-Module syntax-highlighting
Import-Module git-completion
Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete

#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module
Import-Module -Name Microsoft.WinGet.CommandNotFound
#f45873b3-b655-43a6-b217-97c00aa0db58

# Import-Module -Name Terminal-Icons


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
