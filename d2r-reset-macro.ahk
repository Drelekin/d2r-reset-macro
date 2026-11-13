; d2r-reset-macro
;
; Creates a new D2R character from settings.ini.
;
; Flow: game menu -> Save and Exit -> (offline tab -> delete) -> Create New ->
; class -> version -> name -> (hardcore) -> Create -> (hardcore OK).
;
; Every step is gated by a small pixel probe around the control it needs, so the
; macro moves as soon as the UI is ready; timeouts are upper bounds, not waits.
; It starts in game, at the Esc menu, on character select, or on the create
; screen, and only runs while D2R is focused (alt-tab aborts a run; BlockInput
; is deliberately never used).
; Coordinates are level-0 (screenSpace=0) fractions of the 16:9 client rect;
; probes only decide when to click and whether the hardcore toggle needs a click.

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

; Match the process too: other windows (a browser tab, a video) can carry the
; game's name in their title.
global winTitle := "Diablo II: Resurrected"
global winExpr := winTitle . " ahk_exe D2R.exe"

global TARGET_ASPECT := 16 / 9
global ASPECT_TOLERANCE := 0.01
global MAX_NAME_LEN := 16
global DELETE_HOLD_MS := 5025   ; the game requires a long press
global DELETE_ATTEMPTS := 2      ; holds tried when the prompt ignores one
global TRANSITION_TIMEOUT_MS := 5000   ; menu / character select / create screen
global DIALOG_TIMEOUT_MS := 3000   ; dropdowns and confirmation dialogs
global DELETE_TIMEOUT_MS := 8000   ; character list after the delete hold
global CLICK_RETRY_MS := 500    ; re-click window while a screen is unchanged
global CLICK_ATTEMPTS := 3
; A probe costs one display frame, so the probe paces the loop; the fast poll
; only yields, and backs off once a wait looks stuck.
global POLL_FAST_MS := 0
global POLL_SLOW_MS := 20
global POLL_FAST_WINDOW_MS := 1500
; Probe thresholds must key off areas (a fill, a frame), never thin strokes:
; glyph fractions shrink as the sample grid gets coarser.
global SAMPLE_CAP := 2000   ; max pixels sampled per probe region
global FADE_SAMPLES := 3      ; frames a fading control must hold
global FADE_SETTLE_MS := 150    ; ...and how long it must then hold still
global DELETE_SETTLE_MS := 250    ; longer settle: a bad hold wastes 5 s
global CAPTURE_DIR := "captures"

; Sleep is precise instead of a whole 15.6 ms scheduler tick.
DllCall("winmm\timeBeginPeriod", "UInt", 1)
OnExit(ReleaseTimerResolution)

; Patch thresholds are expressed as fractions of the probe area.
global RED_ICON_MIN := 0.15   ; red delete/trash icon
global HC_RED_ON := 0.45   ; hardcore banner is red when checked
global HC_RED_OFF := 0.30   ; and neutral/dark when unchecked
global HUD_RED_MIN := 0.30
global HUD_BLUE_MIN := 0.25

global lastProbeDetail := ""
global lastGrabFailed := false

; Client-pixel caches built once per run so probes and clicks do no per-call math.
global ProbeRects := Map()
global PointPx := Map()

; Diagnostics.
global traceEnabled := false
global traceLog := []

; ---------------------------------------------------------------------------
; Coordinates (fractions of the D2R client rect, screenSpace=0)
; ---------------------------------------------------------------------------
global Coords := Map(
    ; HUD "Game Menu" button: opens the menu and closes open panels / chat.
    "gameMenu", [0.4242, 0.9701],
    ; In-game menu -> Save and Exit
    "saveAndExit", [0.5008, 0.4396],
    ; Character-select screen
    "offlineTab", [0.9367, 0.0479],
    "deleteButton", [0.8672, 0.9361],
    "deleteConfirm", [0.4281, 0.5368],
    "createNew", [0.8953, 0.8672],
    ; Character-create screen
    "versionButton", [0.8953, 0.8597],
    "versionClassic3", [0.8953, 0.7950],
    "versionExpansion3", [0.8953, 0.8150],
    "versionReign3", [0.8953, 0.8350],
    "versionExpansion2", [0.8953, 0.8050],
    "versionReign2", [0.8953, 0.8250],
    "backBtn", [0.0852, 0.9188],
    "blurPoint", [0.5000, 0.6000],
    "hardcoreBox", [0.5000, 0.8840],
    "createBtn", [0.9250, 0.9300],
    "hardcoreOk", [0.4289, 0.5368],
    ; Class row
    "Amazon", [0.1668, 0.4550],
    "Assassin", [0.2550, 0.4550],
    "Necromancer", [0.3530, 0.4550],
    "Barbarian", [0.4620, 0.4550],
    "Paladin", [0.5550, 0.4550],
    "Sorceress", [0.6600, 0.4550],
    "Warlock", [0.7600, 0.4550],
    "Druid", [0.8620, 0.4550]
)

; Probe regions (fractions of the client rect, screenSpace=0). Keep these
; small: a probe only ever looks at the control it is gating.
global Regions := Map(
    ; In-game HUD orbs
    "hudHealth", [0.205, 0.830, 0.270, 0.925],
    "hudMana", [0.748, 0.830, 0.810, 0.925],
    ; Menus and character select
    "saveAndExit", [0.430, 0.418, 0.572, 0.462],
    "offlineTabText", [0.905, 0.040, 0.965, 0.053],
    "createNew", [0.833, 0.850, 0.960, 0.906],
    "deleteButton", [0.850, 0.918, 0.884, 0.953],
    ; Character create
    "createBtn", [0.825, 0.891, 0.945, 0.936],
    "toggleBtn", [0.845, 0.070, 0.950, 0.112],
    ; Keep this strip inside both dropdown layouts (a two-entry list sits one
    ; row lower); higher up it samples class artwork.
    "versionListLeft", [0.766, 0.806, 0.776, 0.833],
    "nameField", [0.440, 0.797, 0.560, 0.833],
    "skull", [0.485, 0.868, 0.515, 0.908],
    ; Dialog button (hardcore and delete confirmation share this layout)
    "dialogButton", [0.367, 0.512, 0.491, 0.562]
)

; D2R screen-space calibration scales all UI about the client-rect center.
global spaceScale := [1.0, 0.97, 0.94, 0.92, 0.90]

global classNames := ["Amazon", "Assassin", "Necromancer", "Barbarian", "Paladin", "Sorceress", "Warlock", "Druid"]
global classicClasses := ["Amazon", "Barbarian", "Necromancer", "Paladin", "Sorceress"]

; The version dropdown only lists versions valid for the selected class, so its
; rows shift with the option count.
global versionNames := ["reign", "expansion", "classic"]
global versionRow3 := Map("classic", "versionClassic3", "expansion", "versionExpansion3", "reign", "versionReign3")
global versionRow2 := Map("expansion", "versionExpansion2", "reign", "versionReign2")

global capFrame := 0

; ---------------------------------------------------------------------------
; Settings (re-read on every run, so no reload is needed after editing)
; ---------------------------------------------------------------------------
try
    ReadSettings()
catch as readErr {
    Fail("Could not read settings.ini: " . readErr.Message)
    ExitApp()
}

; Diagnostics: print the current probe state and exit. Used to calibrate new
; UI states and to report a stuck step.
if (A_Args.Length && A_Args[1] = "--probe") {
    ProbeCli()
    ExitApp()
}

; --trace records how long every probe gate took and writes the run to
; captures\<stamp>-trace.txt when the run ends.
for arg in A_Args {
    if (arg = "--trace")
        traceEnabled := true
}

if (macroHotkey = "") {
    Fail("[Hotkeys] macro is missing in settings.ini.")
    ExitApp()
}

try
    Hotkey(macroHotkey, Reset)
catch as hotkeyErr {
    Fail("Could not register hotkey '" . macroHotkey . "': " . hotkeyErr.Message)
    ExitApp()
}
global registeredHotkey := macroHotkey

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
        this.dw := 0        ; DIB width (row stride source)
        this.dh := 0
        this.w := 0         ; last captured region
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
        this.dw := 0
        this.dh := 0
        this.w := 0
        this.h := 0
    }

    ; Capture one screen rect into the top-left of the DIB. The DIB only grows,
    ; so steady-state probing is one small BitBlt and no allocation.
    Grab(x, y, w, h) {
        if (w <= 0 || h <= 0)
            return 0
        if !this.EnsureDib(w, h)
            return 0
        src := DllCall("GetDC", "Ptr", 0, "UPtr")
        ok := DllCall("BitBlt", "Ptr", this.hdc
            , "Int", 0, "Int", 0, "Int", w, "Int", h
            , "Ptr", src, "Int", x, "Int", y, "UInt", 0x00CC0020, "Int")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", src)
        this.w := w
        this.h := h
        return ok
    }

    ; Capture the whole client area. Used by --probe --shot.
    GrabClient() {
        global hwnd
        WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " hwnd)
        return this.Grab(cx, cy, w, h)
    }

    EnsureDib(w, h) {
        if (this.bits && w <= this.dw && h <= this.dh)
            return 1
        this.Release()
        return this.CreateDib(Max(w, 64), Max(h, 64))
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
        this.dw := w
        this.dh := h
        return 1
    }

    ; Sample one sub-rect on a sparse grid: denser for small areas so thin gold
    ; borders are not skipped, capped so a probe stays cheap.
    Stats(sx, sy, sw, sh) {
        global SAMPLE_CAP
        if (sx < 0)
            sx := 0
        if (sy < 0)
            sy := 0
        sw := Min(sw, this.w - sx)
        sh := Min(sh, this.h - sy)
        if (sw <= 0 || sh <= 0)
            return EmptyStats()

        total := sw * sh
        step := 1
        if (total > SAMPLE_CAP)
            step := Ceil(Sqrt(total / SAMPLE_CAP))

        ; Locals: a property read per pixel is much slower than a local.
        bits := this.bits
        stride := this.dw * 4
        step4 := step * 4

        n := 0
        sr := 0, sg := 0, sb := 0
        sl := 0, sl2 := 0
        mn := 255, mx := 0
        gold := 0, red := 0, blue := 0, bright := 0, silver := 0

        y := 0
        while (y < sh) {
            rowOff := (sy + y) * stride
            x := 0
            xoff := sx * 4
            while (x < sw) {
                ; 32-bit BGRA: one read gives blue, green, red.
                v := NumGet(bits, rowOff + xoff, "UInt")
                b := v & 0xFF
                g := (v >> 8) & 0xFF
                r := (v >> 16) & 0xFF
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
                ; Relative hue tests survive brightness / gamma changes.
                if (r > 18 && g > 0.45 * r && g < 0.90 * r && b < 0.60 * r)
                    gold += 1
                if (r > 18 && r > 1.25 * g && r > 1.25 * b)
                    red += 1
                if (b > 18 && b > 1.25 * r && b > 1.25 * g)
                    blue += 1
                ; Neutral and bright: stone/silver UI chrome. Min/max are
                ; inlined because a call per pixel is expensive.
                lo := r
                hi := r
                if (g < lo)
                    lo := g
                else if (g > hi)
                    hi := g
                if (b < lo)
                    lo := b
                else if (b > hi)
                    hi := b
                if (lo > 70 && hi - lo <= 35)
                    silver += 1

                x += step
                xoff += step4
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

    ; Write the current frame as a bottom-up 32-bit BMP. Used by --shot.
    SaveBmp(path) {
        if !this.bits
            return 0
        w := this.w, h := this.h
        srcStride := this.dw * 4
        imgStride := w * 4
        fileSize := 54 + imgStride * h
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
        NumPut("UInt", imgStride * h, hdr, 34)

        f := FileOpen(path, "w", "UTF-8-RAW")
        if !f
            return 0
        f.RawWrite(hdr, 54)
        row := Buffer(imgStride)
        y := h - 1
        while (y >= 0) {
            DllCall("RtlMoveMemory", "Ptr", row, "Ptr", this.bits + y * srcStride, "UInt", imgStride)
            f.RawWrite(row, imgStride)
            y -= 1
        }
        f.Close()
        return 1
    }
}

Return

ProbeCli() {
    global winTitle, winExpr, hwnd, cw, ch, screenSpace, spaceScale

    hwnd := WinExist(winExpr)
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
    BuildMetrics()
    if !GetCapture().GrabClient() {
        FileAppend("screen capture failed`n", "*")
        return
    }

    out := "client " cw "x" ch " screenSpace=" screenSpace "`n"
    for probeName in ["hud", "menu", "charSelect", "offlineSelected", "createScreen"
        , "deleteButton", "nameField", "versionOpen", "versionClosed"
        , "createEnabled", "hcChecked", "hcUnchecked", "dialog"] {
        r := Probe(probeName)
        out .= probeName . "  " . (r.ok ? "TRUE" : "false") . "  " . r.detail . "`n"
    }
    st := StatsOf("skull")
    out .= "skull raw  " . StatLine(st) . "`n"
    out .= "startState " . DetectStartState() . "`n"
    if (A_Args.Length >= 2 && A_Args[2] = "--shot") {
        SaveCapture("probe")
        out .= "capture saved under " CAPTURE_DIR "`n"
    }
    FileAppend(out, "*")
}

ReadSettings() {
    global name, hero, version, delete, hardcore, screenSpace
    global macroHotkey, liveSplitResetHotkey, liveSplitStartHotkey

    ; FileRead handles a BOM; reading the text keeps a BOM from resetting the
    ; settings.
    iniText := FileRead("settings.ini")

    name := IniVal(iniText, "Settings", "name", "")
    hero := IniVal(iniText, "Settings", "hero", "Barbarian")
    version := IniVal(iniText, "Settings", "version", "")
    delete := IniVal(iniText, "Settings", "delete", "0")
    hardcore := IniVal(iniText, "Settings", "hardcore", "0")
    screenSpace := IniVal(iniText, "Settings", "screenSpace", "0")

    macroHotkey := IniVal(iniText, "Hotkeys", "macro", "")

    liveSplitResetHotkey := IniVal(iniText, "LiveSplit", "reset", "")
    liveSplitStartHotkey := IniVal(iniText, "LiveSplit", "start", "")
}

; ---------------------------------------------------------------------------
; Reset
; ---------------------------------------------------------------------------
; Run entry point. With --trace the run is wrapped so the collected timings are
; written even when it aborts early.
Reset(*) {
    global traceEnabled, traceLog

    if !traceEnabled
        return RunMacro()

    traceLog := []
    t0 := Qpc()
    try
        RunMacro()
    finally {
        traceLog.Push(Format("{:8.1f} ms  TOTAL", Qpc() - t0))
        FlushTrace()
    }
}

RunMacro() {
    global winTitle, winExpr, TARGET_ASPECT, ASPECT_TOLERANCE, MAX_NAME_LEN
    global Coords, Regions, classNames, classicClasses, versionNames, versionRow3, versionRow2
    global name, hero, version, delete, hardcore, screenSpace
    global liveSplitResetHotkey, liveSplitStartHotkey
    global hwnd, cw, ch, lastProbeDetail, CAPTURE_DIR

    CoordMode("Mouse", "Client")
    CoordMode("Pixel", "Client")
    lastProbeDetail := ""

    ; A stray hotkey press while alt-tabbed (or with D2R not running) does
    ; nothing.
    hwnd := WinExist(winExpr)
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
    deleteFlag := (delete = "1")
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

    classicClassFlag := false
    for className in classicClasses
        if (hero = className)
            classicClassFlag := true
    isWarlock := (hero = "Warlock")

    ; A version the class does not support falls back to the closest one
    ; instead of failing.
    if (version = "classic" && !classicClassFlag) {
        version := "expansion"
    }
    if (version = "expansion" && isWarlock) {
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

    BuildMetrics()

    ; --- Start state -------------------------------------------------------
    ; Resume from whichever screen D2R is on.
    startKind := DetectStartState()
    if (startKind = 0) {
        StepFail("Start", "Could not detect the current screen.`nStart in game, at character select, or on the create screen.`nIf D2R is in exclusive fullscreen, switch to Windowed or Borderless.")
        return
    }

    ; The run is at a known screen, so the timer can be reset now.
    SendHotkey(liveSplitResetHotkey)

    if (startKind = 1) {
        ; The HUD Game Menu button opens the menu and closes whatever is open
        ; (chat, inventory, ...) in one click. Esc would only close the chat
        ; and need a second press.
        if !ClickAt("gameMenu")
            return
        if !WaitFor("game menu", "menu", TRANSITION_TIMEOUT_MS, FADE_SAMPLES, FADE_SETTLE_MS) {
            ; Fallback for a click the game did not accept (e.g. a prompt over
            ; the panel): Esc still opens the menu.
            Send("{Esc}")
            if !WaitFor("game menu", "menu", TRANSITION_TIMEOUT_MS, FADE_SAMPLES, FADE_SETTLE_MS) {
                StepFail("Game menu", "The game menu did not appear.")
                return
            }
        }
    }

    ; --- Navigate to character select when needed --------------------------
    ; Save and Exit and Back are not retried: their only safe gate ("still on
    ; the menu") also matches the loading screen, and a repeat could land on
    ; character select and pick a different character.
    atCreate := false
    if (startKind = 1 || startKind = 4) {
        if !ClickAt("saveAndExit")
            return
        if !WaitFor("Save and Exit", "charSelect", TRANSITION_TIMEOUT_MS, 1) {
            StepFail("Save and Exit", "The character-select screen did not appear.")
            return
        }
    } else if (startKind = 3) {
        if deleteFlag {
            ; Mid-creation with delete on: go Back, delete, and create again
            ; from a fresh screen.
            if !ClickAt("backBtn")
                return
            if !WaitFor("Back", "charSelect", TRANSITION_TIMEOUT_MS, 1) {
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
        ; Selected tab text is bright white, unselected is dim.
        if !IsNow("offlineSelected") {
            if !ClickThrough("Offline tab", "offlineTab", "charSelect", "offlineSelected", TRANSITION_TIMEOUT_MS) {
                StepFail("Offline tab", "The offline tab did not become selected.")
                return
            }
        }

        ; --- Optional delete ----------------------------------------------
        if deleteFlag {
            if !WaitFor("delete button", "deleteButton", TRANSITION_TIMEOUT_MS, 1, FADE_SETTLE_MS) {
                StepFail("Delete", "The offline character list / delete button did not appear.")
                return
            }
            ; Not retried: a second click on the modal prompt could cancel it.
            if !ClickAt("deleteButton")
                return
            ; The prompt fades in; hold only once it stops moving, because a
            ; press swallowed by the animation is lost.
            if !WaitFor("delete confirmation", "dialog", DIALOG_TIMEOUT_MS, FADE_SAMPLES, DELETE_SETTLE_MS) {
                SaveCapture("delete-dialog")
                StepFail("Delete", "The delete-confirmation prompt did not appear.`nA screenshot was saved under the " CAPTURE_DIR " folder.")
                return
            }

            ; The game needs a long press (~5 s); release commits it. The end of
            ; the progress ring cannot be probed: the prompt stays up until the
            ; button is released.
            closed := false
            Loop DELETE_ATTEMPTS {
                if !HoldFor("deleteConfirm", DELETE_HOLD_MS) {
                    StepFail("Delete", "Lost focus while holding the delete button.")
                    return
                }
                if WaitFor("delete prompt closed", "dialogGone", DELETE_TIMEOUT_MS, 1) {
                    closed := true
                    break
                }
                ; Still up, so the press was ignored; holding again only
                ; restarts the ring.
                if !IsNow("dialog")
                    break
            }
            if !closed {
                SaveCapture("delete-stuck")
                StepFail("Delete", "The delete prompt did not close after the hold.`nA screenshot was saved under the " CAPTURE_DIR " folder.")
                return
            }

            ; The character list is the reliable post-delete state.
            if !WaitFor("character list", "charSelect", DELETE_TIMEOUT_MS, 1) {
                StepFail("Delete", "The character list did not return after deleting.")
                return
            }
        }

        ; --- Create New ----------------------------------------------------
        if !ClickThrough("Create New", "createNew", "charSelect", "createScreen", TRANSITION_TIMEOUT_MS) {
            StepFail("Create New", "The character-create screen did not appear.`nThe createNew coordinate may need a click-logger check.")
            return
        }
    }

    ; --- Class -------------------------------------------------------------
    ; The name field only appears after the class selection is registered, and
    ; clicking the class row again is harmless, so a dropped click is retried.
    if !ClickThrough("Class", hero, "createScreen", "nameField", TRANSITION_TIMEOUT_MS) {
        StepFail("Class", "The character name field did not appear after selecting " . hero . ".")
        return
    }

    ; --- Version -----------------------------------------------------------
    ; Reign is the create-screen default (and Warlock is Reign-only).
    if (version != "reign") {
        versionCoord := classicClassFlag ? versionRow3[version] : versionRow2[version]
        if !ClickAt("versionButton")
            return
        if !WaitFor("version dropdown", "versionOpen", DIALOG_TIMEOUT_MS, FADE_SAMPLES, FADE_SETTLE_MS) {
            StepFail("Version", "The game-version dropdown did not open.")
            return
        }
        if !ClickAt(versionCoord)
            return
        if !WaitFor("version accepted", "versionClosed", DIALOG_TIMEOUT_MS, 1) {
            StepFail("Version", "The game-version dropdown did not close after selecting " . version . ".")
            return
        }
    }

    ; --- Name --------------------------------------------------------------
    ; The field has focus already, so no click; it is only non-empty when
    ; resuming a half-filled create screen.
    if atCreate
        Send("^a{Backspace}")
    SendText(charName)

    ; The Create button turns gold only after class + name are accepted, which
    ; makes it the readiness gate. Click a neutral spot first so the name field
    ; loses focus.
    if !ClickThrough("Name", "blurPoint", "createScreen", "createEnabled", DIALOG_TIMEOUT_MS) {
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
        if !WaitFor("hardcore selected", "hcChecked", DIALOG_TIMEOUT_MS, FADE_SAMPLES) {
            StepFail("Hardcore", "The Hardcore skull did not turn on.")
            return
        }
    } else if !hardcoreFlag && hcState {
        if !ClickAt("hardcoreBox")
            return
        if !WaitFor("hardcore cleared", "hcUnchecked", DIALOG_TIMEOUT_MS, FADE_SAMPLES) {
            StepFail("Hardcore", "The Hardcore skull did not turn off.")
            return
        }
    }

    ; --- Create ------------------------------------------------------------
    if !ClickAt("createBtn")
        return

    ; The split is sent on the click: the run is over, nothing left to wait for.
    if !hardcoreFlag {
        SendHotkey(liveSplitStartHotkey)
        return
    }

    ; Hardcore confirmation. The OK button is gold-framed (language
    ; independent).
    if !WaitFor("hardcore confirmation", "dialog", DIALOG_TIMEOUT_MS, FADE_SAMPLES, FADE_SETTLE_MS) {
        StepFail("Hardcore OK", "The Hardcore confirmation dialog did not appear.")
        return
    }
    if !ClickAt("hardcoreOk")
        return
    SendHotkey(liveSplitStartHotkey)

    ; Repair a click swallowed by the fade-in, and report a stuck dialog.
    dismissed := false
    Loop CLICK_ATTEMPTS {
        if WaitFor("hardcore dialog closed", "dialogGone", CLICK_RETRY_MS, 1) {
            dismissed := true
            break
        }
        if !ClickAt("hardcoreOk")
            return
    }
    if !dismissed
        StepFail("Hardcore OK", "The Hardcore confirmation dialog did not close.")
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

; Precompute the client-pixel probe rects and click points for the current
; client size and screen-space setting.
BuildMetrics() {
    global Coords, Regions, cw, ch, screenSpace, spaceScale
    global ProbeRects, PointPx

    k := spaceScale[screenSpace + 1]
    ProbeRects := Map()
    for regionName, r in Regions {
        x1 := Max(0, Min(cw, Round(cw * (0.5 + (r[1] - 0.5) * k))))
        y1 := Max(0, Min(ch, Round(ch * (0.5 + (r[2] - 0.5) * k))))
        x2 := Max(0, Min(cw, Round(cw * (0.5 + (r[3] - 0.5) * k))))
        y2 := Max(0, Min(ch, Round(ch * (0.5 + (r[4] - 0.5) * k))))
        ProbeRects[regionName] := [x1, y1, x2, y2]
    }
    PointPx := Map()
    for pointName, p in Coords
        PointPx[pointName] := [Round(cw * (0.5 + (p[1] - 0.5) * k))
            , Round(ch * (0.5 + (p[2] - 0.5) * k))]
}

; Scale a level-0 coordinate about the client-rect center.
ScreenPoint(key) {
    global PointPx
    return PointPx[key]
}

; Returns 0 if the game is not focused (no click is sent).
ClickAt(key) {
    if !GameActive()
        return 0
    p := ScreenPoint(key)
    MouseClick("Left", p[1], p[2], 1, 0)
    return GameActive()
}

; Click a control and wait for the screen to react. The click is repeated only
; while the screen it belongs to is still showing, so a repeat cannot land on
; the next screen. A swallowed click costs CLICK_RETRY_MS, a slow transition
; falls through to one long wait.
ClickThrough(step, key, gateProbe, targetProbe, timeoutMs) {
    global CLICK_RETRY_MS, CLICK_ATTEMPTS

    start := A_TickCount
    Loop CLICK_ATTEMPTS {
        if !ClickAt(key)
            return 0
        if WaitFor(step, targetProbe, CLICK_RETRY_MS, 1)
            return 1
        ; Click accepted: the screen it belonged to is gone, just wait it out.
        if !Probe(gateProbe).ok
            break
    }
    left := timeoutMs - (A_TickCount - start)
    return (left > 0) ? WaitFor(step, targetProbe, left, 1) : 0
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

; One screen read per probe: all of its regions are captured in one BitBlt of
; their bounding box and sampled afterwards. Returns region name -> stats.
StatsBatch(regionKeys) {
    global ProbeRects, hwnd, lastGrabFailed
    static o := Buffer(8, 0)

    ux1 := 1000000000, uy1 := 1000000000, ux2 := -1, uy2 := -1
    for k in regionKeys {
        r := ProbeRects[k]
        if (r[1] < ux1)
            ux1 := r[1]
        if (r[2] < uy1)
            uy1 := r[2]
        if (r[3] > ux2)
            ux2 := r[3]
        if (r[4] > uy2)
            uy2 := r[4]
    }
    uw := ux2 - ux1, uh := uy2 - uy1

    out := Map()
    if (uw <= 0 || uh <= 0) {
        for k in regionKeys
            out[k] := EmptyStats()
        return out
    }

    ; Re-read per probe: a few microseconds, and captures stay correct if the
    ; window moved.
    NumPut("Int", 0, o, 0)
    NumPut("Int", 0, o, 4)
    DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", o.Ptr)
    cap := GetCapture()
    if !cap.Grab(NumGet(o, 0, "Int") + ux1, NumGet(o, 4, "Int") + uy1, uw, uh) {
        lastGrabFailed := true
        for k in regionKeys
            out[k] := EmptyStats()
        return out
    }
    lastGrabFailed := false
    for k in regionKeys {
        r := ProbeRects[k]
        out[k] := cap.Stats(r[1] - ux1, r[2] - uy1, r[3] - r[1], r[4] - r[2])
    }
    return out
}

StatsOf(regionKey) {
    return StatsBatch([regionKey])[regionKey]
}

; ---------------------------------------------------------------------------
; Probes
; ---------------------------------------------------------------------------
; A dialog button is a stone-grey fill with white text and a gold border.
; Key off the grey fill, never the text: the sample grid is sparse, so glyph
; fractions collapse when SAMPLE_CAP or the resolution changes. The fill reads
; ~27% on the dialog vs ~6% on the character list behind it.
DialogButton(st) {
    return st.silverFrac >= 0.15 && st.sdRatio >= 0.45 && st.meanL >= 20
}

DropdownOpen(st) {
    return st.goldFrac < 0.08 && st.redFrac < 0.10 && st.sdRatio < 0.90 && st.meanL > 12
}

; The Toggle button only exists on the create screen and stays gold after the
; Create button turns gold, so it survives a name being entered.
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
    st := StatsOf("skull")
    if (st.redFrac >= HC_RED_ON)
        return 1
    if (st.redFrac <= HC_RED_OFF)
        return 0
    return -1
}

; Probe names are deliberately strings: the switch is easy to extend and the
; detailed stats are kept for failure messages.
Probe(name) {
    switch name {
        case "hud":
            s := StatsBatch(["hudHealth", "hudMana"])
            h := s["hudHealth"]
            m := s["hudMana"]
            return { ok: HudVisible(h, m), sig: Signature(h)
                , detail: "health " StatLine(h) " | mana " StatLine(m) }

        case "menu":
            s := StatsBatch(["saveAndExit", "toggleBtn"])
            st := s["saveAndExit"]
            ; The menu button is silver-framed with white text; silver separates
            ; it from the live game scene at the same spot (~36% vs ~3%).
            ; Exclude the create screen, whose class row overlaps this area.
            t := s["toggleBtn"]
            isCreate := OnCreateScreen(t)
            ok := st.silverFrac >= 0.15 && st.sdRatio <= 1.0
                && st.meanL >= 10 && !isCreate
            return { ok: ok, sig: Signature(st)
                , detail: StatLine(st) . " | createScreen=" (isCreate ? 1 : 0) }

        case "charSelect":
            st := StatsOf("createNew")
            ; Gold frame + red trim + white text; the white keeps in-game
            ; scenery from matching.
            ok := st.goldFrac >= 0.06 && st.redFrac >= 0.05
                && st.brightFrac >= 0.01
                && st.sdRatio <= 1.30 && st.meanL >= 10
            return { ok: ok, sig: Signature(st), detail: StatLine(st) }

        case "createScreen":
            s := StatsBatch(["createBtn", "toggleBtn"])
            c := s["createBtn"]
            t := s["toggleBtn"]
            ok := OnCreateScreen(t)
            return { ok: ok, sig: Signature(t)
                , detail: "create " StatLine(c) " | toggle " StatLine(t) }

        case "offlineSelected":
            st := StatsOf("offlineTabText")
            ; Selected tab text is white, unselected is dim grey.
            ok := st.brightFrac >= 0.05 && st.meanL >= 50
            return { ok: ok, sig: Signature(st), detail: StatLine(st) }

        case "deleteButton":
            st := StatsOf("deleteButton")
            ok := st.redFrac >= RED_ICON_MIN && st.sdRatio <= 1.30 && st.meanL >= 8
            return { ok: ok, sig: Signature(st), detail: StatLine(st) }

        case "nameField":
            st := StatsOf("nameField")
            ; Gold frame + dark, non-flat interior; the char-select panel at the
            ; same spot is flat.
            ok := st.goldFrac >= 0.03 && st.sdRatio >= 0.80
            return { ok: ok, sig: Signature(st), detail: StatLine(st) }

        case "versionOpen":
            st := StatsOf("versionListLeft")
            return { ok: DropdownOpen(st), sig: Signature(st), detail: StatLine(st) }

        case "versionClosed":
            st := StatsOf("versionListLeft")
            return { ok: !DropdownOpen(st), sig: Signature(st), detail: StatLine(st) }

        case "createEnabled":
            st := StatsOf("createBtn")
            ok := st.goldFrac >= 0.05 && st.sdRatio <= 1.35 && st.meanL >= 8
            return { ok: ok, sig: Signature(st), detail: StatLine(st) }

        case "hcChecked":
            st := StatsOf("skull")
            return { ok: st.redFrac >= HC_RED_ON, sig: Signature(st), detail: StatLine(st) }

        case "hcUnchecked":
            st := StatsOf("skull")
            return { ok: st.redFrac <= HC_RED_OFF, sig: Signature(st), detail: StatLine(st) }

            ; Shared by the hardcore and delete confirmation dialogs.
        case "dialog":
            st := StatsOf("dialogButton")
            return { ok: DialogButton(st), sig: Signature(st), detail: StatLine(st) }

        case "dialogGone":
            st := StatsOf("dialogButton")
            return { ok: !DialogButton(st), sig: Signature(st), detail: StatLine(st) }

        default:
            return { ok: 0, sig: [], detail: "unknown probe " name }
    }
}

Signature(st) {
    return [st.meanL, st.sdRatio, st.goldFrac, st.redFrac, st.blueFrac]
}

; True when two signatures are close enough to be the same, finished control.
; A click or hold started while a control still fades in can be swallowed.
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

; One probe, for decisions outside WaitFor.
IsNow(probeName) {
    return Probe(probeName).ok
}

; 0 = unknown, 1 = in game, 2 = character select, 3 = create screen, 4 = menu.
; Menu first: the Esc menu keeps the HUD and the class row visible.
DetectStartState() {
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
; Poll until the probe is true. `samples` = consecutive positive polls: 1 for a
; whole-screen change, FADE_SAMPLES for anything that fades in. `stableMs` also
; requires the signature to stop changing for that long, which tells a finished
; fade-in from one still in progress. Returns 1/0; on timeout the last stats are
; kept for StepFail().
WaitFor(name, probeName, timeoutMs, samples := 2, stableMs := 0) {
    global lastProbeDetail, lastGrabFailed
    global POLL_FAST_MS, POLL_SLOW_MS, POLL_FAST_WINDOW_MS
    global traceEnabled, traceLog

    t0 := traceEnabled ? Qpc() : 0
    start := A_TickCount
    got := 0
    result := 0
    lastSig := 0
    stableSince := 0
    firstOk := 0
    polls := 0
    lastProbeDetail := ""

    while (A_TickCount - start < timeoutMs) {
        if !GameActive() {
            lastProbeDetail := "game lost focus"
            break
        }
        r := Probe(probeName)
        polls += 1
        lastProbeDetail := lastGrabFailed ? "screen capture failed" : r.detail
        if r.ok {
            if !firstOk
                firstOk := A_TickCount - start + 1
            got += 1
            if (got >= samples) {
                if (stableMs <= 0) {
                    result := 1
                    break
                }
                if (stableSince && SigStable(lastSig, r.sig)) {
                    if (A_TickCount - stableSince >= stableMs) {
                        result := 1
                        break
                    }
                } else {
                    stableSince := A_TickCount
                }
                lastSig := r.sig
            }
        } else {
            got := 0
            stableSince := 0
            lastSig := 0
        }
        Sleep((A_TickCount - start < POLL_FAST_WINDOW_MS) ? POLL_FAST_MS : POLL_SLOW_MS)
    }

    if traceEnabled {
        ; first = when the probe matched, held = the fade settle actually paid.
        detail := ""
        if firstOk
            detail .= Format("  first={} ms", firstOk)
        if (result && stableMs > 0)
            detail .= Format("  held={} ms", A_TickCount - start - stableSince)
        traceLog.Push(Format("{:8.1f} ms  {} {:5d} ms  {}  ({} probes{})"
            , Qpc() - t0, result ? "ok  " : "FAIL", timeoutMs, name, polls, detail))
    }
    return result
}

; Hold the left button for ms (the game's hold-to-delete). Always releases.
; Returns 1, or 0 if focus was lost.
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
; Failure and screenshot helpers
; ---------------------------------------------------------------------------
StepFail(step, message) {
    global lastProbeDetail
    ; Alt-tab is a normal abort: do not steal focus with a message box.
    if (lastProbeDetail = "game lost focus")
        return
    detail := (lastProbeDetail != "") ? "`n`nLast pixel state:`n" . lastProbeDetail : ""
    Fail(step . "`n`n" . message . detail)
}

SaveCapture(tag) {
    global CAPTURE_DIR
    if !DirExist(CAPTURE_DIR)
        DirCreate(CAPTURE_DIR)
    if !GetCapture().GrabClient()
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

Fail(message) {
    MsgBox(message, "d2r-reset-macro", "Icon!")
}

; ---------------------------------------------------------------------------
; Watch settings.ini for a changed macro hotkey and re-register it (everything
; else is re-read per run).
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

; ---------------------------------------------------------------------------
; Diagnostics: --trace
; ---------------------------------------------------------------------------
; Monotonic ms clock (A_TickCount is quantized to the scheduler tick).
Qpc() {
    static freq := 0
    if !freq {
        ; The output variable must exist before it is passed to DllCall.
        f := 0
        DllCall("QueryPerformanceFrequency", "Int64*", &f)
        freq := f
    }
    t := 0
    DllCall("QueryPerformanceCounter", "Int64*", &t)
    return t * 1000.0 / freq
}

FlushTrace() {
    global traceLog, CAPTURE_DIR
    if !traceLog.Length
        return
    if !DirExist(CAPTURE_DIR)
        DirCreate(CAPTURE_DIR)
    text := "probe latency, timeout, step (first = probe matched, held = fade settle paid)`n"
    for line in traceLog
        text .= line . "`n"
    path := A_ScriptDir . "\" . CAPTURE_DIR . "\" . FormatTime(, "yyyyMMdd-HHmmss") . "-trace.txt"
    try FileAppend(text, path, "UTF-8")
}

ReleaseTimerResolution(*) {
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}