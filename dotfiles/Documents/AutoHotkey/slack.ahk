#SingleInstance Force
#NoTrayIcon
; -------------------------------------------------
; ** SlackWindows Group
; -------------------------------------------------
; SetTitleMatchMode "RegEx"
GroupAdd "SlackWindows", "ahk_exe Slack.exe" ; Desktop App

#HotIf WinActive("ahk_group SlackWindows")
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
