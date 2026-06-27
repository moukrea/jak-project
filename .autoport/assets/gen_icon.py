#!/usr/bin/env python3
"""
Phase Gpkg-branding (autoport 2026-06-27) — placeholder launcher icon generator.

Generates a clean, non-copyrighted PLACEHOLDER launcher icon for the Jak 1
Android port: a "J&D" monogram (Jak & Daxter) in Precursor gold on a deep
blue->eco-teal gradient. It is intentionally typographic so it ships NO scraped
copyrighted character art. The owner replaces this with real cover art by
dropping a >=512x512 PNG (foreground art + a background color) and re-running.

Outputs (Android res/, density-correct):
  drawable/ic_launcher_background.xml           (vector gradient, authored separately)
  mipmap-<d>/ic_launcher_foreground.png         (adaptive foreground, transparent, safe-zone)
  mipmap-<d>/ic_launcher.png                     (legacy full square icon)
  mipmap-<d>/ic_launcher_round.png               (legacy full circular icon)
  .autoport/assets/icon-src-placeholder.png      (512x512 master, owner reference)

Run: python3 .autoport/assets/gen_icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = os.path.join(ROOT, "android/app/src/main/res")
FONT = "/usr/share/fonts/abattis-cantarell-fonts/Cantarell-ExtraBold.otf"
TEXT = "J&D"

# Jak & Daxter placeholder palette (colors are not copyrightable).
TOP    = (0x16, 0x32, 0x4F)   # deep sky blue
BOTTOM = (0x1E, 0x7A, 0x5A)   # eco teal-green
GOLD   = (0xF4, 0xC5, 0x42)   # Precursor gold
DARK   = (0x0B, 0x1A, 0x2A)   # outline / legibility stroke

# density -> (foreground 108dp px, legacy 48dp px)
DENSITIES = {
    "mdpi":    (108, 48),
    "hdpi":    (162, 72),
    "xhdpi":   (216, 96),
    "xxhdpi":  (324, 144),
    "xxxhdpi": (432, 192),
}
SS = 4  # supersample factor for crisp text


def gradient_bg(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(TOP[0] * (1 - t) + BOTTOM[0] * t)
        g = round(TOP[1] * (1 - t) + BOTTOM[1] * t)
        b = round(TOP[2] * (1 - t) + BOTTOM[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img.convert("RGBA")


def text_layer(size, width_frac, stroke_frac=0.055):
    """Transparent RGBA layer with TEXT centered, width ~= width_frac*size."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    target_w = width_frac * S
    best = None
    lo, hi = 4, S * 2
    while lo <= hi:
        mid = (lo + hi) // 2
        f = ImageFont.truetype(FONT, mid)
        sw = max(1, int(mid * stroke_frac))
        bbox = draw.textbbox((0, 0), TEXT, font=f, stroke_width=sw)
        w = bbox[2] - bbox[0]
        if w <= target_w:
            best = (mid, f, bbox, sw)
            lo = mid + 1
        else:
            hi = mid - 1
    fs, f, bbox, sw = best
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (S - w) // 2 - bbox[0]
    y = (S - h) // 2 - bbox[1]
    # soft drop shadow for depth
    draw.text((x, y + S // 48), TEXT, font=f, fill=(0, 0, 0, 90),
              stroke_width=sw, stroke_fill=(0, 0, 0, 90))
    draw.text((x, y), TEXT, font=f, fill=GOLD + (255,),
              stroke_width=sw, stroke_fill=DARK + (255,))
    return img.resize((size, size), Image.LANCZOS)


def circular(img):
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * SS - 1, size * SS - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.copy()
    out.putalpha(mask)
    return out


def write(img, rel):
    path = os.path.join(RES, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", rel, img.size)


for d, (fg_px, leg_px) in DENSITIES.items():
    # adaptive foreground: smaller (safe zone ~ central 72/108), transparent
    fg = text_layer(fg_px, width_frac=0.52)
    write(fg, f"mipmap-{d}/ic_launcher_foreground.png")
    # legacy full icons: gradient bg + monogram filling more of the tile
    bg = gradient_bg(leg_px)
    mono = text_layer(leg_px, width_frac=0.68)
    full = Image.alpha_composite(bg, mono)
    write(full, f"mipmap-{d}/ic_launcher.png")
    write(circular(full), f"mipmap-{d}/ic_launcher_round.png")

# 512x512 owner-reference master
master_bg = gradient_bg(512)
master = Image.alpha_composite(master_bg, text_layer(512, width_frac=0.66))
mpath = os.path.join(ROOT, ".autoport/assets/icon-src-placeholder.png")
master.save(mpath)
print("wrote", mpath, master.size)
print("DONE")
