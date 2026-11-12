# d2r-reset-macro

Automates D2R character resets. Start in game with chat closed and press the
hotkey: the macro saves and exits, optionally deletes the current character,
then creates a new one from `settings.ini`. It only runs while D2R is focused;
losing focus aborts the run.

Flow: `Esc` -> Save and Exit -> (offline tab -> delete) -> Create New -> class
-> version -> name -> (hardcore) -> Create -> (hardcore confirmation). It stops
after Create and does not wait for the loading screen.

## Requirements

- AutoHotkey v2.0+
- D2R in windowed or borderless mode at any 16:9 resolution
- Screen Space Calibration 0-4 (0 is the calibrated baseline)

Exclusive fullscreen can produce black captures; use windowed or borderless.

## Setup

Edit `settings.ini`, then run `d2r-reset-macro.ahk`. Press the configured macro
hotkey in game. Hotkey changes are picked up automatically; other changes apply
on the next run.

You can start in game, at the Esc menu, on character select, or on the
character-create screen. With `delete=1`, make sure the throwaway character is
selected first.

## settings.ini

```ini
[Settings]
name=          ; 1-16 letters; 1 letter is doubled; empty = class name
hero=5         ; class name or 1-8
version=reign  ; reign | expansion | classic
delete=1       ; 1 = delete the selected character first
hardcore=1     ; 1 = hardcore, 0 = softcore
screenSpace=0  ; D2R screen space calibration 0-4

[Hotkeys]
macro=F12
; load=F11

[LiveSplit]
; optional; blank to disable
reset=Numpad3
start=Numpad1

[Timeouts]
transition=5000   ; menu / character select / create screen
dialog=3000       ; dropdowns and confirmation dialogs
deleteHold=8000   ; max wait for the character list after the delete hold
poll=50           ; probe interval

[Debug]
log=0             ; 1 = write macro-log.txt
capture=0         ; 1 = save a BMP when a step fails
```

Timeouts are upper bounds, not delays. The macro continues as soon as the UI is
ready.

## Troubleshooting

With `[Debug] log=1`, failures are written to `macro-log.txt`; `capture=1` also
saves a BMP under `captures/`.

```
AutoHotkey64.exe d2r-reset-macro.ahk --probe
AutoHotkey64.exe d2r-reset-macro.ahk --probe --shot
```

`--probe` prints probe results and exits; `--shot` also saves a screenshot.
Probe mode replaces a running macro, so start it again afterwards.

## License

MIT.
