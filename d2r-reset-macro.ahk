/*
    Settings
*/

; Hero positions
; Use Config hotkey (F7 by default) while inside D2R window to get mouse X and Y positions
; Hover the mouse on top of the classes and paste X positions for all classes
Amazon = 404
Assassin = 597
Necromancer = 782
Barbarian = 959
Paladin = 1167
Sorceress = 1380
Druid = 1555
HeroY = 590 ; Y-position can be the same for all classes

; Settings
Name = Helene
Hero := Sorceress
Hardcore := False
Classic := True
DeleteHero := False

; Timers
Delay = 100
LoadingDelay = 500
DeleteDelay = 5025

; Hotkeys
LiveSplit = F4
Hotkey, f7, Config
Hotkey, f8, Load
Hotkey, f9, Reset
Return

/*
    Macro
*/

Reset:
    Send {%LiveSplit%}
    BlockInput, On

    If DeleteHero
    {
        MouseClick, left, 1680, 1050 ; Click on delete icon
        MouseMove, 840, 625 ; Move mouse to "Yes"
        Send {LButton Down} ; Hold down left mouse
        Sleep, %DeleteDelay%
        Send {LButton Up} ; Release left mouse
    }

    MouseClick, left, 1725, 980 ; Click on "Create New"
    Sleep, %LoadingDelay%
    MouseClick, left, %Hero%, %HeroY% ; Click on the selected Hero
    Sleep, %Delay%

    If !DeleteHero ; Add random characters to "Name" if DeleteHero is false
    {
        Loop, 5 {
            Letters := "bcdfghjklmnpqrstvwxz"
            random, Rand, 1, % strlen(Letters)
            randomLetter := strsplit(Letters) 
            Send, % randomLetter[Rand]
        }
        Send _%Name%
    }
    Else
    {
        Send %Name%
    }

    If Classic
    {
        MouseClick, left, 1014, 1005 ; Click on Pre-Expansion (Classic)
    }

    If Hardcore {
        MouseClick, left, 941, 1005 ; Click on Hardcore
        MouseClick, left, 1775, 1050 ; Click on "Create"
        Sleep, %Delay%
        MouseClick, left, 825, 625 ; Click on "OK" to confirm Hardcore
    }

    Else
    {
        MouseClick, left, 1775, 1050 ; Click on "Create"
    }
    Send {F3}
    BlockInput Off
Return

Config: ; Show mouse position on hotkey to help with settings
    MouseGetPos, xpos, ypos 
    MsgBox, Cursor X%xpos%, Y%ypos%.
Return

Load: ; Load settings on hotkey
    ToolTip Loading...
    Sleep, 500
    Reload