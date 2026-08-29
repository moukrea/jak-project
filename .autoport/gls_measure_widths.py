#!/usr/bin/env python3
"""Gloading-screen — mesure, DANS L'IMAGE PRODUITE, la largeur de l'encre du texte et celle de la
ligne de glyphes precurseurs. Owner 2026-08-29 : elles doivent etre egales.

NATURE : deux longueurs, en PIXELS de l'image livree.
REPERE : l'image rendue elle-meme -- pas la toile 512, pas le modele de mise en page. C'est ce qui
  rend la mesure INDEPENDANTE du calcul qu'elle verifie ; la ligne `LOADSCREEN-WIDTH` du moteur,
  elle, publie deux nombres issus du meme calcul et ne pourrait pas se contredire.
CE QU'ELLE LIT QUAND LE DEFAUT EST ABSENT : `ecart` a 0 px. Avant le correctif du 2026-08-29 la
  ligne precurseur etait 30,6 % plus large que le texte.

Les deux bandes sont isolees sans rien supposer de leur position : on ne garde que la MOITIE
DROITE de l'image (la silhouette occupe la gauche), on projette l'encre sur les lignes, et on
coupe aux lignes vides. La bande du HAUT est le texte, celle du BAS les glyphes.
"""

import argparse
import glob
import os

import numpy as np
from PIL import Image

INK = 40  # luminance au-dessus de laquelle un pixel est de l'encre (le fond est noir plein)


def rightmost_cluster(ink_row_any, w, gap=70):
    """Bornes x du groupe d'encre le PLUS A DROITE, deux plages separees de moins de `gap` pixels
    etant considerees comme un meme groupe (les espaces entre lettres et entre glyphes).
    Sert a isoler la ligne de texte de la SILHOUETTE, qui la chevauche horizontalement ET
    verticalement : la restreindre a la moitie droite de l'image la tronquait, et rendait alors
    un bord gauche a exactement 960 sur trois langues sur cinq — un nombre rond, donc un tell."""
    xs = np.where(ink_row_any)[0]
    if len(xs) == 0:
        return None
    end = int(xs[-1])
    start = end
    i = len(xs) - 1
    while i > 0 and xs[i] - xs[i - 1] <= gap:
        i -= 1
        start = int(xs[i])
    return start, end + 1


def bands(img):
    a = np.asarray(img.convert("L")).astype(np.int16)
    h, w = a.shape
    right = a
    ink = right > INK
    rows = ink.any(axis=1)
    out, inb, y0 = [], False, 0
    for y, v in enumerate(rows):
        if v and not inb:
            y0, inb = y, True
        elif not v and inb:
            out.append((y0, y))
            inb = False
    if inb:
        out.append((y0, h))
    res = []
    for (b0, b1) in out:
        if b1 - b0 < 4:
            continue
        c = rightmost_cluster(ink[b0:b1].any(axis=0), w)
        if c is None:
            continue
        res.append((b0, b1, c[0], c[1]))
    return res, w, h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", nargs="+")
    ap.add_argument("--out", default=".autoport/reports/Gloading-screen/widths.txt")
    a = ap.parse_args()

    lines = ["# Gloading-screen — largeurs MESUREES DANS L'IMAGE (pixels), "
             ".autoport/gls_measure_widths.py"]
    worst = 0.0
    for path in sorted(a.shots):
        if not os.path.exists(path):
            lines.append("MANQUANT %s" % path)
            continue
        lang = os.path.basename(path).replace("ls-", "").replace(".png", "")
        bs, w, h = bands(Image.open(path))
        if len(bs) < 2:
            lines.append("LANGUE=%-9s ECHEC bandes=%d (image %dx%d) — rien a mesurer" % (lang, len(bs), w, h))
            continue
        # les bandes sont triees par y ; la ligne de texte et la ligne de glyphes sont les DEUX
        # DERNIERES (la silhouette occupe les bandes au-dessus).
        txt, gly = bs[-2], bs[-1]
        tw = txt[3] - txt[2]
        gw = gly[3] - gly[2]
        d = gw - tw
        worst = max(worst, abs(d))
        lines.append(
            "LANGUE=%-9s image=%dx%d  largeur texte=%d px [x %d..%d]  "
            "largeur precurseur=%d px [x %d..%d]  ecart=%+d px  bandes-y texte=%d..%d glyphes=%d..%d"
            % (lang, w, h, tw, txt[2], txt[3], gw, gly[2], gly[3], d, txt[0], txt[1], gly[0], gly[1]))
    lines.append("ECART_MAX_PX=%d" % int(worst))
    txt = "\n".join(lines) + "\n"
    print(txt, end="")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out, "w").write(txt)


if __name__ == "__main__":
    main()
