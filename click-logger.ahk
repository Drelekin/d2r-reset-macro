; D2R click logger
;
; Run this with AutoHotkey v2 alongside d2r-reset-macro.ahk. It logs every
; left-button down/up with:
;   - screen coordinates
;   - D2R client coordinates and fractions
;   - whether the event was injected by a script
;   - the active window
;
; Ctrl+Alt+F8 writes a marker, Ctrl+Alt+F9 toggles logging, Ctrl+Alt+F10 exits.
; The log is written next to this script as click-log.txt.

#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode(2)

global LogPath := A_ScriptDir "\click-log.txt"
global Logging := true
global Hook := 0
global HookCallback := 0

OnExit(Shutdown)

FileAppend("=== " FormatTime(, "yyyy-MM-dd HH:mm:ss") " click logger started ===`n", LogPath)
FileAppend("screenDPI=" A_ScreenDPI "  log=" LogPath "`n", LogPath)
TrayTip("Ctrl+Alt+F8 marks, Ctrl+Alt+F9 toggles, Ctrl+Alt+F10 exits", "D2R click logger", 1)

HookCallback := CallbackCreate(MouseHook, "Fast", 3)
Hook := DllCall("SetWindowsHookEx", "Int", 14, "Ptr", HookCallback, "Ptr", 0, "UInt", 0, "Ptr")
if !Hook {
    MsgBox("Could not install the mouse hook.", "D2R click logger", "Icon!")
    ExitApp()
}

^!F8::MarkLog()
^!F9::ToggleLogging()
^!F10::ExitApp()

MarkLog() {
    global LogPath
    FileAppend("=== MARK " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ===`n", LogPath)
}

ToggleLogging() {
    global Logging, LogPath
    Logging := !Logging
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  logging=" (Logging ? "on" : "off") "`n", LogPath)
}

MouseHook(nCode, wParam, lParam) {
    global Logging, LogPath

    if (nCode >= 0 && Logging && (wParam = 0x0201 || wParam = 0x0202)) {
        screenX := NumGet(lParam, 0, "Int")
        screenY := NumGet(lParam, 4, "Int")
        flags := NumGet(lParam, 12, "UInt")
        injected := (flags & 0x01) ? 1 : 0
        event := (wParam = 0x0201) ? "DOWN" : "UP"

        activeTitle := ""
        activeProcess := ""
        try activeTitle := WinGetTitle("A")
        try activeProcess := WinGetProcessName("A")

        d2rInfo := "d2r=none"
        fracInfo := "frac=n/a"
        hwnd := WinExist("Diablo II: Resurrected")
        if hwnd {
            try {
                WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
                d2rInfo := "d2rClient=" cx "," cy " " cw "x" ch
                if (cw > 0 && ch > 0)
                    fracInfo := Format("frac={:.4f},{:.4f}", (screenX - cx) / cw, (screenY - cy) / ch)
            }
        }

        line := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            . "  " event
            . "  screen=" screenX "," screenY
            . "  " d2rInfo
            . "  " fracInfo
            . "  injected=" injected
            . "  active=" activeTitle " [" activeProcess "]`n"
        FileAppend(line, LogPath)
    }

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

Shutdown(*) {
    global Hook, HookCallback
    if Hook
        DllCall("UnhookWindowsHookEx", "Ptr", Hook)
    if HookCallback
        CallbackFree(HookCallback)
}
