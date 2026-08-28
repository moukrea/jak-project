#!/usr/bin/env python3
"""Genere un atlas de glyphes Urbanist + sa table UV pour la police de jak1.

Sources : Urbanist-600.ttf (latin) + urbanist-latin-ext-600-normal.woff2 (latin etendu).
Le jeu de caracteres est DERIVE des banques de texte du jeu, jamais liste a la main.
"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

CHARSET = open('charset_latin.txt', encoding='utf-8').read()
BASE, EXT = 'Urbanist-600.ttf', 'urbanist-latin-ext-600-normal.woff2'
PAD = 2

def load(px):
    return ImageFont.truetype(BASE, px), ImageFont.truetype(EXT, px)

def pick(ch, fb, fe):
    """Rend le glyphe avec la police qui le possede reellement."""
    probe = Image.new('L', (px_probe, px_probe), 0)
    ImageDraw.Draw(probe).text((4, 4), '', font=fb, fill=255)
    tofu = probe.tobytes()
    im = Image.new('L', (px_probe, px_probe), 0)
    ImageDraw.Draw(im).text((4, 4), ch, font=fb, fill=255)
    return fe if im.tobytes() == tofu and ch != ' ' else fb

def build(px, out_png, out_json):
    global px_probe
    px_probe = px * 2 + 16
    fb, fe = load(px)
    glyphs = []
    for ch in CHARSET:
        f = pick(ch, fb, fe)
        l, t, r, b = f.getbbox(ch)
        adv = f.getlength(ch)
        glyphs.append({'ch': ch, 'w': max(1, r - l), 'h': max(1, b - t),
                       'bx': l, 'by': t, 'adv': adv, 'font': f})
    cols = math.ceil(math.sqrt(len(glyphs)))
    cw = max(g['w'] for g in glyphs) + PAD * 2
    chh = max(g['h'] for g in glyphs) + PAD * 2
    rows = math.ceil(len(glyphs) / cols)
    W = 1 << (cols * cw - 1).bit_length()
    H = 1 << (rows * chh - 1).bit_length()
    atlas = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(atlas)
    table = []
    for i, g in enumerate(glyphs):
        cx, cy = (i % cols) * cw, (i // cols) * chh
        d.text((cx + PAD - g['bx'], cy + PAD - g['by']), g['ch'], font=g['font'], fill=255)
        table.append({'char': g['ch'], 'cp': ord(g['ch']),
                      'u0': (cx + PAD) / W, 'v0': (cy + PAD) / H,
                      'u1': (cx + PAD + g['w']) / W, 'v1': (cy + PAD + g['h']) / H,
                      'w': g['w'], 'h': g['h'], 'adv': round(g['adv'], 3),
                      'bx': g['bx'], 'by': g['by']})
    atlas.save(out_png)
    json.dump({'size_px': px, 'atlas': [W, H], 'count': len(table),
               'glyphs': table}, open(out_json, 'w'), ensure_ascii=False, indent=1)
    # quantification 4 bits : ce que le pipeline d'origine sait porter
    q = atlas.point(lambda v: (v // 17) * 17)
    q.save(out_png.replace('.png', '-4bit.png'))
    print("  %2dpx -> atlas %dx%d, %d glyphes, cellule %dx%d" % (px, W, H, len(table), cw, chh))
    return W, H, len(table)

for px in (12, 24, 48):
    build(px, 'urbanist-%d.png' % px, 'urbanist-%d.json' % px)
