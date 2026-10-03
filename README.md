# Samirius Arena (Sega Game Gear)

Single-screen top-down arena shooter for Game Gear. Move and aim with the D-pad, use either action button to fire, and clear the arena by defeating all three opponents.

## Build

```
python tools/build.py
```

Output: `dist/samirius_arena.gg`

Needs Python 3 only (Z80 assembler is included).

## Run

Load `dist/samirius_arena.gg` in Emulicious, Kega Fusion, Mega EverDrive, or a flash cart. The header is export Game Gear (`TMR SEGA`, 32 KB).

## Controls

- D-Pad — move and set firing direction
- Button 1 or Button 2 — fire
- Start — begin / retry
