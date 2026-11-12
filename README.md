# d2r-reset-macro

Automates D2R character resets. Start in a game with the chat box closed and
press the hotkey: it saves and exits, optionally deletes the character, then
creates a new one from `settings.ini`. Only runs while D2R is focused; losing
focus aborts the run.

The flow follows the original known-good v1 script, adapted to the current UI:
`Esc` -> Save and Exit -> (offline tab -> delete) -> Create New -> class ->
version -> name -> (hardcore) -> Create -> (hardcore confirmation). The macro
ends there; it does not wait through the loading screen or move the mouse
afterwards. The offline tab is only clicked if it is not already the selected
tab. After typing the name it clicks a neutral background spot once, because
D2R only enables Create after the name field loses focus.

Every step waits for the actual UI to be ready, then clicks the measured
coordinate. Readiness is detected with small pixel probes around the control
(gold/silver button frames and white text, dialog borders, the hardcore banner
colour, the health and mana orbs). The probes use normalized local contrast and
channel ratios, so
they survive brightness, contrast and gamma changes; probe regions are scaled
with D2R's screen-space setting. There are no delay values to tune:
`[Timeouts]` are upper bounds, and the macro continues as soon as the screen is ready.

16:9 only: windowed or borderless at any 16:9 resolution. Screen Space
Calibration 0-4 is supported (level 0 is the calibrated baseline). `version`
can be `reign` (Reign of the Warlock), `expansion`, or `classic`. Needs
AutoHotkey v2.0+.

Windowed and borderless modes are recommended. Exclusive fullscreen can stop
the screen capture from seeing the game; if a step times out with a black
capture, switch to Windowed or Borderless.

## Setup

Edit `settings.ini`, run `d2r-reset-macro.ahk` with AutoHotkey v2.0+, press
`F12` in game. Hotkey changes are picked up automatically; other changes apply
on the next run. If you prefer the old reload hotkey, uncomment `load=F11`
under `[Hotkeys]`.

You can start in game (chat box closed), at the Esc menu, on character select
(online or offline), or on the character-create screen. The macro detects the
current screen and resumes:

- **In game:** opens the Esc menu, then Save and Exit.
- **Esc menu:** goes straight to Save and Exit.
- **Character select:** switches to the offline tab if needed, deletes when
  `delete=1`, then clicks Create New.
- **Create screen:** continues creating. With `delete=1` it first clicks Back,
  deletes the selected character, then creates again from a fresh screen.

With `delete=1`, the macro deletes the **currently selected character**. Make
sure the throwaway character is selected before starting.

## settings.ini

```ini
[Settings]
; 2-16 chars. empty = hero name. delete=0 adds a 3-letter prefix.
name=
; Name or 1-8:
; Amazon, Assassin, Necromancer, Barbarian, Paladin, Sorceress, Warlock, Druid
hero=5
; reign | expansion | classic
; classic: Amazon, Barbarian, Necromancer, Paladin, Sorceress
; expansion: all except Warlock; reign: all (Warlock is reign-only)
; reign is the create-screen default and needs no dropdown selection.
version=reign
; 1 = delete first, 0 = keep
delete=1
; 1 = hardcore, 0 = softcore
hardcore=1
; D2R > Options > Video > Screen Space Calibration, 0-4
screenSpace=0

[Hotkeys]
; e.g. F12, ^F12, !r, #r
macro=F12
; optional v1-style reload hotkey
; load=F11

[LiveSplit]
; optional; blank to disable
reset=Numpad3          ; sent at start
start=Numpad1          ; sent after Create / hardcore OK

[Timeouts]
; Upper bounds only, not delays.
transition=5000        ; menu / character select / create screen
dialog=3000            ; dropdowns and confirmation dialogs
deleteHold=8000        ; max wait for the character list after the 5 s hold
poll=50                ; probe interval

[Debug]
log=0                  ; 1 = write macro-log.txt
capture=0              ; 1 = save a BMP when a step fails
```

The old `[Delays]` section is accepted but ignored. `actionDelay`,
`saveAndExitDelay` and `createNewDelay` no longer affect the run. The delete
prompt still needs a real hold of about five seconds. That hold is a fixed game
requirement, not a tunable delay; `deleteHold` is the maximum wait for the
character list after it.

### v1 compatibility

If `version` is missing, the old `classic=1` / `classic=0` setting is used
instead (`1` = classic, `0` = expansion). The old `[Hotkeys] load` key is
optional. `[Delays]` is ignored.

## When a step times out

The message names the step and shows the last pixel statistics for that step.
The macro aborts without further clicks, and any mouse button it was holding is
released.

For a report or calibration:

1. Set `[Debug] log=1` (and optionally `capture=1`).
2. Run one reset.
3. Share `macro-log.txt` and any BMP in `captures/`.

Pixel probes are printed by the diagnostic mode:

```
AutoHotkey64.exe d2r-reset-macro.ahk --probe
AutoHotkey64.exe d2r-reset-macro.ahk --probe --shot
```

`--probe` activates D2R, prints each probe's pass/fail and local statistics,
and exits. `--shot` also saves the client area as a BMP under `captures/`.
Because the macro is single-instance, the probe replaces a running macro;
start the macro again afterwards.

## Debugging clicks

Run `click-logger.ahk` with AHK v2 alongside the macro. It writes
`click-log.txt` with each left click's screen position, D2R client fraction,
injected flag, and active window. `Ctrl+Alt+F8` marks the log, `Ctrl+Alt+F9`
toggles logging, and `Ctrl+Alt+F10` exits.

## License

MIT.
