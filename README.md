# d2r-reset-macro

Press a hotkey in Diablo II: Resurrected and the macro resets your character:
it saves and exits, deletes the old character if you want, and creates a new
one using `settings.ini`. It stops if D2R loses focus.

It also watches the area name in the top-right corner and can send LiveSplit
splits as you reach each town.

## Requirements

- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- D2R in Windowed or Fullscreen, at a 16:9 resolution
- `settings.ini` set to match your game options (see below)

## Setup

1. Edit `settings.ini`.
2. Run `d2r-reset-macro.ahk`.
3. Press the macro hotkey in game (default `F12`).

You can start anywhere: in game, at the Esc menu, on character select, or on the
character-create screen. If `delete=1`, the character to delete must be selected
first.

Changes to the hotkey, `screenSpace`, `showClock`, `largeFontMode` and
`autoSplit` apply right away. Other changes apply on the next run.

## settings.ini

```ini
[Settings]
name=          ; character name; blank uses the class name
hero=5         ; class name or 1-8
version=reign  ; reign (1) | expansion (2) | classic (3)
delete=1       ; keep (0) | delete old character (1)
hardcore=1     ; softcore (0) | hardcore (1)
screenSpace=0  ; D2R > Options > Video > Screen Space Calibration
showClock=0    ; D2R > Options > Gameplay > Show Clock
largeFontMode=0 ; D2R > Options > Gameplay > Large Font Mode
autoSplit=0    ; send LiveSplit town splits (1) | disabled (0)

[Hotkeys]
macro=F12

[LiveSplit]
; optional; leave blank to disable
reset=Numpad3
start=Numpad1   ; also used for town splits
```

Classes: Amazon (1), Assassin (2), Necromancer (3), Barbarian (4), Paladin (5),
Sorceress (6), Warlock (7), Druid (8).

`screenSpace`, `showClock` and `largeFontMode` must match the game exactly. If
they don't, the macro can't find what it's looking for.

## Town splits

With `autoSplit=1`, LiveSplit gets a split when you reach each town:

- **Normal:** Lut Gholein, Kurast Docks, Pandemonium Fortress, Harrogath
- **Nightmare / Hell:** Rogue Encampment, Lut Gholein, Kurast Docks,
  Pandemonium Fortress, Harrogath

Splits only work in order. If you skip a town or are tabbed out when you reach
it, the remaining splits for that run are skipped. Each new run starts over at
the first town. With `version=classic`, Harrogath is dropped in Normal and
Nightmare, but kept in Hell.

LiveSplit reset is sent at the start of a run, and the start hotkey after the
character is created, even with `autoSplit=0`.

## Troubleshooting

Check what the macro sees after changing a video/gameplay setting:

```
AutoHotkey64.exe d2r-reset-macro.ahk --probe
```

Add `--shot` to also save a screenshot. Add `--trace` to a normal run to log
every step to `captures\`. Failed runs also save screenshots there.

If a run fails before changing anything in game, the macro tries the other
`screenSpace` values and remembers the first one that works.

## License

MIT.
