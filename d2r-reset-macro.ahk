; d2r-reset-macro
;
; Creates a new D2R character from settings.ini.
;
; Flow:
;   in game -> Esc -> Save and Exit -> (offline tab -> delete) -> Create New ->
;   class -> version -> name -> (hardcore) -> Create -> (hardcore OK) -> done
;
; Every UI step is gated by a small pixel probe around the control that must be
; on screen. The macro proceeds as soon as the probe is stable, so there is no
; delay tuning. Timeouts in [Timeouts] are upper bounds, not waits.
;
; Start in game (chat closed), at the Esc menu, on character select (online or
; offline), or on the character-create screen. The macro resumes from the
; current screen. It only runs while D2R is the active window and stops as soon
; as the game loses focus. It ends right after Create (or the hardcore OK
; button); it does not wait for the loading screen or touch the mouse after.
; BlockInput is deliberately not used so alt-tab can abort a run without
; leaving input blocked.
;
; Click coordinates are still the measured level-0 (screenSpace=0) fractions of
; the game's 16:9 client rect. Pixel probes only decide when to click and
; whether the hardcore toggle needs a click. ScreenPoint scales coordinates
; about the center for the configured screen-space level.

#Requires AutoHotkey v2.0
#SingleInstance Force
; Keep code warnings out of modal dialogs so they cannot interrupt a run.
#Warn All, StdOut

SetTitleMatchMode(2)
SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Client")
CoordMode("Pixel", "Client")

if !FileExist("settings.ini")
    FileOpen("settings.ini", "a").Close()

global winTitle := "Diablo II: Resurrected"

global TARGET_ASPECT       := 16 / 9
global ASPECT_TOLERANCE    := 0.01
global MAX_NAME_LEN        := 16
global DELETE_HOLD_MS      := 5025     ; the game requires a long press
global INPUT_SETTLE_MS     := 60       ; tiny click settle, not a UI wait
global CAPTURE_DIR         := "captures"
global LOG_FILE            := "macro-log.txt"

; Patch thresholds are expressed as fractions of the probe area.
global RED_ICON_MIN    := 0.15   ; red delete/trash icon
global HC_RED_ON       := 0.45   ; hardcore banner is red when checked
global HC_RED_OFF      := 0.30   ; and neutral/dark when unchecked
global HUD_RED_MIN     := 0.30
global HUD_BLUE_MIN    := 0.25

global lastProbeDetail := ""

; ---------------------------------------------------------------------------
; Coordinates (fractions of the D2R client rect, screenSpace=0)
; ---------------------------------------------------------------------------
global Coords := Map(
    ; In-game menu -> Save and Exit
    "saveAndExit",       [0.5008, 0.4396],

    ; Character-select screen
    "offlineTab",        [0.9367, 0.0479],
    "deleteButton",      [0.8672, 0.9361],
    "deleteConfirm",     [0.4281, 0.5368],
    "createNew",         [0.8953, 0.8672],

    ; Character-create screen
    "versionButton",     [0.8953, 0.8597],
    "versionClassic3",   [0.8953, 0.7950],
    "versionExpansion3", [0.8953, 0.8150],
    "versionReign3",     [0.8953, 0.8350],
    "versionExpansion2", [0.8953, 0.8050],
    "versionReign2",     [0.8953, 0.8250],
    "backBtn",           [0.0852, 0.9188],
    "blurPoint",         [0.5000, 0.6000],
    "hardcoreBox",       [0.5000, 0.8840],
    "createBtn",         [0.9250, 0.9300],
    "hardcoreOk",        [0.4289, 0.5368],

    ; Class row
    "Amazon",            [0.1668, 0.4550],
    "Assassin",          [0.2550, 0.4550],
    "Necromancer",       [0.3530, 0.4550],
    "Barbarian",         [0.4620, 0.4550],
    "Paladin",           [0.5550, 0.4550],
    "Sorceress",         [0.6600, 0.4550],
    "Warlock",           [0.7600, 0.4550],
    "Druid",             [0.8620, 0.4550]
)

; Probe regions (fractions of the client rect, screenSpace=0). Keep these
; small: a probe only ever looks at the control it is gating.
global Regions := Map(
    ; In-game HUD orbs
    "hudHealth",        [0.205, 0.830, 0.270, 0.925],
    "hudMana",          [0.748, 0.830, 0.810, 0.925],

    ; Menus and character select
    "saveAndExit",      [0.430, 0.418, 0.572, 0.462],
    "offlineTabText",   [0.905, 0.040, 0.965, 0.053],
    "createNew",        [0.833, 0.850, 0.960, 0.906],
    "deleteButton",     [0.850, 0.918, 0.884, 0.953],

    ; Character create
    "createBtn",        [0.825, 0.891, 0.945, 0.936],
    "toggleBtn",        [0.845, 0.070, 0.950, 0.112],
    ; The version list pops up above the version button with its rows
    ; vertically centred, so a two-entry list (expansion-only classes such as
    ; Assassin and Druid) sits one row lower than the three-entry list. Keep
    ; this strip inside both layouts; otherwise the top of the strip samples
    ; the class artwork and the open probe reads its gold/red.
    "versionListLeft",  [0.766, 0.806, 0.776, 0.833],
    "nameField",        [0.440, 0.797, 0.560, 0.833],
    "skull",            [0.485, 0.868, 0.515, 0.908],

    ; Dialog button (hardcore and delete confirmation share this layout)
    "dialogButton",     [0.367, 0.512, 0.491, 0.562]
)

; D2R screen-space calibration scales all UI about the client-rect center.
global spaceScale := [1.0, 0.97, 0.94, 0.92, 0.90]

global classNames     := ["Amazon", "Assassin", "Necromancer", "Barbarian", "Paladin", "Sorceress", "Warlock", "Druid"]
global classicClasses := ["Amazon", "Barbarian", "Necromancer", "Paladin", "Sorceress"]

; The version dropdown shows only the versions valid for the selected class,
; so its rows shift depending on the option count. These are the row centers.
global versionNames  := ["reign", "expansion", "classic"]
global versionRow3 := Map("classic", "versionClassic3", "expansion", "versionExpansion3", "reign", "versionReign3")
global versionRow2 := Map("expansion", "versionExpansion2", "reign", "versionReign2")

global capFrame := 0

; ---------------------------------------------------------------------------
; Settings (re-read on every run, so no reload is needed after editing)
; ---------------------------------------------------------------------------
try
    ReadSettings()
catch as err {
    Fail("Could not read settings.ini: " . err.Message)
    ExitApp()
}

if (debugLog = "1") {
    try FileDelete(LOG_FILE)
    Log("settings: hero=" . hero . " version=" . version . " delete=" . delete
        . " hardcore=" . hardcore . " screenSpace=" . screenSpace)
    Log("timeouts: transition=" . timeoutTransition
        . " dialog=" . timeoutDialog . " deleteHold=" . timeoutDeleteHold
        . " poll=" . pollMs)
}

; Diagnostics: print the current probe state and exit. Used to calibrate new
; UI states and to report a stuck step.
if (A_Args.Length && A_Args[1] = "--probe") {
    ProbeCli()
    ExitApp()
}

if (macroHotkey = "") {
    Fail("[Hotkeys] macro is missing in settings.ini.")
    ExitApp()
}

try
    Hotkey(macroHotkey, Reset)
catch as err {
    Fail("Could not register hotkey '" . macroHotkey . "': " . err.Message)
    ExitApp()
}
global registeredHotkey := macroHotkey

; Optional v1-style reload hotkey. A bad value is a warning, not a startup
; failure, because the macro hotkey is the one that matters.
if (loadHotkey != "") {
    try
        Hotkey(loadHotkey, LoadSettings)
    catch as err {
        ToolTip("Could not register load hotkey '" . loadHotkey . "': " . err.Message)
        SetTimer(ClearTip, -2500)
    }
}

global iniStamp := FileGetTime("settings.ini", "M")
SetTimer(WatchSettings, 2000)

; ---------------------------------------------------------------------------
; Pixel capture and statistics
; ---------------------------------------------------------------------------
class Capture {
    __New() {
        this.hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "UPtr")
        this.hbm := 0
        this.obm := 0
        this.bits := 0
        this.w := 0
        this.h := 0
    }

    __Delete() {
        this.Release()
        if this.hdc
            DllCall("DeleteDC", "Ptr", this.hdc)
    }

    Release() {
        if this.obm {
            DllCall("SelectObject", "Ptr", this.hdc, "Ptr", this.obm)
            this.obm := 0
        }
        if this.hbm {
            DllCall("DeleteObject", "Ptr", this.hbm)
            this.hbm := 0
        }
        this.bits := 0
        this.w := 0
        this.h := 0
    }

    ; Capture the client area of the game window into a top-down 32-bit DIB.
    Grab() {
        global hwnd
        WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " hwnd)
        if (w <= 0 || h <= 0)
            return 0
        if (w != this.w || h != this.h) {
            this.Release()
            if !this.CreateDib(w, h)
                return 0
        }
        src := DllCall("GetDC", "Ptr", 0, "UPtr")
        ok := DllCall("BitBlt", "Ptr", this.hdc
            , "Int", 0, "Int", 0, "Int", w, "Int", h
            , "Ptr", src, "Int", cx, "Int", cy, "UInt", 0x00CC0020, "Int")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", src)
        return ok
    }

    CreateDib(w, h) {
        bmi := Buffer(40, 0)
        NumPut("UInt", 40, bmi, 0)          ; biSize
        NumPut("Int", w, bmi, 4)            ; biWidth
        NumPut("Int", -h, bmi, 8)           ; top-down rows
        NumPut("UShort", 1, bmi, 12)        ; planes
        NumPut("UShort", 32, bmi, 14)       ; bit count
        bits := 0
        hbm := DllCall("CreateDIBSection", "Ptr", this.hdc, "Ptr", bmi
            , "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "UPtr")
        if !hbm
            return 0
        this.hbm := hbm
        this.bits := bits
        this.obm := DllCall("SelectObject", "Ptr", this.hdc, "Ptr", hbm, "UPtr")
        this.w := w
        this.h := h
        return 1
    }

    Stats(regionKey) {
        global Regions, screenSpace, spaceScale
        r := Regions[regionKey]
        k := spaceScale[screenSpace + 1]
        w := this.w
        h := this.h
        x1 := Round(w * (0.5 + (r[1] - 0.5) * k))
        y1 := Round(h * (0.5 + (r[2] - 0.5) * k))
        x2 := Round(w * (0.5 + (r[3] - 0.5) * k))
        y2 := Round(h * (0.5 + (r[4] - 0.5) * k))
        return this.StatsRect(x1, y1, x2, y2)
    }

    ; Sample the region on a sparse grid; the grid is denser for small areas so
    ; thin gold borders are not skipped, and capped for speed.
    StatsRect(x1, y1, x2, y2) {
        x1 := Max(0, Min(x1, this.w))
        y1 := Max(0, Min(y1, this.h))
        x2 := Max(0, Min(x2, this.w))
        y2 := Max(0, Min(y2, this.h))
        if (x2 <= x1 || y2 <= y1)
            return EmptyStats()

        total := (x2 - x1) * (y2 - y1)
        step := 1
        if (total > 6000)
            step := Ceil(Sqrt(total / 6000))

        n := 0
        sr := 0, sg := 0, sb := 0
        sl := 0, sl2 := 0
        mn := 255, mx := 0
        gold := 0, red := 0, blue := 0, bright := 0, silver := 0

        y := y1
        while (y < y2) {
            rowOff := (y * this.w) * 4
            x := x1
            while (x < x2) {
                off := rowOff + x * 4
                b := NumGet(this.bits, off, "UChar")
                g := NumGet(this.bits, off + 1, "UChar")
                r := NumGet(this.bits, off + 2, "UChar")
                l := 0.299 * r + 0.587 * g + 0.114 * b

                sr += r
                sg += g
                sb += b
                sl += l
                sl2 += l * l
                n += 1
                if (l < mn)
                    mn := l
                if (l > mx)
                    mx := l
                if (l > 170)
                    bright += 1
                ; Relative hue tests survive global brightness / gamma changes.
                if (r > 18 && g > 0.45 * r && g < 0.90 * r && b < 0.60 * r)
                    gold += 1
                if (r > 18 && r > 1.25 * g && r > 1.25 * b)
                    red += 1
                if (b > 18 && b > 1.25 * r && b > 1.25 * g)
                    blue += 1
                ; Silver/white chrome (menu buttons) is neutral and bright.
                lo := Min(r, Min(g, b))
                hi := Max(r, Max(g, b))
                if (lo > 70 && hi - lo <= 35)
                    silver += 1
                x += step
            }
            y += step
        }

        meanL := sl / n
        sd := Sqrt(Max(0, sl2 / n - meanL * meanL))
        return {
            n: n,
            meanL: meanL,
            minL: mn,
            maxL: mx,
            sd: sd,
            sdRatio: sd / (meanL + 1),
            contrast: (mx - mn) / (mx + mn + 1),
            meanR: sr / n,
            meanG: sg / n,
            meanB: sb / n,
            goldFrac: gold / n,
            redFrac: red / n,
            blueFrac: blue / n,
            brightFrac: bright / n,
            silverFrac: silver / n
        }
    }

    ; Write the current frame as a bottom-up 32-bit BMP. Used only for debug.
    SaveBmp(path) {
        if !this.bits
            return 0
        w := this.w, h := this.h, stride := w * 4
        fileSize := 54 + stride * h
        hdr := Buffer(54, 0)
        NumPut("UChar", 0x42, hdr, 0)       ; 'B'
        NumPut("UChar", 0x4D, hdr, 1)       ; 'M'
        NumPut("UInt", fileSize, hdr, 2)
        NumPut("UInt", 54, hdr, 10)
        NumPut("UInt", 40, hdr, 14)
        NumPut("Int", w, hdr, 18)
        NumPut("Int", h, hdr, 22)
        NumPut("UShort", 1, hdr, 26)
        NumPut("UShort", 32, hdr, 28)
        NumPut("UInt", stride * h, hdr, 34)

        f := FileOpen(path, "w", "UTF-8-RAW")
        if !f
            return 0
        f.RawWrite(hdr, 54)
        row := Buffer(stride)
        y := h - 1
        while (y >= 0) {
            DllCall("RtlMoveMemory", "Ptr", row, "Ptr", this.bits + y * stride, "UInt", stride)
            f.RawWrite(row, stride)
            y -= 1
        }
        f.Close()
        return 1
    }
}

Return

ProbeCli() {
    global winTitle, hwnd, cw, ch, screenSpace, spaceScale, debugCapture

    hwnd := WinExist(winTitle)
    if !hwnd {
        FileAppend("D2R window not found`n", "*")
        return
    }
    WinActivate("ahk_id " hwnd)
    Sleep(150)
    if !WinActive("ahk_id " hwnd) {
        FileAppend("D2R is not the active window`n", "*")
        return
    }

    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc.Ptr)
    cw := NumGet(rc, 8, "Int")
    ch := NumGet(rc, 12, "Int")
    if !GetCapture().Grab() {
        FileAppend("screen capture failed`n", "*")
        return
    }

    out := "client " cw "x" ch " screenSpace=" screenSpace "`n"
    for probeName in ["hud", "menu", "charSelect", "offlineSelected", "createScreen"
        , "deleteButton", "nameField", "versionOpen", "versionClosed"
        , "createEnabled", "hcChecked", "hcUnchecked", "hcDialog", "deleteConfirm"] {
        r := Probe(probeName)
        out .= probeName . "  " . (r.ok ? "TRUE" : "false") . "  " . r.detail . "`n"
    }
    st := StatsOf("skull")
    out .= "skull raw  " . StatLine(st) . "`n"
    out .= "startState " . DetectStartState() . "`n"
    if (A_Args.Length >= 2 && A_Args[2] = "--shot") {
        debugCapture := "1"
        SaveCapture("probe")
        out .= "capture saved under " CAPTURE_DIR "`n"
    }
    FileAppend(out, "*")
}

ReadSettings() {
    global name, hero, version, delete, hardcore, screenSpace
    global macroHotkey, loadHotkey, liveSplitResetHotkey, liveSplitStartHotkey
    global timeoutTransition, timeoutDialog, timeoutDeleteHold, pollMs
    global debugLog, debugCapture, logPath

    name     := ""
    hero     := "Barbarian"
    version  := ""
    delete   := "0"
    hardcore := "0"
    screenSpace := "0"
    macroHotkey := ""
    loadHotkey  := ""
    liveSplitResetHotkey := ""
    liveSplitStartHotkey := ""
    timeoutTransition := "5000"
    timeoutDialog     := "3000"
    timeoutDeleteHold := "8000"
    pollMs            := "50"
    debugLog     := "0"
    debugCapture := "0"
    logPath      := A_ScriptDir . "\" . LOG_FILE

    ; FileRead handles BOMs of any encoding. Parsing the text directly keeps a
    ; UTF-8 BOM from silently resetting the settings.
    iniText := FileRead("settings.ini")

    name     := IniVal(iniText, "Settings", "name", "")
    hero     := IniVal(iniText, "Settings", "hero", "Barbarian")
    version  := IniVal(iniText, "Settings", "version", "")
    delete   := IniVal(iniText, "Settings", "delete", "0")
    hardcore := IniVal(iniText, "Settings", "hardcore", "0")
    screenSpace := IniVal(iniText, "Settings", "screenSpace", "0")

    macroHotkey := IniVal(iniText, "Hotkeys", "macro", "")
    loadHotkey  := IniVal(iniText, "Hotkeys", "load", "")

    liveSplitResetHotkey := IniVal(iniText, "LiveSplit", "reset", "")
    liveSplitStartHotkey := IniVal(iniText, "LiveSplit", "start", "")

    timeoutTransition := IniVal(iniText, "Timeouts", "transition", "5000")
    timeoutDialog     := IniVal(iniText, "Timeouts", "dialog", "3000")
    timeoutDeleteHold := IniVal(iniText, "Timeouts", "deleteHold", "8000")
    pollMs            := IniVal(iniText, "Timeouts", "poll", "50")

    debugLog     := IniVal(iniText, "Debug", "log", "0")
    debugCapture := IniVal(iniText, "Debug", "capture", "0")
    logPath      := A_ScriptDir . "\" . LOG_FILE
}

; ---------------------------------------------------------------------------
; Reset
; ---------------------------------------------------------------------------
Reset(*) {
    global winTitle, TARGET_ASPECT, ASPECT_TOLERANCE, MAX_NAME_LEN
    global Coords, Regions, classNames, classicClasses, versionNames, versionRow3, versionRow2
    global name, hero, version, delete, hardcore, screenSpace
    global liveSplitResetHotkey, liveSplitStartHotkey
    global timeoutTransition, timeoutDialog, timeoutDeleteHold, pollMs
    global hwnd, cw, ch, lastProbeDetail

    CoordMode("Mouse", "Client")
    CoordMode("Pixel", "Client")
    lastProbeDetail := ""

    ; Only run when the game already has focus: a stray hotkey press while
    ; alt-tabbed (or with D2R not running) quietly does nothing.
    hwnd := WinExist(winTitle)
    if !GameActive()
        return

    try
        ReadSettings()
    catch as err {
        Fail("Could not read settings.ini: " . err.Message)
        return
    }

    if (delete != "0" && delete != "1") {
        Fail("Invalid delete '" . delete . "' in settings.ini.`nUse 0 or 1.")
        return
    }
    if (hardcore != "0" && hardcore != "1") {
        Fail("Invalid hardcore '" . hardcore . "' in settings.ini.`nUse 0 or 1.")
        return
    }
    deleteFlag   := (delete = "1")
    hardcoreFlag := (hardcore = "1")

    ; hero may be a number 1-8 or a class name (case-insensitive).
    heroKey := ""
    if IsInteger(hero) {
        index := Integer(hero)
        if (index >= 1 && index <= classNames.Length)
            heroKey := classNames[index]
    } else {
        for className in classNames {
            if (StrLower(hero) = StrLower(className)) {
                heroKey := className
                break
            }
        }
    }
    if (heroKey = "") {
        Fail("Invalid hero '" . hero . "' in settings.ini.`nUse 1-8 or a class name.")
        return
    }
    hero := heroKey

    ; An empty name falls back to the hero name so delete=1 can still create.
    ; A single-character name is doubled because D2R rejects 1-char names.
    if (name = "")
        name := hero
    if (StrLen(name) = 1)
        name := name . name

    ; version may be a number 1-3 or a version name (case-insensitive).
    version := StrLower(Trim(version))
    if (version = "")
        version := "reign"
    if IsInteger(version) {
        index := Integer(version)
        if (index >= 1 && index <= versionNames.Length)
            version := versionNames[index]
    }
    if !versionRow3.Has(version) {
        Fail("Invalid version '" . version . "' in settings.ini.`nUse 1-3 or reign, expansion or classic.")
        return
    }

    if !IsInteger(screenSpace) {
        Fail("Invalid screenSpace '" . screenSpace . "' in settings.ini.`nUse 0-4.")
        return
    }
    screenSpace := Integer(screenSpace)
    if (screenSpace < 0 || screenSpace > 4) {
        Fail("Invalid screenSpace '" . screenSpace . "' in settings.ini.`nUse 0-4.")
        return
    }

    timeoutTransition := ParseTimeout(timeoutTransition, 200, 120000, "transition")
    if (timeoutTransition = 0)
        return
    timeoutDialog := ParseTimeout(timeoutDialog, 200, 120000, "dialog")
    if (timeoutDialog = 0)
        return
    timeoutDeleteHold := ParseTimeout(timeoutDeleteHold, 1000, 120000, "deleteHold")
    if (timeoutDeleteHold = 0)
        return
    pollMs := ParseTimeout(pollMs, 10, 1000, "poll")
    if (pollMs = 0)
        return

    classicClassFlag := false
    for className in classicClasses
        if (hero = className)
            classicClassFlag := true
    isWarlock := (hero = "Warlock")

    ; Keep the run moving when settings contain a version the class does not
    ; support: use the closest available version instead of failing.
    if (version = "classic" && !classicClassFlag) {
        Log("WARN classic is not available for " . hero . "; using expansion")
        version := "expansion"
    }
    if (version = "expansion" && isWarlock) {
        Log("WARN expansion is not available for Warlock; using reign")
        version := "reign"
    }

    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc.Ptr)
    cw := NumGet(rc, 8, "Int")
    ch := NumGet(rc, 12, "Int")
    if (cw = 0 || ch = 0) {
        Fail("Could not read the game's client size.")
        return
    }

    if (Abs(cw / ch - TARGET_ASPECT) / TARGET_ASPECT > ASPECT_TOLERANCE) {
        Fail("Client size " . cw . "x" . ch . " is not 16:9.`nCheck the window mode / resolution.")
        return
    }

    ; Character name: delete=0 gets a short prefix, delete=1 reuses the name.
    if deleteFlag {
        charName := name
    } else {
        letters := "bcdfghjklmnpqrstvwxz"
        charName := ""
        Loop 3 {
            n := Random(1, StrLen(letters))
            charName .= SubStr(letters, n, 1)
        }
        charName .= "_" . name
    }
    charName := SubStr(charName, 1, MAX_NAME_LEN)
    if (StrLen(charName) < 2) {
        Fail("Character name '" . charName . "' is too short.`nUse 1-16 letters.")
        return
    }

    Log("=== run start: hero=" . hero . " version=" . version
        . " delete=" . delete . " hardcore=" . hardcore . " screenSpace=" . screenSpace)

    ; --- Start state -------------------------------------------------------
    ; Resume from whatever screen D2R is on: in game, the Esc menu, character
    ; select (online or offline), or the character-create screen.
    startKind := DetectStartState()
    if (startKind = 0) {
        StepFail("Start", "Could not detect the current screen.`nStart in game, at character select, or on the create screen.`nIf D2R is in exclusive fullscreen, switch to Windowed or Borderless.")
        return
    }

    ; The run is at a known screen, so the timer can be reset now.
    SendHotkey(liveSplitResetHotkey)

    if (startKind = 1) {
        Log("start: in game")
        Send("{Esc}")
        Sleep(INPUT_SETTLE_MS)
        ; If Esc closed the chat box instead of opening the menu, the HUD is
        ; still visible. One more Esc opens the menu.
        if !WaitFor("game menu", "menu", 1000, 150) {
            if !IsNow("menu") && IsNow("hud") {
                Log("still in game after Esc; chat was probably open, pressing Esc again")
                Send("{Esc}")
                Sleep(INPUT_SETTLE_MS)
            }
        }
        if !WaitFor("game menu", "menu", timeoutTransition, 200) {
            StepFail("Game menu", "The Esc menu did not appear.`nClose the chat box and run again.")
            return
        }
    } else if (startKind = 4) {
        Log("start: game menu already open")
    } else if (startKind = 2) {
        Log("start: character select")
    } else if (startKind = 3) {
        Log("start: create screen")
    }

    ; --- Navigate to character select when needed --------------------------
    atCreate := false
    if (startKind = 1 || startKind = 4) {
        if !ClickAt("saveAndExit")
            return
        if !WaitFor("character select", "charSelect", timeoutTransition, 200) {
            StepFail("Save and Exit", "The character-select screen did not appear.")
            return
        }
    } else if (startKind = 3) {
        if deleteFlag {
            ; Starting mid-creation with delete enabled: go Back to character
            ; select, delete, then create again from a fresh screen.
            if !ClickAt("backBtn")
                return
            if !WaitFor("character select", "charSelect", timeoutTransition, 200) {
                StepFail("Back", "The character-select screen did not appear after Back.")
                return
            }
        } else {
            ; Continue on the current create screen.
            atCreate := true
        }
    }

    if !atCreate {
        ; --- Ensure the offline tab ---------------------------------------
        ; The selected tab has bright white text; the unselected tab is dim.
        if IsNow("offlineSelected") {
            Log("offline tab already selected")
        } else {
            if !ClickAt("offlineTab")
                return
            if !WaitFor("offline tab", "offlineSelected", timeoutTransition, 200) {
                StepFail("Offline tab", "The offline tab did not become selected.")
                return
            }
        }

        ; --- Optional delete ----------------------------------------------
        if deleteFlag {
            if !WaitFor("delete button", "deleteButton", timeoutTransition, 150) {
                StepFail("Delete", "The offline character list / delete button did not appear.")
                return
            }
            if !ClickAt("deleteButton")
                return
            if !WaitFor("delete confirmation", "deleteConfirm", timeoutDialog, 200) {
                StepFail("Delete", "The delete-confirmation prompt did not appear.")
                return
            }

            ; The game needs a long press (~5 s); release is what commits it.
            ; Do not try to detect the end of the progress ring: the prompt
            ; stays up until release, and the character-select screen behind
            ; it has gold armour that can fool a border probe.
            start := A_TickCount
            if !HoldFor("deleteConfirm", DELETE_HOLD_MS) {
                StepFail("Delete", "Lost focus while holding the delete button.")
                return
            }
            Log("delete hold released after " . (A_TickCount - start) . " ms")

            if !WaitFor("delete prompt closed", "deleteConfirmGone", timeoutDeleteHold, 150) {
                StepFail("Delete", "The delete prompt did not close after the hold.")
                return
            }

            ; The character list is the reliable post-delete state.
            if !WaitFor("character list", "charSelect", timeoutDeleteHold, 200) {
                StepFail("Delete", "The character list did not return after deleting.")
                return
            }
        }

        ; --- Create New ----------------------------------------------------
        if !ClickAt("createNew")
            return
        if !WaitFor("create screen", "createScreen", timeoutTransition, 200) {
            StepFail("Create New", "The character-create screen did not appear.`nThe createNew coordinate may need a click-logger check.")
            return
        }
    }

    ; --- Class -------------------------------------------------------------
    if !ClickAt(hero)
        return
    ; The name field only appears after the class selection is registered.
    if !WaitFor("class selected", "nameField", timeoutTransition, 150) {
        StepFail("Class", "The character name field did not appear after selecting " . hero . ".")
        return
    }

    ; --- Version -----------------------------------------------------------
    ; Reign is the create-screen default, so it needs no dropdown selection.
    ; (Warlock is Reign-only, so this also covers Warlock.)
    if (version != "reign") {
        versionCoord := classicClassFlag ? versionRow3[version] : versionRow2[version]
        if !ClickAt("versionButton")
            return
        if !WaitFor("version dropdown", "versionOpen", timeoutDialog, 100) {
            StepFail("Version", "The game-version dropdown did not open.")
            return
        }
        if !ClickAt(versionCoord)
            return
        if !WaitFor("version accepted", "versionClosed", timeoutDialog, 100) {
            StepFail("Version", "The game-version dropdown did not close after selecting " . version . ".")
            return
        }
    }

    ; --- Name --------------------------------------------------------------
    ; The name field already has keyboard focus when it appears; no click is
    ; needed (and clicking it would only move the cursor).
    Send("^a")
    Sleep(30)
    if !GameActive()
        return
    Send("{Backspace}")
    Sleep(30)
    if !GameActive()
        return
    SendText(charName)
    Sleep(INPUT_SETTLE_MS)

    ; The Create button only turns gold after the name field loses focus, so
    ; click a neutral background spot to commit the name (not the field).
    if !ClickAt("blurPoint")
        return

    ; The Create button turns gold only once class + name are accepted, so it
    ; is the readiness gate for both the name and the hardcore choice.
    if !WaitFor("name accepted", "createEnabled", timeoutDialog, 150) {
        StepFail("Name", "The Create button did not become ready.`nThe name may be invalid or already in use.")
        return
    }

    ; --- Hardcore ----------------------------------------------------------
    hcState := HardcoreState()
    if (hcState < 0) {
        StepFail("Hardcore", "Could not tell whether the Hardcore skull is selected.")
        return
    }
    if hardcoreFlag && !hcState {
        if !ClickAt("hardcoreBox")
            return
        if !WaitFor("hardcore selected", "hcChecked", timeoutDialog, 100) {
            StepFail("Hardcore", "The Hardcore skull did not turn on.")
            return
        }
    } else if !hardcoreFlag && hcState {
        if !ClickAt("hardcoreBox")
            return
        if !WaitFor("hardcore cleared", "hcUnchecked", timeoutDialog, 100) {
            StepFail("Hardcore", "The Hardcore skull did not turn off.")
            return
        }
    }

    if !WaitFor("Create ready", "createEnabled", timeoutDialog, 100) {
        StepFail("Create", "The Create button is not ready.")
        return
    }

    ; --- Create ------------------------------------------------------------
    if !ClickAt("createBtn")
        return

    ; Hardcore confirmation dialog. The OK button is detected by its gold
    ; border (language independent) and must be stable before clicking.
    if hardcoreFlag {
        if !WaitFor("hardcore confirmation", "hcDialog", timeoutDialog, 250) {
            StepFail("Hardcore OK", "The Hardcore confirmation dialog did not appear.")
            return
        }
        dismissed := false
        Loop 2 {
            if !ClickAt("hardcoreOk")
                return
            if WaitFor("hardcore dialog closed", "hcDialogGone", timeoutDialog, 150) {
                dismissed := true
                break
            }
            Log("hardcore dialog still open after OK; retrying")
        }
        if !dismissed {
            StepFail("Hardcore OK", "The Hardcore confirmation dialog did not close.")
            return
        }
    }

    ; Done: do not wait for the loading screen or move the mouse. The host
    ; timer, if configured, is started immediately after the final click.
    SendHotkey(liveSplitStartHotkey)
    Log("=== run complete")
}

; Parse and validate a [Timeouts] value; returns the integer or 0 on error.
ParseTimeout(value, low, high, key) {
    if !IsInteger(value) {
        Fail("Invalid [Timeouts] " . key . " '" . value . "' in settings.ini.")
        return 0
    }
    n := Integer(value)
    if (n < low || n > high) {
        Fail("Invalid [Timeouts] " . key . " '" . value . "' in settings.ini.`nUse " . low . "-" . high . ".")
        return 0
    }
    return n
}

IniVal(text, section, key, fallback) {
    cur := ""
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if (SubStr(line, 1, 1) = "[") {
            pos := InStr(line, "]")
            if pos
                cur := SubStr(line, 2, pos - 2)
            continue
        }
        if (StrLower(cur) != StrLower(section))
            continue
        eq := InStr(line, "=")
        if !eq
            continue
        if (StrLower(Trim(SubStr(line, 1, eq - 1))) = StrLower(key)) {
            val := Trim(SubStr(line, eq + 1))
            val := Trim(RegExReplace(val, "\s;.*$"))
            return val
        }
    }
    return fallback
}

; True while the game window still exists and has focus.
GameActive() {
    global hwnd
    return hwnd && WinActive("ahk_id " . hwnd)
}

; Scale a level-0 coordinate about the client-rect center.
ScreenPoint(key) {
    global cw, ch, Coords, screenSpace, spaceScale
    p := Coords[key]
    k := spaceScale[screenSpace + 1]
    return [Round(cw * (0.5 + (p[1] - 0.5) * k)), Round(ch * (0.5 + (p[2] - 0.5) * k))]
}

; Returns 0 if the game is not focused (no click is sent).
ClickAt(key) {
    if !GameActive()
        return 0
    p := ScreenPoint(key)
    MouseClick("Left", p[1], p[2])
    Sleep(INPUT_SETTLE_MS)
    return GameActive()
}


EmptyStats() {
    return {
        n: 0, meanL: 0, minL: 0, maxL: 0, sd: 0, sdRatio: 0, contrast: 0,
        meanR: 0, meanG: 0, meanB: 0,
        goldFrac: 0, redFrac: 0, blueFrac: 0, brightFrac: 0, silverFrac: 0
    }
}

GetCapture() {
    global capFrame
    if !capFrame
        capFrame := Capture()
    return capFrame
}

StatsOf(regionKey) {
    return GetCapture().Stats(regionKey)
}

; ---------------------------------------------------------------------------
; Probes
; ---------------------------------------------------------------------------
; A dialog button is a stone-grey fill with bright white text and a gold
; border. The silver/bright part is what distinguishes it from the gold
; shield/armour on the character-select screen behind the prompt.
DialogButton(st) {
    return st.silverFrac >= 0.12 && st.brightFrac >= 0.02
        && st.sdRatio >= 0.45 && st.meanL >= 20
}

DropdownOpen(st) {
    return st.goldFrac < 0.08 && st.redFrac < 0.10 && st.sdRatio < 0.90 && st.meanL > 12
}

; The Toggle button exists only on the character-create screen and is gold
; framed. Keying off it means the probe still works after the Create button
; turns gold (name entered), when the Create button is no longer grey.
OnCreateScreen(t) {
    return t.goldFrac >= 0.03 && t.sdRatio <= 1.20 && t.meanL >= 10
}

HudVisible(h, m) {
    global HUD_RED_MIN, HUD_BLUE_MIN
    return h.meanL >= 8 && m.meanL >= 8
        && h.redFrac >= HUD_RED_MIN && h.meanR > h.meanB * 1.5
        && m.blueFrac >= HUD_BLUE_MIN && m.meanB > m.meanR * 1.5
}

; 1 = checked, 0 = unchecked, -1 = cannot tell.
HardcoreState() {
    global HC_RED_ON, HC_RED_OFF
    GetCapture().Grab()
    st := StatsOf("skull")
    Log("hardcore skull " . StatLine(st))
    if (st.redFrac >= HC_RED_ON)
        return 1
    if (st.redFrac <= HC_RED_OFF)
        return 0
    return -1
}

; Probe names are deliberately strings: the switch is easy to extend and the
; detailed stats are logged on every timeout.
Probe(name) {
    switch name {
        case "hud":
            h := StatsOf("hudHealth")
            m := StatsOf("hudMana")
            return {ok: HudVisible(h, m), sig: Sig(h)
                , detail: "health " StatLine(h) " | mana " StatLine(m)}

        case "menu":
            st := StatsOf("saveAndExit")
            ; The Esc menu button is silver-framed with white text. The HUD is
            ; still visible in the menu, so a colour test cannot be used here.
            ; Silver fraction separates the button from in-game scenery at the
            ; same place (about 36% on the menu, 3% on the live game scene).
            ; Exclude the create screen, whose class row overlaps this area.
            t := StatsOf("toggleBtn")
            isCreate := OnCreateScreen(t)
            ok := st.silverFrac >= 0.15 && st.sdRatio <= 1.0
                && st.meanL >= 10 && !isCreate
            return {ok: ok, sig: Sig(st)
                , detail: StatLine(st) . " | createScreen=" (isCreate ? 1 : 0)}

        case "charSelect":
            st := StatsOf("createNew")
            ; The Create New button has a gold frame, red trim and white text.
            ; The white text is what keeps the in-game HUD/scenery from
            ; matching this region.
            ok := st.goldFrac >= 0.06 && st.redFrac >= 0.05
                && st.brightFrac >= 0.01
                && st.sdRatio <= 1.30 && st.meanL >= 10
            return {ok: ok, sig: Sig(st), detail: StatLine(st)}

        case "createScreen":
            c := StatsOf("createBtn")
            t := StatsOf("toggleBtn")
            ok := OnCreateScreen(t)
            return {ok: ok, sig: Sig(t)
                , detail: "create " StatLine(c) " | toggle " StatLine(t)}

        case "offlineSelected":
            st := StatsOf("offlineTabText")
            ; Selected tab text is white; the unselected tab text is dim grey.
            ok := st.brightFrac >= 0.05 && st.meanL >= 50
            return {ok: ok, sig: Sig(st), detail: StatLine(st)}

        case "deleteButton":
            st := StatsOf("deleteButton")
            ok := st.redFrac >= RED_ICON_MIN && st.sdRatio <= 1.30 && st.meanL >= 8
            return {ok: ok, sig: Sig(st), detail: StatLine(st)}

        case "nameField":
            st := StatsOf("nameField")
            ; Gold frame plus a dark, non-flat interior. The char-select panel
            ; at the same spot is flat; the hidden create-screen field has no
            ; gold frame.
            ok := st.goldFrac >= 0.03 && st.sdRatio >= 0.80
            return {ok: ok, sig: Sig(st), detail: StatLine(st)}

        case "versionOpen":
            st := StatsOf("versionListLeft")
            return {ok: DropdownOpen(st), sig: Sig(st), detail: StatLine(st)}

        case "versionClosed":
            st := StatsOf("versionListLeft")
            return {ok: !DropdownOpen(st), sig: Sig(st), detail: StatLine(st)}

        case "createEnabled":
            st := StatsOf("createBtn")
            ok := st.goldFrac >= 0.05 && st.sdRatio <= 1.35 && st.meanL >= 8
            return {ok: ok, sig: Sig(st), detail: StatLine(st)}

        case "hcChecked":
            st := StatsOf("skull")
            return {ok: st.redFrac >= HC_RED_ON, sig: Sig(st), detail: StatLine(st)}

        case "hcUnchecked":
            st := StatsOf("skull")
            return {ok: st.redFrac <= HC_RED_OFF, sig: Sig(st), detail: StatLine(st)}

        case "hcDialog":
            st := StatsOf("dialogButton")
            return {ok: DialogButton(st), sig: Sig(st), detail: StatLine(st)}

        case "hcDialogGone":
            st := StatsOf("dialogButton")
            return {ok: !DialogButton(st), sig: Sig(st), detail: StatLine(st)}

        case "deleteConfirm":
            st := StatsOf("dialogButton")
            return {ok: DialogButton(st), sig: Sig(st), detail: StatLine(st)}

        case "deleteConfirmGone":
            st := StatsOf("dialogButton")
            return {ok: !DialogButton(st), sig: Sig(st), detail: StatLine(st)}

        default:
            return {ok: 0, sig: [], detail: "unknown probe " name}
    }
}

Sig(st) {
    return [st.meanL, st.sdRatio, st.goldFrac, st.redFrac, st.blueFrac]
}

SigStable(a, b) {
    if !IsObject(a) || !IsObject(b) || a.Length < 5 || b.Length < 5
        return 0
    return Abs(a[1] - b[1]) <= 0.06 * Max(1, a[1])
        && Abs(a[2] - b[2]) <= 0.15
        && Abs(a[3] - b[3]) <= 0.02
        && Abs(a[4] - b[4]) <= 0.02
        && Abs(a[5] - b[5]) <= 0.02
}

StatLine(st) {
    return Format("L={:.0f} sdR={:.2f} gold={:.1f}% red={:.1f}% blue={:.1f}% bright={:.1f}% silver={:.1f}% max={:.0f}"
        , st.meanL, st.sdRatio, st.goldFrac * 100, st.redFrac * 100
        , st.blueFrac * 100, st.brightFrac * 100, st.silverFrac * 100, st.maxL)
}

; One fresh grab + probe, for decisions outside WaitFor.
IsNow(probeName) {
    if !GetCapture().Grab()
        return 0
    return Probe(probeName).ok
}

; 0 = unknown, 1 = in game, 2 = character select, 3 = create screen, 4 = menu.
; The Esc menu keeps the HUD visible, so the menu is checked first; the menu
; probe is false on character select and on the create screen.
DetectStartState() {
    if !GetCapture().Grab()
        return 0
    if Probe("menu").ok
        return 4
    if Probe("hud").ok
        return 1
    ; Check the create screen before character select: with an enabled Create
    ; button its region overlaps Create New and can look like the char list.
    if Probe("createScreen").ok
        return 3
    if Probe("charSelect").ok
        return 2
    return 0
}

; ---------------------------------------------------------------------------
; Wait framework
; ---------------------------------------------------------------------------
; Poll until the probe is true. When stableMs > 0 the probe's stats must also
; stop changing (dialog fade-in), otherwise stableCount positive polls are
; enough. Returns 1/0; on timeout the last stats are kept for StepFail().
WaitFor(name, probeName, timeoutMs, stableMs := 150, stableCount := 2) {
    global pollMs, lastProbeDetail

    start := A_TickCount
    stableStart := 0
    lastSig := 0
    got := 0
    lastProbeDetail := ""

    while (A_TickCount - start < timeoutMs) {
        if !GameActive() {
            lastProbeDetail := "game lost focus"
            Log("ABORT " name ": game lost focus")
            return 0
        }
        if !GetCapture().Grab() {
            lastProbeDetail := "screen capture failed"
            Sleep(pollMs)
            continue
        }
        r := Probe(probeName)
        lastProbeDetail := r.detail
        if r.ok {
            if (stableMs <= 0) {
                got += 1
                if (got >= stableCount) {
                    Log("READY " name " after " (A_TickCount - start) " ms  " r.detail)
                    return 1
                }
            } else {
                if !stableStart {
                    stableStart := A_TickCount
                    lastSig := r.sig
                } else if (A_TickCount - stableStart >= stableMs && SigStable(lastSig, r.sig)) {
                    Log("READY " name " after " (A_TickCount - start) " ms  " r.detail)
                    return 1
                } else if !SigStable(lastSig, r.sig) {
                    stableStart := A_TickCount
                    lastSig := r.sig
                }
            }
        } else {
            got := 0
            stableStart := 0
            lastSig := 0
        }
        Sleep(pollMs)
    }

    Log("TIMEOUT " name " after " timeoutMs " ms  " lastProbeDetail)
    return 0
}

; Hold the left button for ms. Used for the game's hold-to-delete button,
; which needs a continuous long press. The button is always released. Returns
; 1, or 0 if focus was lost.
HoldFor(key, ms) {
    if !GameActive()
        return 0
    p := ScreenPoint(key)
    x := p[1], y := p[2]
    MouseMove(x, y, 0)
    MouseClick("Left", x, y, 1, 0, "D")

    try {
        end := A_TickCount + ms
        while (A_TickCount < end && GameActive())
            Sleep(40)
    } finally {
        MouseClick("Left", , , 1, 0, "U")
    }
    return GameActive()
}

; ---------------------------------------------------------------------------
; Logging and failure helpers
; ---------------------------------------------------------------------------
Log(message) {
    global debugLog, logPath
    if (debugLog != "1")
        return
    if (logPath = "")
        return
    try FileAppend(FormatTime(, "HH:mm:ss") " " message "`n", logPath)
}

StepFail(step, message) {
    global debugCapture, lastProbeDetail
    Log("FAIL " step ": " message " | " lastProbeDetail)
    ; Alt-tab is a normal abort: do not steal focus with a message box.
    if (lastProbeDetail = "game lost focus")
        return
    SaveCapture("fail")
    detail := (lastProbeDetail != "") ? "`n`nLast pixel state:`n" . lastProbeDetail : ""
    Fail(step . "`n`n" . message . detail)
}

SaveCapture(tag) {
    global debugCapture, CAPTURE_DIR
    if (debugCapture != "1")
        return
    if !DirExist(CAPTURE_DIR)
        DirCreate(CAPTURE_DIR)
    if !GetCapture().Grab()
        return
    stamp := FormatTime(, "yyyyMMdd-HHmmss")
    GetCapture().SaveBmp(A_ScriptDir . "\" . CAPTURE_DIR . "\" . stamp . "-" . tag . ".bmp")
}

; Send a hotkey string such as F4, Numpad3, ^F1 or #r.
SendHotkey(key) {
    if (key = "")
        return
    ; Keep modifiers outside the braces: Send "^{F1}", not "{^F1}".
    if RegExMatch(key, "^([\^!+#]+)(.+)$", &m)
        Send(m[1] . "{" . m[2] . "}")
    else
        Send("{" . key . "}")
}

; v1-style reload hotkey.
LoadSettings(*) {
    ToolTip("Loading...")
    Sleep(500)
    Reload()
}

Fail(message) {
    MsgBox(message, "d2r-reset-macro", "Icon!")
}

; ---------------------------------------------------------------------------
; Watch settings.ini for a changed [Hotkeys] macro and re-register it.
; Everything else is re-read on every run, so no reload is needed.
; ---------------------------------------------------------------------------
WatchSettings() {
    global iniStamp, registeredHotkey

    try {
        iniTime := FileGetTime("settings.ini", "M")
        if (iniTime = iniStamp)
            return
        iniStamp := iniTime
        iniText := FileRead("settings.ini")
    } catch {
        return
    }

    newHotkey := IniVal(iniText, "Hotkeys", "macro", "")
    if (newHotkey = "" || newHotkey = registeredHotkey)
        return

    try
        Hotkey(registeredHotkey, "Off")
    catch {
        ; The old hotkey may already be gone; still try the new one.
    }
    try
        Hotkey(newHotkey, Reset)
    catch {
        Hotkey(registeredHotkey, Reset)
        ToolTip("hotkey " . newHotkey . " is unavailable, keeping " . registeredHotkey)
        SetTimer(ClearTip, -2500)
        return
    }
    registeredHotkey := newHotkey
}

ClearTip() {
    ToolTip()
}
