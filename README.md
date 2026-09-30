# CGA-Demo
A graphical demo for CGA video cards in IBM 5150 machines. AI will be used.

Written in 8086/8088 assembly for [FASM](https://flatassembler.net), produces a
single `.COM` file (~3.5 KB) for MS-DOS.

## Parts

| # | Effect                          | Mode                          |
|---|---------------------------------|-------------------------------|
| 1 | Logo + raster (copper) bars     | 320x200, 4 colors, per-line background |
| 2 | Parallax starfield + scroller   | 320x200, 4 colors             |
| 3 | XOR line kaleidoscope           | 640x200, 2 colors             |
| 4 | Plasma                          | 40x25 text, 16 bg colors (blink off) |
| 5 | Credits                         | 80x25 text                    |

Controls: any key = next part, `ESC` = quit to DOS.

## Build

```
fasm demo.asm demo.com
```

## Run in DOSBox-X

A prebuilt `demo.com` is included. Recommended `dosbox-x.conf` settings:

```ini
[dosbox]
machine=cga

[cpu]
cputype=8086
core=normal
cycles=fixed 3000
```

The effects are paced by vertical retrace, so higher `cycles` values are fine.
Lower values (closer to a real 4.77 MHz 8088) also work; parts just run slower.

Notes:
- Part 1 changes the background color on every scanline, so it needs a real
  CGA (or `machine=cga`); with `machine=svga_*` it may look different.
- The scroller uses the BIOS 8x8 font at `F000:FA6E`, as on the IBM 5150.
