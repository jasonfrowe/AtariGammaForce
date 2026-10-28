#!/usr/bin/env python3
"""Summarize prof_mark timings from a play.sh log (peek 25f0 14 lines)."""
import sys
NAMES = ['frame', 'pl_draw', 'waves', 'think', 'en_upd+hits', 'damage', 'en_draw',
         'fx+shots', 'bullets', '-', 'hud', 'player', 'boss', 'wrecks']
rows = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 16 and p[1] == '25f0':
        rows.append([int(x, 16) * 64 for x in p[2:16]])
avg = [sum(r[i] for r in rows) / len(rows) for i in range(14)]
mx = [max(r[i] for r in rows) for i in range(14)]
for n, a, m in zip(NAMES, avg, mx):
    print(f"{n:14s} avg {a:6.0f}  max {m:6d}")
print(f"{'TOTAL':14s} avg {sum(avg):6.0f}  max {max(sum(r) for r in rows):6d}  (frame = 29,830 cycles)")
