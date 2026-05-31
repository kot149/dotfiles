#SingleInstance Force
#NoTrayIcon
#MaxThreadsPerHotkey 10
#Include *i lib\ImagePut\ImagePut.ahk

PrintScreen::Send "!{PrintScreen}"

+F11::
+PrintScreen::{
	ScreenshotDir := "E:\Pictures\Screenshots"

	ScreenShot := ImagePutBuffer("A")

	SplitPath(WinGetProcessName("A"), &AppName)

	; Create Output Dir
	OutputDir := ScreenshotDir "\" AppName
	DirCreate(OutputDir)

	; Determine Output filename
	OutputFilePath := OutputDir "\" "Screenshot_" FormatTime(, "yyyy-MMdd-HHmm")

	Count := 0
	If FileExist(OutputFilePath ".png"){
		Count++
		while FileExist(OutputFilePath "(" Count ")" ".png")
			Count++
		OutputFilePath := OutputFilePath "(" Count ")"
	}
	OutputFilePath := OutputFilePath ".png"

	; Send Notification
	; A_IconHidden := false
	; TraySetIcon(OutputFilePath)
	; TrayTip(OutputFilePath, "Screenshot has been saved.", 4 | 32)

	; Show Dialog
	width := ImageWidth(ScreenShot)
	height := ImageHeight(ScreenShot)
	w := A_ScreenWidth / 5
	h := A_ScreenHeight / 4
	ratio := Min(w / width, h / height)
	w := Round(width * ratio)
	h := Round(height * ratio)
	x := A_ScreenWidth - w - 20
	y := A_Screenheight - h - 100
	window := ImagePutWindow({image: ScreenShot, scale: ratio}, "ScreenShot has been saved.", [x, y])

	; Output
	ImagePutFile(ScreenShot, OutputFilePath)

	Sleep(500)
	WinClose(window)
}
