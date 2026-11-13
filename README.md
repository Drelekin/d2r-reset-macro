# d2r-reset-macro

Automates D2R character resets. Start in game and press the hotkey: the macro
opens the game menu, saves and exits, optionally deletes the current character,
then creates a new one from `settings.ini`. It only runs while D2R is focused;
losing focus aborts the run.

Flow: HUD Game Menu button -> Save and Exit -> (offline tab -> delete) -> Create
New -> class -> version -> name -> (hardcore) -> Create -> (hardcore
confirmation). It stops on the final click and does not wait for the loading
screen. The menu button also closes an open chat box or panel, so the run does
not need to start from a clean screen.

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
version=reign  ; reign (1) | expansion (2) | classic (3)
delete=1       ; keep (0) | delete first (1)
hardcore=1     ; softcore (0) | hardcore (1)
screenSpace=0  ; D2R screen space calibration 0-4

[Hotkeys]
macro=F12

[LiveSplit]
; optional; blank to disable
reset=Numpad3
start=Numpad1
```

## Troubleshooting

```
AutoHotkey64.exe d2r-reset-macro.ahk --probe
AutoHotkey64.exe d2r-reset-macro.ahk --probe --shot
```

`--probe` prints probe results and exits; `--shot` also saves a screenshot.
Probe mode replaces a running macro, so start it again afterwards. Use `--probe`
after changing `screenSpace` or a resolution to confirm every screen still
probes as expected.

`--trace` (add to the normal run) records how long every wait took and writes
`captures\<stamp>-trace.txt` when the run ends. Each line also shows when the
probe matched (`first=`) and how much of the wait was the fade settle (`held=`),
so a slow step can be told apart from a slow animation.

If the delete step fails, the macro saves a screenshot of the delete prompt
(`captures\<stamp>-delete-dialog.bmp` or `<stamp>-delete-stuck.bmp`), and the
error box prints the last pixel state of the failed probe.

## Notes

- A probe reads only the regions it needs, all in one capture, so a poll costs
  about one display frame.
- Controls that fade in must hold for `FADE_SAMPLES` frames and then keep the
  same signature for `FADE_SETTLE_MS` before they are clicked; a click started
  mid-animation can be swallowed.
- Probe thresholds must key off areas (a fill, a frame), never thin strokes:
  glyph fractions change with `SAMPLE_CAP` and the resolution.
- The hold-to-delete press (`DELETE_HOLD_MS`) is a game requirement and is the
  largest single cost of a run.

## License

MIT.
