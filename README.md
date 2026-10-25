# Atari Gamma Force

A vertical shoot-'em-up for the Atari 7800: a demake of
[MegaGammaForce](https://github.com/jasonfrowe/MegaGammaForce) for the
Picocomputer 6502. Two buttons, two weapons, the Vulcan and the Radiant
Sword; a color chain; weapons that level up; bosses taken apart piece by
piece. Written in [7800basic](https://github.com/7800-devtools/7800basic)
with an assembly display engine for smooth vertical scrolling.

**Status:** early. The scroll engine works (pixel-exact against the map in
every fine scroll position); the ship flies and shoots over stage 1. See
[docs/DESIGN.md](docs/DESIGN.md) for the plan and
[docs/ENGINE.md](docs/ENGINE.md) for how the scrolling works.

## Controls (planned)

| | |
|---|---|
| Joystick | Move |
| Button 1 (left) | Vulcan: hold to fire |
| Button 2 (right) | Radiant Sword: cuts, and absorbs pink bullets |
| Both, gauge full | Hyper Sword |
| Pause | Pause |

## Building

Needs [wasmtime](https://wasmtime.dev) (7800basic is vendored in
`tools/7800basic` as WebAssembly):

```sh
tools/build.sh                 # -> build/gammaforce.a78
```

or with CMake: `cmake --preset default && cmake --build --preset default`.

Run it in [A7800](https://github.com/7800-devtools/a7800):

```sh
a7800 a7800 -cart build/gammaforce.a78
```

## Layout

| Path | |
|---|---|
| `src/gammaforce.bas` | The game (7800basic) |
| `src/asm/engine.asm` | Scroll engine and sprite plotter |
| `src/gfx/`, `src/gen/` | Generated graphics and data (committed; made by `tools/gen_assets.py`) |
| `assets/mgf/` | Source art snapshotted from MegaGammaForce (`tools/import_mgf.py`) |
| `tools/7800basic/` | 7800basic v0.41, with one small patch (see ENGINE.md) |
| `tools/test_scroll.sh` | Headless engine regression test |
| `docs/reference/` | Local copy of the 7800basic guide |

Regenerating the art needs Python with Pillow and numpy:

```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python tools/gen_assets.py
```

## License

GPL-3.0, like MegaGammaForce and Astro Wing. 7800basic is under its own
license (`tools/7800basic/LICENSE.txt`).
