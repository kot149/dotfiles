#SingleInstance Force
#NoTrayIcon
; -------------------------------------------------
; ** DiscordWindows Group
; -------------------------------------------------
; SetTitleMatchMode "RegEx"
GroupAdd "DiscordWindows", "ahk_exe Discord.exe" ; Desktop App
GroupAdd "DiscordWindows", "ahk_exe DiscordPTB.exe" ; Desktop PTB App
GroupAdd "DiscordWindows", "ahk_exe DiscordCanary.exe" ; Desktop Canary App
; GroupAdd "DiscordWindows", "Discord ahk_exe Chrome.exe" ; Chrome App
; GroupAdd "DiscordWindows", "Discord ahk_exe Vivaldi.exe" ; Vivaldi App
; GroupAdd "DiscordWindows", "Discord ahk_exe Firefox.exe" ; Firefox App

#HotIf WinActive("ahk_group DiscordWindows")
; -------------------------------------------------
; ** Alt+Shift+Up / Down
; -------------------------------------------------
F16::Send "!+{Up}"
F20::Send "!+{Down}"
; F17 & F14::Send "!+{Up}"

; -------------------------------------------------
; ** Alt+Up / Alt+Down
; -------------------------------------------------
F15::Send "!{Up}"
F19::Send "!{Down}"

#HotIf
