#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

script_dir := A_ScriptDir

Loop Files, script_dir "\*.ahk", "F" {
	if (A_LoopFileFullPath = A_ScriptFullPath) {
		continue
	}
	Run A_LoopFileFullPath
}
