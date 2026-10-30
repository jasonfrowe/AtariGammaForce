#!/usr/bin/env python3
"""Summarize the IDLELOG build's per-frame timing (catch-up, draw, wait).

Build with GF_DEFINES="... IDLELOG" and run a play.sh script that peeks
every frame: "<f> peek 22c3" and "<f> peek 25f0 6". Then:

    tools/idlelog.py <play.txt> [from_frame to_frame]

Times are in 1024-cycle ticks (a frame is 29.2), per displayed frame:
catch-up steps after the vblank, the draw step, catch-up steps run early
(before the frame showed) and the wait for vblank."""
import sys

rows, cur, last = [], None, None
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) < 3:
        continue
    if p[1] == '22c3':
        cur = (int(p[0]), int(p[2], 16))
    elif p[1] == '25f0' and cur and cur[1] != last:
        last = cur[1]
        v = [int(x, 16) for x in p[2:]] + [0, 0]
        rows.append((cur[0],) + tuple(v[:6]))
lo, hi = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (0, 1 << 60)
rs = [r for r in rows if lo <= r[0] < hi]
n, fr = len(rs), rs[-1][0] - rs[0][0]
avg = lambda i: sum(r[i] for r in rs) / n
print(f"{60 * n / fr:.1f} fps ({n} drawn in {fr} frames); per drawn frame, in ticks:")
print(f"  catch-up after vblank {avg(1):5.1f} ({avg(4):.2f} steps)")
print(f"  draw step             {avg(2):5.1f}")
print(f"  catch-up early        {avg(5):5.1f} ({avg(6):.2f} steps)")
print(f"  wait for vblank       {avg(3):5.1f}")
