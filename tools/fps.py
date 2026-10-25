#!/usr/bin/env python3
"""Game frames per 60 emulated frames, from play.sh peeks of tick ($2312) every 10 frames."""
import sys
ticks = [(int(l.split()[0]), int(l.split()[2], 16)) for l in open(sys.argv[1]) if l.split()[1:2] == ['2312']]
deltas = [((t2 - t1) & 255, f2 - f1) for (f1, t1), (f2, t2) in zip(ticks, ticks[1:])]
game = sum(d for d, _ in deltas)
emu = sum(f for _, f in deltas)
slow = sum(1 for d, f in deltas if d < f)
print(f"{game} game frames in {emu} emulated: {60 * game / emu:.1f} fps; {slow}/{len(deltas)} windows lagged")
