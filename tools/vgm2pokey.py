#!/usr/bin/env python3
"""Convert MegaGammaForce's OPL2 VGM music to POKEY data for the 7800.

    vgm2pokey.py assets/mgf/music/Stage1.vgm [more.vgm ...] -o src/gen/music.asm

MegaGammaForce's tracks are OPL2, logged at 60 Hz, 7 channels:
lead, arp, bass, kick, snare, hat, pad. POKEY has four, so:

  voice 0  channels 1+2 joined, 16-bit at 1.79 MHz: the lead, or the arp
           whenever the lead is silent, or the pad when both are. 16 bits
           keeps every note in tune.
  voice 1  channel 3: the bass, 8-bit, on the 15 kHz clock for low notes
           and the 64 kHz clock for high ones (whichever tunes closer).
  voice 2  channel 4: drums. Kick, snare and hat are short "macros" of
           per-frame control and frequency values.
  (the TIA is left to the sound effects)

The OPL2's envelopes run inside the chip, so this simulates each note's
attack/decay/sustain/release from its patch to get a volume per frame.

Data format, per song (see src/asm/music.asm, which plays it):
  a stream per voice of
    $00-$7F  note n (voice 0/1: MIDI note; voice 2: drum number), then an
             envelope number byte
    $80-$BF  wait 1-64 frames
    $C0      rest (silence)
    $C1 a a n  play the n bytes at address a (an earlier phrase of the same
             voice, never itself containing a $C1), then carry on here
    $FF      end of song: start over
  envelopes: volume per frame (0-15), $FF = hold the last value. Shared by
  all voices of a song and deduplicated, so repeated notes cost 2 bytes.
"""

import argparse
import math
import struct
from pathlib import Path

FRAME_HZ = 60
OPL_CLOCK = 3579545
OPL_RATE = OPL_CLOCK / 72.0
POKEY_CLOCK = 1789772.5
CLK15 = POKEY_CLOCK / 114.0
CLK64 = POKEY_CLOCK / 28.0

# Operator slots (modulator, carrier) of each OPL2 channel.
OPS = [(0, 3), (1, 4), (2, 5), (8, 11), (9, 12), (10, 13), (16, 19), (17, 20), (18, 21)]
ROLE = ["lead", "arp", "bass", "kick", "snare", "hat", "pad"]

# Loudness of each voice at full OPL level, out of 15.
VMAX = {"lead": 11, "arp": 8, "bass": 12, "pad": 10}


def parse_vgm(path):
    d = Path(path).read_bytes()
    if d[:4] != b"Vgm ":
        raise SystemExit(f"{path}: not a VGM file")
    off = struct.unpack("<I", d[0x34:0x38])[0] + 0x34
    p, frame, ev = off, 0, []
    while p < len(d):
        c = d[p]
        if c == 0x5A:  # YM3812 write
            ev.append((frame, d[p + 1], d[p + 2]))
            p += 3
        elif c == 0x62:
            frame += 1
            p += 1
        elif c == 0x61:
            frame += round(struct.unpack("<H", d[p + 1:p + 3])[0] / 735)
            p += 3
        elif 0x70 <= c <= 0x7F:
            p += 1
        elif c == 0x66:
            break
        else:
            raise SystemExit(f"{path}: unsupported VGM command {c:#x}")
    return ev, frame


def env_times(ar, dr, rr):
    """Seconds for a full 96 dB attack / decay / release at these rates."""
    def t(rate, base):
        return 0.0 if rate >= 15 else (math.inf if rate == 0 else base / 2 ** (rate - 1))
    return t(ar, 2.826), t(dr, 39.28), t(rr, 39.28)


class Channel:
    """One OPL2 channel's state, stepped a frame at a time."""

    def __init__(self):
        self.key = False
        self.att = 96.0  # envelope attenuation, dB
        self.phase = "off"
        self.note = None

    def step(self, regs, ch):
        m, c = OPS[ch]
        ar, dr = regs[0x60 + c] >> 4, regs[0x60 + c] & 15
        sl, rr = regs[0x80 + c] >> 4, regs[0x80 + c] & 15
        sustain = bool(regs[0x20 + c] & 0x20)
        ta, td, tr = env_times(ar, dr, rr)
        dt = 1.0 / FRAME_HZ
        slv = 93.0 if sl == 15 else sl * 3.0
        if self.phase == "attack":
            self.att = 0.0 if ta == 0 else max(0.0, self.att - 96 * dt / ta)
            if self.att <= 0.0:
                self.phase = "decay"
        elif self.phase == "decay":
            if td == 0:
                self.att = slv
            elif td != math.inf:
                self.att = min(slv, self.att + 96 * dt / td)
            if self.att >= slv:
                self.phase = "sustain" if sustain else "release"
        elif self.phase == "release":
            if tr == 0:
                self.att = 96.0
            elif tr != math.inf:
                self.att = min(96.0, self.att + 96 * dt / tr)
        tl = (regs[0x40 + c] & 63) * 0.75
        return min(96.0, self.att + tl)


def simulate(ev, frames):
    """Per frame, per channel: (MIDI note or None, attenuation dB, keyed-on-this-frame)."""
    regs = [0] * 256
    chans = [Channel() for _ in range(9)]
    out = [[None] * 9 for _ in range(frames + 1)]
    i = 0
    for f in range(frames + 1):
        triggered = set()
        while i < len(ev) and ev[i][0] == f:
            _, r, v = ev[i]
            old = regs[r]
            regs[r] = v
            if 0xB0 <= r <= 0xB8:
                ch = r - 0xB0
                if v & 0x20 and not old & 0x20:
                    fnum = regs[0xA0 + ch] | ((v & 3) << 8)
                    blk = (v >> 2) & 7
                    hz = fnum * OPL_RATE / 2 ** (20 - blk)
                    chans[ch].note = round(69 + 12 * math.log2(hz / 440)) if hz > 0 else None
                    chans[ch].phase = "attack"
                    triggered.add(ch)
                elif old & 0x20 and not v & 0x20:
                    chans[ch].phase = "release"
            i += 1
        for ch in range(9):
            att = chans[ch].step(regs, ch)
            out[f][ch] = (chans[ch].note, att, ch in triggered)
    return out


def vol(att, vmax):
    return max(0, min(15, round(vmax * 10 ** (-att / 20))))


# ---------------------------------------------------------------------------
# Voices.

def voice_lead(sim):
    """Per frame (note, volume, retrigger) for voice 0: lead, else arp."""
    out = []
    for fr in sim:
        lead, arp = fr[0], fr[1]
        lv = vol(lead[1], VMAX["lead"]) if lead[0] is not None else 0
        if lv > 0:
            out.append((lead[0], lv, lead[2], "lead"))
        else:
            av = vol(arp[1], VMAX["arp"]) if arp[0] is not None else 0
            if av > 0:
                out.append((arp[0], av, arp[2], "arp"))
            else:
                # The pad fills the gaps (intros, breaks): without it some
                # tracks open with seconds of silence.
                pad = fr[6]
                pv = vol(pad[1], VMAX["pad"]) if pad[0] is not None else 0
                out.append((pad[0] if pv else None, pv, pad[2], "pad"))
    return out


def voice_bass(sim):
    out = []
    for fr in sim:
        b = fr[2]
        v = vol(b[1], VMAX["bass"]) if b[0] is not None else 0
        out.append((b[0] if v else None, v, b[2], "bass"))
    return out


DRUMS = {
    # name: list of (AUDC, AUDF) per frame. Played on the 15 kHz clock
    # (or 64 kHz when the bass is high; they still read as drums).
    "kick": [(0xAC, 40), (0xAA, 70), (0xA8, 110), (0xA6, 150), (0xA4, 190), (0xA2, 230)],
    "snare": [(0x8C, 3), (0x8A, 4), (0x88, 5), (0x86, 5), (0x84, 6), (0x83, 6), (0x82, 7), (0x81, 7)],
    "hat": [(0x86, 0), (0x83, 0), (0x81, 0)],
}
DRUM_IDS = {"kick": 0, "snare": 1, "hat": 2}


def voice_drums(sim):
    """Drum hits per frame: drum name or None. Snare beats kick beats hat."""
    out = []
    for fr in sim:
        hit = None
        for name, ch in (("snare", 4), ("kick", 3), ("hat", 5)):
            if fr[ch][2] and vol(fr[ch][1], 15) > 2:
                hit = name
                break
        out.append(hit)
    return out


# ---------------------------------------------------------------------------
# Encoding.

class Song:
    def __init__(self, name):
        self.name = name
        self.envs = {}  # tuple of volumes -> id
        self.streams = []

    def env_id(self, seq):
        seq = list(seq)
        while len(seq) > 1 and seq[-1] == seq[-2]:
            seq.pop()  # the player holds the last value
        key = tuple(seq)
        if key not in self.envs:
            self.envs[key] = len(self.envs)
        return self.envs[key]


def waits(n):
    out = []
    while n > 0:
        w = min(64, n)
        out.append(0x7F + w)
        n -= w
    return out


def encode_tonal(song, frames):
    """Segments of constant note; a new segment on every retrigger."""
    out, i, n = [], 0, len(frames)
    while i < n:
        note, v, _trig, src = frames[i]
        j = i + 1
        while j < n and frames[j][0] == note and not frames[j][2] and frames[j][3] == src:
            j += 1
        if note is None or all(frames[k][1] == 0 for k in range(i, j)):
            out.append(0xC0)
        else:
            out += [note & 0x7F, song.env_id(frames[k][1] for k in range(i, j))]
        out += waits(j - i)
        i = j
    return out


def encode_drums(hits):
    out, i, n = [], 0, len(hits)
    pending = None
    gap = 0
    for i in range(n):
        if hits[i] is not None:
            if pending is not None or gap:
                out += waits(gap) if pending is None else []
            out += [DRUM_IDS[hits[i]], 0]
            # count frames until the next hit
            j = i + 1
            while j < n and hits[j] is None:
                j += 1
            out += waits(j - i)
            pending = True
            gap = 0
        elif pending is None:
            gap += 1
    if pending is None:
        out += [0xC0] + waits(gap)
    return out


def boundaries(st):
    """Positions where commands start (a note takes 2 bytes)."""
    b, i = set(), 0
    while i < len(st):
        b.add(i)
        i += 2 if st[i] < 0x80 else 1
    b.add(len(st))
    return b


def compress(st, min_len=6):
    """Replace repeated phrases with $C1 calls to their first occurrence.

    Returns a list of tokens: ints (literal bytes) and ("call", out_offset, n).
    A phrase is only ever copied from literal bytes, so calls never nest."""
    bset = boundaries(st)
    out = []
    lits = []  # (orig_start, orig_end, out_start) of literal runs
    pos = 0
    while pos < len(st):
        best_n, best_out = 0, 0
        for ls, le, os_ in lits:
            for s0 in range(ls, le):
                if s0 not in bset:
                    continue
                n = 0
                while pos + n < len(st) and s0 + n < le and st[s0 + n] == st[pos + n] and n < 255:
                    n += 1
                while n > 0 and (pos + n) not in bset:
                    n -= 1
                if n > best_n:
                    best_n, best_out = n, os_ + (s0 - ls)
        if best_n >= min_len:
            out.append(("call", best_out, best_n))
            pos += best_n
        else:
            n = 2 if st[pos] < 0x80 else 1
            if lits and lits[-1][1] == pos:
                ls, le, os_ = lits[-1]
                lits[-1] = (ls, pos + n, os_)
            else:
                lits.append((pos, pos + n, len_tokens(out)))
            out += st[pos:pos + n]
            pos += n
    return out


def len_tokens(tokens):
    return sum(4 if isinstance(t, tuple) else 1 for t in tokens)


def convert(path):
    ev, frames = parse_vgm(path)
    sim = simulate(ev, frames)
    song = Song(Path(path).stem)
    song.streams = [encode_tonal(song, voice_lead(sim)), encode_tonal(song, voice_bass(sim)),
                    encode_drums(voice_drums(sim))]
    return song, frames


def period_tables():
    """Voice 0: 16-bit periods. Voice 1: 8-bit period and clock per note."""
    lo16, hi16, p8, c8 = [], [], [], []
    for n in range(128):
        f = 440 * 2 ** ((n - 69) / 12)
        p = max(0, min(65535, round(POKEY_CLOCK / (2 * f) - 7)))
        lo16.append(p & 255)
        hi16.append(p >> 8)
        best = None
        for clk, flag in ((CLK15, 1), (CLK64, 0)):
            q = round(clk / (2 * f) - 1)
            if 0 <= q <= 255:
                err = abs(clk / (2 * (q + 1)) - f) / f
                if best is None or err < best[0]:
                    best = (err, q, flag)
        if best is None:
            best = (0, 255, 1) if f < 100 else (0, 0, 0)
        p8.append(best[1])
        c8.append(best[2])
    return lo16, hi16, p8, c8


def asm_bytes(label, data, per=16):
    lines = [label]
    for i in range(0, len(data), per):
        lines.append("  .byte " + ",".join(f"${b:02X}" for b in data[i:i + per]))
    if not data:
        lines.append("  ; (empty)")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("vgm", nargs="+")
    ap.add_argument("-o", "--out", required=True, help="songs for the stage bank")
    ap.add_argument("--fixed", help="file for the fixed bank: shared tables, the song table, "
                    "and the songs named by --fixed-songs")
    ap.add_argument("--fixed-songs", default="", help="comma separated song names (file stems)")
    args = ap.parse_args()
    fixed_songs = {n.strip().lower() for n in args.fixed_songs.split(",") if n.strip()}

    lines = ["; Generated by tools/vgm2pokey.py. Do not edit.", ""]
    banked = ["; Generated by tools/vgm2pokey.py. Do not edit.", "; Songs that live in a stage's bank.", ""]
    lo16, hi16, p8, c8 = period_tables()
    lines += asm_bytes("mus_p16lo", lo16) + asm_bytes("mus_p16hi", hi16)
    lines += asm_bytes("mus_p8", p8) + asm_bytes("mus_clk15", c8)
    lines.append("")
    lines.append("; Drum macros: AUDC, AUDF pairs per frame, AUDC 0 ends.")
    for name in DRUM_IDS:
        data = [b for pair in DRUMS[name] for b in pair] + [0]
        lines += asm_bytes(f"mus_drum_{name}", data)
    lines.append("mus_drumlo .byte " + ",".join(f"<mus_drum_{n}" for n in DRUM_IDS))
    lines.append("mus_drumhi .byte " + ",".join(f">mus_drum_{n}" for n in DRUM_IDS))
    lines.append("")

    total = 0
    songs = []
    for path in args.vgm:
        song, frames = convert(path)
        nm = song.name.lower()
        songs.append(nm)
        envs = sorted(song.envs.items(), key=lambda kv: kv[1])
        if len(envs) > 256:
            raise SystemExit(f"{path}: {len(envs)} envelopes, more than a byte can number")
        out_lines = lines if (nm in fixed_songs or not args.fixed) else banked
        packed = [compress(st) for st in song.streams]
        size = sum(len_tokens(p) + 1 for p in packed) + sum(len(e) + 1 for e, _ in envs) + 2 * len(envs)
        total += size
        out_lines.append(f"; {song.name}: {frames} frames ({frames / 60:.0f} s), {len(envs)} envelopes, "
                     f"{size} bytes")
        for v, p in enumerate(packed):
            label = f"mus_{nm}_v{v}"
            out_lines.append(label)
            row = []
            for t in p + [0xFF]:
                if isinstance(t, tuple):
                    if row:
                        out_lines.append("  .byte " + ",".join(f"${b:02X}" for b in row))
                        row = []
                    _, off, n = t
                    out_lines.append(f"  .byte $C1,<({label}+{off}),>({label}+{off}),{n}")
                else:
                    row.append(t)
                    if len(row) == 16:
                        out_lines.append("  .byte " + ",".join(f"${b:02X}" for b in row))
                        row = []
            if row:
                out_lines.append("  .byte " + ",".join(f"${b:02X}" for b in row))
        for e, k in envs:
            out_lines += asm_bytes(f"mus_{nm}_e{k}", list(e) + [0xFF], per=32)
        # dasm allows 32 operators a line, so 8 addresses per .byte.
        for part, op in (("lo", "<"), ("hi", ">")):
            out_lines.append(f"mus_{nm}_env{part}")
            for i in range(0, len(envs), 8):
                out_lines.append("  .byte " + ",".join(f"{op}mus_{nm}_e{k}" for _, k in envs[i:i + 8]))
        out_lines.append("")
        print(f"{song.name}: {frames / 60:.0f} s, streams {[len(s) for s in song.streams]} -> "
              f"{[len_tokens(p) for p in packed]}, "
              f"{len(envs)} envelopes, {size} bytes")

    lines.append("; Song table: voice 0-2 stream addresses, envelope tables.")
    for field, fmt in (("v0", "mus_{}_v0"), ("v1", "mus_{}_v1"), ("v2", "mus_{}_v2"),
                       ("el", "mus_{}_envlo"), ("eh", "mus_{}_envhi")):
        for part, op in (("lo", "<"), ("hi", ">")):
            lines.append(f"mus_song_{field}{part}")
            for i in range(0, len(songs), 8):
                lines.append("  .byte " + ",".join(op + fmt.format(n) for n in songs[i:i + 8]))
    for i, n in enumerate(songs):
        lines.append(f"SONG_{n.upper()} = {i}")
    if args.fixed:
        Path(args.fixed).write_text("\n".join(lines) + "\n")
        Path(args.out).write_text("\n".join(banked) + "\n")
    else:
        Path(args.out).write_text("\n".join(lines) + "\n")
    print(f"total {total} bytes -> {args.out}")


if __name__ == "__main__":
    main()
