#!/usr/bin/env python3
"""Build the game's manual: docs/manual/manual.html -> PDFs.

    .venv/bin/python tools/make_manual.py            # images (but not the
                                                     # screenshots) and PDFs
    .venv/bin/python tools/make_manual.py --shots    # screenshots too (runs
                                                     # the emulator: minutes)

The manual is a pocket booklet in the style of the old Atari manuals, laid
out in docs/manual/manual.html (edit the text there) and printed by Chrome
at two sizes: 5 x 7 inches and 4 x 6.5 inches (docs/manual/*.pdf). Its 16
pages are a multiple of 4, for a folded, stapled booklet.

The images in docs/manual/img: screenshots from the emulator (tools/play.sh,
--shots), the sprites drawn from src/gfx at the 7800's pixel shape (a 160A
pixel is two lines wide), the cover art and the logo.
"""

import argparse
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MAN = ROOT / "docs" / "manual"
IMG = MAN / "img"
GFX = ROOT / "src" / "gfx"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

sys.path.insert(0, str(ROOT / "tools"))
import gen_assets  # noqa: E402  (palettes)

RGB = gen_assets.rgb_of
PAL = gen_assets.PAL_CODES                      # global palettes 0-7
CHAIN = {"red": PAL[4], "blue": PAL[5], "yellow": PAL[6]}
GOLD_LOGO = [0x12, 0x17, 0x3D]                  # the title's logo, gold

# ---------------------------------------------------------------------------
# Screenshots: (file, build defines, frame, script kind). Kinds: "title"
# (no game started), "play" (fire held, weaving), "sword" (the sword held
# from frame 1300, then both buttons for the Hyper Sword at 2400).
SHOTS = [
    ("title", "CHEAT", 200, "title"),
    ("stage1", "CHEAT", 1500, "play"),
    ("boss1", "CHEAT BOSSTEST", 1250, "play"),
    ("stage2", "CHEAT STAGE2TEST", 1800, "play"),
    ("boss2", "CHEAT BOSSTEST STAGE2TEST", 1450, "play"),
    ("stage3", "CHEAT STAGE3TEST", 1900, "play"),
    ("boss3", "CHEAT BOSSTEST STAGE3TEST", 1900, "play"),
    ("stage4", "CHEAT STAGE4TEST", 1300, "play"),
    ("boss4", "CHEAT BOSSTEST STAGE4TEST", 1900, "play"),
    ("results", "CHEAT BOSSTEST", (2752, 2760), "play"),   # (the bonus figure blinks)
    ("sword", "CHEAT BOSSTEST", 1900, "sword"),
    ("hyper", "CHEAT BOSSTEST", 2450, "sword"),
]


def script(kind, frames):
    lines = []
    if kind != "title":
        lines += ["300 press P1 Button 2", "310 release P1 Button 2"]
    if kind == "play":
        lines.append("320 press P1 Button 1")
        for f in range(330, 6000, 200):
            lines += [f"{f} press P1 Left", f"{f + 45} release P1 Left",
                      f"{f + 100} press P1 Right", f"{f + 145} release P1 Right"]
    if kind == "sword":
        lines += ["1300 press P1 Button 2", "2380 release P1 Button 2", "2400 press P1 Button 1",
                  "2401 press P1 Button 2", "2420 release P1 Button 1", "2420 release P1 Button 2"]
    lines += [f"{f} snap" for f in frames]
    lines.sort(key=lambda l: int(l.split()[0]))
    return "\n".join(lines) + "\n"


def shots():
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for name, defines, frame, kind in SHOTS:
            frames = frame if isinstance(frame, tuple) else (frame,)
            subprocess.run([str(ROOT / "tools" / "build.sh")], env={**os.environ, "GF_DEFINES": defines},
                           check=True, stdout=subprocess.DEVNULL)
            (tmp / f"{name}.txt").write_text(script(kind, frames))
            subprocess.run([str(ROOT / "tools" / "play.sh"), str(tmp / f"{name}.txt"), str(tmp / name)],
                           env={**os.environ, "ROM": str(ROOT / "build" / "gammaforce-test.a78")},
                           check=True, stdout=subprocess.DEVNULL)
            # of several frames, the one with the most drawn on it
            ims = [Image.open(p).convert("RGB") for p in sorted((tmp / name / "a7800").glob("*.png"))]
            best = max(ims, key=lambda im: sum(c for c, _ in sorted(im.getcolors(1 << 20))[:-1]))
            best.save(IMG / f"{name}.png")
            print("shot", name, file=sys.stderr)
    # the HUD, and the ship with its sword, cut from the sword shot
    sw = Image.open(IMG / "sword.png")
    sw.crop((0, 0, 320, 24)).save(IMG / "hud.png")


# ---------------------------------------------------------------------------
# Sprites, from the 160A sheets in src/gfx (colour 0 transparent).

def frame(name, w, k=0, strips=1, pal=None):
    """Frame k of a sprite w 160A pixels wide (its strips stacked), RGBA,
    one pixel per 160A pixel; pal: three 7800 colors for colors 1-3."""
    parts = []
    for s in range(strips):
        sheet = Image.open(GFX / (f"{name}{s}.png" if strips > 1 else f"{name}.png"))
        parts.append(sheet.crop((k * w, 0, (k + 1) * w, 16)))
    h = 16 * strips
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src_pal = parts[0].getpalette()
    for s, part in enumerate(parts):
        for y in range(16):
            for x in range(w):
                i = part.getpixel((x, y))
                if i == 0:
                    continue
                c = RGB(pal[i - 1]) if pal else tuple(src_pal[3 * i:3 * i + 3])
                out.putpixel((x, 16 * s + y), (*c, 255))
    bbox = out.getbbox()
    return out.crop(bbox) if bbox else out


def big(im, scale):
    """At the 7800's shape: each 160A pixel 2 wide, 1 tall, times scale."""
    return im.resize((im.width * 2 * scale, im.height * scale), Image.NEAREST)


SPRITES = [
    # file, sheet, width, frame, strips, palette (None: the sheet's own)
    ("ship", "ship", 16, 0, 2, None),
    ("dart", "dart", 8, 0, 1, CHAIN["red"]),
    ("saucer", "saucer", 8, 0, 1, CHAIN["blue"]),
    ("drone", "drone", 8, 0, 1, CHAIN["yellow"]),
    ("wasp", "wasp", 8, 0, 1, CHAIN["red"]),
    ("gunship", "gunship", 16, 0, 2, None),
    ("turret", "turret", 8, 0, 1, CHAIN["blue"]),
    ("tank", "tank", 8, 0, 1, CHAIN["yellow"]),
    ("tower", "tower", 16, 0, 2, None),
    ("gunboat", "gunboat", 16, 0, 2, CHAIN["red"]),
    ("train", "train", 16, 0, 2, CHAIN["blue"]),
    ("traincar", "train", 16, 1, 2, CHAIN["blue"]),
    ("pinkbullet", "pinkbullet", 4, 0, 1, PAL[7]),
    ("bluebullet", "bluebullet", 4, 0, 1, PAL[7]),
    ("needle", "needle", 4, 0, 1, PAL[7]),
    ("gem_red", "hudgem", 8, 0, 1, CHAIN["red"]),
    ("gem_blue", "hudgem", 8, 0, 1, CHAIN["blue"]),
    ("gem_yellow", "hudgem", 8, 0, 1, CHAIN["yellow"]),
]


def sprites():
    for name, sheet, w, k, strips, pal in SPRITES:
        big(frame(sheet, w, k, strips, pal), 8).save(IMG / f"sp_{name}.png")
    # each air enemy in the three chain colors, side by side
    for name, w in (("dart", 8), ("saucer", 8), ("drone", 8), ("wasp", 8)):
        ims = [frame(name, w, 0, 1, CHAIN[c]) for c in ("red", "blue", "yellow")]
        wd = sum(i.width for i in ims) + 4 * (len(ims) - 1)
        row = Image.new("RGBA", (wd, max(i.height for i in ims)), (0, 0, 0, 0))
        x = 0
        for i in ims:
            row.alpha_composite(i, (x, 0))
            x += i.width + 4
        big(row, 8).save(IMG / f"sp_{name}3.png")


def logo():
    """GAMMA over FORCE, in the title's gold, at 2:1."""
    g = frame("logo_gamma", 92, 0, 2, GOLD_LOGO)
    f = frame("logo_force", 92, 0, 2, GOLD_LOGO)
    out = Image.new("RGBA", (max(g.width, f.width), 34 + f.height), (0, 0, 0, 0))
    out.alpha_composite(g, ((out.width - g.width) // 2, 0))
    out.alpha_composite(f, ((out.width - f.width) // 2, 34))
    big(out, 6).save(IMG / "logo.png")


def cover():
    """The cover's art: the fighter climbing into a sky of the enemy, a
    pixel-art scene (one pixel per 160A pixel, then 2:1 and up)."""
    W, H = 160, 200
    rnd = random.Random(7)
    im = Image.new("RGBA", (W, H))
    for y in range(H):                     # night, deepening to blue
        t = y / H
        c = (int(4 + 14 * t), int(6 + 30 * t), int(24 + 80 * t), 255)
        for x in range(W):
            im.putpixel((x, y), c)
    for _ in range(90):                    # stars
        x, y = rnd.randrange(W), rnd.randrange(H - 40)
        v = rnd.choice((120, 170, 230))
        im.putpixel((x, y), (v, v, min(255, v + 25), 255))

    def put(name, w, x, y, k=0, strips=1, pal=None):
        s = frame(name, w, k, strips, pal)
        im.alpha_composite(s, (x - s.width // 2, y - s.height // 2))

    # the enemy, in formation
    for i, (x, y) in enumerate(((30, 38), (52, 30), (74, 24), (96, 24), (118, 30), (140, 38))):
        put("dart", 8, x, y, pal=CHAIN[("red", "blue", "yellow")[i % 3]])
    put("gunship", 16, 80, 66, strips=2)
    for x, y, c in ((34, 84, "blue"), (126, 84, "blue"), (56, 104, "yellow"), (104, 104, "yellow")):
        put("saucer", 8, x, y, pal=CHAIN[c])
    for x, y in ((20, 120), (140, 116)):
        put("wasp", 8, x, y, pal=CHAIN["red"])
    for x, y in ((64, 128), (70, 136), (92, 128), (86, 136), (78, 120), (98, 112)):
        put("pinkbullet", 4, x, y, pal=PAL[7])
    for x, y in ((44, 132), (118, 136)):
        put("bluebullet", 4, x, y, pal=PAL[7])
    # the fighter, its sword out, and its Vulcan
    for y in (140, 124, 108):
        put("vulcan", 4, 80, y, pal=PAL[3])
    put("sword", 24, 80, 160, k=1, strips=2, pal=PAL[7])
    put("ship", 16, 80, 176, strips=2)
    big(im, 4).convert("RGB").save(IMG / "cover.png")


# ---------------------------------------------------------------------------
SIZES = {
    # name: page width, height (inches), base font size, page padding
    "5x7": ("5in", "7in", "9pt", "0.38in 0.4in 0.42in"),
    "4x6.5": ("4in", "6.5in", "7.6pt", "0.3in 0.3in 0.36in"),
}


def pdfs():
    html = (MAN / "manual.html").read_text()
    for name, (w, h, fs, pad) in SIZES.items():
        sized = re.sub(r"/\*SIZE\*/.*?/\*END\*/",
                       f"/*SIZE*/ --page-w: {w}; --page-h: {h}; --base: {fs}; --pad: {pad}; /*END*/",
                       html, flags=re.S)
        sized = re.sub(r"@page \{[^}]*\}", f"@page {{ size: {w} {h}; margin: 0; }}", sized)
        tmp = MAN / f".manual-{name}.html"
        tmp.write_text(sized)
        out = MAN / f"Atari_Gamma_Force_Manual_{name}.pdf"
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        "--run-all-compositor-stages-before-draw", "--virtual-time-budget=4000",
                        f"--print-to-pdf={out}", tmp.as_uri()],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tmp.unlink()
        print(out.relative_to(ROOT))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", action="store_true", help="capture the screenshots (runs the emulator)")
    ap.add_argument("--no-pdf", action="store_true")
    args = ap.parse_args()
    IMG.mkdir(parents=True, exist_ok=True)
    if args.shots:
        shots()
    sprites()
    logo()
    cover()
    if not args.no_pdf:
        pdfs()


if __name__ == "__main__":
    main()
