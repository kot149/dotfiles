#SingleInstance Force
#NoTrayIcon
; InstallKeybdHook
; InstallMouseHook

SetNumLockState "AlwaysOn"
; SetNumLockState "AlwaysOff"
SetCapsLockState "AlwaysOff"

; -------------------------------------------------
; ** Change Volume Control Step
; -------------------------------------------------
; Volume_Up::SoundSetVolume('+5')
; Volume_Down::SoundSetVolume(-5)

; -------------------------------------------------
; ** Mute/unmute active window's audio session
; -------------------------------------------------
^!+m::Run('nircmdc muteappvolume focused 2', , 'Hide')

; -------------------------------------------------
; ** Maximize/minimize Window
; -------------------------------------------------
#Up::WinMaximize("A")
#Down::WinRestore("A")
!#^Down::WinMinimize("A")

; =================================================
; ** Launch Applications
; =================================================
runAndActivate(app_path, workingDir:=A_WorkingDir, params:="") {
	Run app_path, workingDir, params, &app_pid
	WinWait "ahk_pid " app_pid
	WinActivate
}

; -------------------------------------------------
; ** Calc
; -------------------------------------------------
#c::{
	if !WinExist("電卓 ahk_exe ApplicationFrameHost.exe") {
		Run "calc"
		WinWait("電卓 ahk_exe ApplicationFrameHost.exe")
	}
	WinActivate
}

; -------------------------------------------------
; ** Notepad
; -------------------------------------------------
#n::{
	Run "notepad"
	WinWait("タイトルなし - メモ帳 ahk_exe Notepad.exe")
	WinActivate
}

; -------------------------------------------------
; ** Paint
; -------------------------------------------------
#p::runAndActivate("C:\Program Files\paint.net\paintdotnet.exe", workingDir:="C:\Program Files\paint.net")

; -------------------------------------------------
; ** OBS
; -------------------------------------------------
#o::runAndActivate("C:\Program Files\obs-studio\bin\64bit\obs64.exe", workingDir:="C:\Program Files\obs-studio\bin\64bit")

; -------------------------------------------------
; ** YouTube
; -------------------------------------------------
#y::runAndActivate("~\AppData\Local\Vivaldi\Application\vivaldi_proxy.exe  --profile-directory=`"Profile 3`" --app-id=agimnkijcaahngcdmfeangaknmldooml", workingDir:="~\AppData\Local\Vivaldi\Application")

NumLock::Send("{VKF3}")

; -------------------------------------------------
; ** Sleep
; -------------------------------------------------
#L::{
	DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
}

; -------------------------------------------------
; ** Zenkaku / Hankaku
; -------------------------------------------------
#Include lib\IMEv2\IMEv2.ahk
capslock_timestamp := -1
vkf0:: ; CapsLock on JIS keyboards
vkf3:: ; Hankaku/Zenkaku
vkf4:: ; Hankaku/Zenkaku
CapsLock::{
	global capslock_timestamp
	if A_TickCount - capslock_timestamp > 300 {
		Send('{vk1Dsc07B}') ; IME OFF
	} else {
		Send('{vk1Csc079}') ; IME ON
	}
	capslock_timestamp := A_TickCount
}

; ^!+vkf0::
; ^!+CapsLock::{
; 	SetCapsLockState !GetKeyState("CapsLock", "T")
; }

; Disable Shift+CapsLock, Ctrl+CapsLock, Alt+CapsLock
^CapsLock::
^vkf0::
+CapsLock::
+vkf0::
!CapsLock::
!vkf0::{
	Return
}
