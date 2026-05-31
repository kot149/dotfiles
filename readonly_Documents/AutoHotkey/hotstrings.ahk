#SingleInstance Force
#NoTrayIcon
:*:@d/::{
	SendInput FormatTime(, "yyyy/MM/dd")
}
:*:@d-::{
	SendInput FormatTime(, "yyyy-MM-dd")
}
:*:@dt::{
	SendInput FormatTime(, "yyyy/MM/dd HH:mm")
}


:*:@yw::↑
:*:@ya::←
:*:@ys::↓
:*:@yd::→
