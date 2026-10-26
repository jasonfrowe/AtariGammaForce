#!/usr/bin/env python3
"""Game speed and display rate from play.sh peeks every 10 frames: tick
($2312, one per game step) and, if peeked, pfdraws ($22C3, one per frame
drawn). The game speed should stay at 60 even when the display drops to
30 (late frames run a catch-up step; see engine.asm pf_drawscreen)."""
import sys


def series(addr):
    return [(int(l.split()[0]), int(l.split()[2], 16)) for l in open(sys.argv[1])
            if l.split()[1:2] == [addr]]


def rate(vals):
    deltas = [((v2 - v1) & 255, f2 - f1) for (f1, v1), (f2, v2) in zip(vals, vals[1:])]
    n = sum(d for d, _ in deltas)
    emu = sum(f for _, f in deltas)
    return n, emu, deltas


n, emu, deltas = rate(series('2312'))
slow = sum(1 for d, f in deltas if d < f)
print(f"game speed: {n} steps in {emu} frames, {60 * n / emu:.1f}/s; {slow}/{len(deltas)} windows slowed")
draws = series('22c3')
if draws:
    n, emu, deltas = rate(draws)
    full = sum(1 for d, f in deltas if d >= f)
    print(f"display: {60 * n / emu:.1f} fps; {full}/{len(deltas)} windows at a full 60")
