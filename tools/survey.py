#!/usr/bin/env python3
"""Summarize a tools/survey.sh run: display rate, MARIA's load and what is
on screen, by stretch of the map (8 rows = 128 lines) and then through the
boss fight (every 5 seconds).

    tools/survey.py build/survey/stage1/play.txt build/survey/stage1.dma"""
import sys
from collections import defaultdict

ET_PART = None  # (boss parts count as enemies here)

rows = defaultdict(dict)
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) < 3:
        continue
    f = int(p[0])
    if p[1] == 'dma':
        rows[f]['stolen'] = int(p[4])
        rows[f]['over'] = int(p[6])
        rows[f]['peak'] = int(p[8])
    else:
        rows[f][p[1]] = [int(x, 16) for x in p[2:]]

over_frames = defaultdict(int)  # emulator frame -> lines cut short
if len(sys.argv) > 2:
    for line in open(sys.argv[2]):
        if line.startswith('#'):
            continue
        h = line.split(':')[0].split()
        if int(h[3]):
            over_frames[int(h[0])] = int(h[3])

fs = sorted(f for f in rows if '2312' in rows[f] and '22c3' in rows[f])
groups = []  # (label, [windows])
cur, cur_key = None, None
boss_start = None
for a, b in zip(fs, fs[1:]):
    r = rows[a]
    spos = r['2231'][0] + 256 * r['2231'][1]
    bstate = r['2344'][0]
    if bstate == 0:
        key = ('map', spos // 128)
        label = f"lines {spos // 128 * 128:5d}+"
    else:
        if boss_start is None:
            boss_start = a
        key = ('boss', (a - boss_start) // 300)
        label = f"boss {(a - boss_start) // 60:4d}s+"
    steps = (rows[b]['2312'][0] - r['2312'][0]) & 255
    draws = (rows[b]['22c3'][0] - r['22c3'][0]) & 255
    nen = sum(1 for t in r['2600'] if t)
    nbul = sum(1 for t in r['2480'] if t)
    over = sum(n for g, n in over_frames.items() if a <= g < b)
    w = (b - a, steps, draws, nen, nbul, r.get('stolen', 0), r.get('peak', 0), over)
    if key != cur_key:
        cur = (label, [])
        groups.append(cur)
        cur_key = key
    cur[1].append(w)

print(f"{'where':14s} {'fps':>5s} {'speed':>5s} {'enem':>5s} {'bull':>5s} {'dma':>6s} {'peak':>5s} {'cut':>4s}")
tot = [0, 0, 0]
for label, ws in groups:
    fr = sum(w[0] for w in ws)
    fps = 60 * sum(w[2] for w in ws) / fr
    spd = 60 * sum(w[1] for w in ws) / fr
    tot[0] += fr; tot[1] += sum(w[2] for w in ws); tot[2] += sum(w[7] for w in ws)
    en = sum(w[3] for w in ws) / len(ws)
    bu = sum(w[4] for w in ws) / len(ws)
    dma = sum(w[5] for w in ws) / len(ws)
    peak = max(w[6] for w in ws)
    cut = sum(w[7] for w in ws)
    flag = ' <--' if fps < 40 or cut else ''
    print(f"{label:14s} {fps:5.1f} {spd:5.1f} {en:5.1f} {bu:5.1f} {dma:6.0f} {peak:5d} {cut:4d}{flag}")
print(f"{'all':14s} {60 * tot[1] / tot[0]:5.1f}{'':30s}{tot[2]:5d} lines cut short in all")
