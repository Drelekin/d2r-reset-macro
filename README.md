# d2r-reset-macro

Automates D2R character resets. Press the hotkey in game: the macro opens the
game menu, saves and exits, optionally deletes the character, then creates a
new one from `settings.ini`. It aborts if D2R loses focus.

Flow: Game Menu -> Save and Exit -> (delete) -> Create New -> class -> version
-> name -> (hardcore) -> Create -> (hardcore confirmation). It stops after the
final click and does not wait for the loading screen. The Game Menu button also
closes an open chat box or panel, so it doesn't matter what screen you start
from.

## Requirements

- AutoHotkey v2.0+
- D2R in Windowed or Fullscreen at any 16:9 resolution
- Screen Space Calibration 0-4 (0 is the calibrated baseline)

## Setup

Edit `settings.ini` and run `d2r-reset-macro.ahk`, then press the macro hotkey
in game. Hotkey changes apply immediately; other changes on the next run.

You can start in game, at the Esc menu, on character select, or on the
character-create screen. With `delete=1` the throwaway character must be
selected first.

If a run fails before changing anything in game, the macro retries the other
`screenSpace` values and saves the first that works. Save and Exit is never
repeated, failures after a delete or the Create click are reported directly,
and `settings.ini` is only written when a run completes.

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

`--probe` prints results and exits, `--shot` also saves a screenshot. Probe
replaces a running macro. Run it after changing `screenSpace` or resolution.

`--trace` on a normal run logs every wait to `captures\<stamp>-trace.txt`, with
`first=` (when the probe matched) and `held=` (fade settle) per step; a
calibration retry adds an `attempt screenSpace <n>` line.

Delete failures save `captures\<stamp>-delete-dialog.bmp` or
`<stamp>-delete-stuck.bmp`, and the error box prints the last pixel state. After
a calibration retry it also lists the `screenSpace` values that were tried.

## Notes

- A probe captures once and reads only its regions, so a poll costs about a frame.
- Fading controls must hold `FADE_SAMPLES` frames, then stay stable for
  `FADE_SETTLE_MS`; a click started mid-animation can be swallowed.
- Thresholds key off areas (a fill, a frame), never thin strokes, since glyph
  fractions shift with `SAMPLE_CAP` and resolution.
- `DELETE_HOLD_MS` is a game requirement and the largest cost of a run.

## License

MIT.
