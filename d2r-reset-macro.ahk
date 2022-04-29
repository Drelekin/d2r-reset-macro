FileAppend,, settings.ini, CP0
CoordMode, Mouse, Client

IniRead, macroHotkey, settings.ini, Hotkeys, macro
IniRead, loadHotkey, settings.ini, Hotkeys, load

Hotkey, %macroHotkey%, Reset
Hotkey, %loadHotkey%, Load
Return

Reset:
    rect := WindowGetRect("Diablo II: Resurrected")

    heroY := rect.height * 0.503
    heroXAmazon := rect.width * 0.200
    heroXAssassin := rect.width * 0.303
    heroXNecromancer := rect.width * 0.402
    heroXBarbarian := rect.width * 0.494
    heroXPaladin := rect.width * 0.602
    heroXSorceress := rect.width * 0.712
    heroXDruid := rect.width * 0.809

    ; Settings
    IniRead, name, settings.ini, Settings, name
    IniRead, hero, settings.ini, Settings, hero
    heroX := heroX%hero%
    IniRead, delete, settings.ini, Settings, delete
    IniRead, classic, settings.ini, Settings, classic
    IniRead, hardcore, settings.ini, Settings, hardcore

    ; Delays
    IniRead, saveAndExitDelay, settings.ini, Delays, saveAndExitDelay
    IniRead, loadingDelay, settings.ini, Delays, loadingDelay
    hardcoreDelay := 100
    deleteDelay := 5025

    ; Hotkeys
    IniRead, liveSplitResetHotkey, settings.ini, LiveSplit, reset
    IniRead, liveSplitStartHotkey, settings.ini, LiveSplit, start

    ; Reset
    Send {%liveSplitResetHotkey%}
    BlockInput, On

    Send {Esc}
    MouseClick, left, rect.width * 0.5, rect.height * 0.438
    Sleep, %saveAndExitDelay%

    ; Delete
    if delete {
        MouseClick, left, rect.width * 0.866, rect.height * 0.937
        MouseMove, rect.width * 0.427, rect.height * 0.538
        Send {LButton Down}
        Sleep, %deleteDelay%
        Send {LButton Up}
    }

    ; Create New
    MouseClick, left, rect.width * 0.891, rect.height * 0.868
    Sleep, %loadingDelay%

    ; Select Hero Class
    MouseClick, left, %heroX%, %heroY%

    ; Character Name
    If !delete
    {
        Loop, 5 {
            letters := "bcdfghjklmnpqrstvwxz"
            random, rand, 1, % strlen(letters)
            randomLetter := strsplit(letters) 
            Send, % randomLetter[rand]
        }
        Send _%name%
    } Else
    {
        Send %Name%
    }

    ; Pre-Expansion (Classic)
    If classic
    {
        MouseClick, left, rect.width * 0.519, rect.height * 0.885
    }

    ; Create
    If hardcore {
        MouseClick, left, rect.width * 0.483, rect.height * 0.881
        MouseClick, left, rect.width * 0.914, rect.height * 0.920
        Sleep, %hardcoreDelay%
        MouseClick, left, rect.width * 0.428, rect.height * 0.536
    } Else {
        MouseClick, left, rect.width * 0.914, rect.height * 0.920
    }

    ; Move mouse to center
    MouseMove, (rect.width/2), (rect.height/2)

    BlockInput Off
    Send {%liveSplitStartHotkey%}
return

; Load settings on hotkey
load:
    ToolTip Loading...
    Sleep, 500
    Reload
Return

WindowGetRect(windowTitle*) {
    if hwnd := WinExist(windowTitle*) {
        VarSetCapacity(rect, 16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rect)
        return {width: NumGet(rect, 8, "Int"), height: NumGet(rect, 12, "Int")}
    }
}