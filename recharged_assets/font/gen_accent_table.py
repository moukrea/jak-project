#!/usr/bin/env python3
"""Fabrique les entrees de composition d'ACCENTS MINUSCULES pour jak1.

Pourquoi il en faut
-------------------
jak1 n'a AUCUN glyphe accentue precompose (sauf Ç Æ Œ ß). Une capitale accentuee est
composee a l'execution : `replace_info_jak1` remplace "É" par "E~Y~-22H~-5V'~Z", soit
« dessine E, sauvegarde la plume, recule de 22, descends de 5, dessine l'accent aigu,
restaure la plume ». Le corpus emploie 49 capitales accentuees et ZERO minuscule
accentuee (mesure : 11 994 entrees, seule `ö` apparait, 7 fois, et c'est une coquille).
Passer le jeu en casse mixte demande donc de creer les 49 entrees minuscules.

L'unite des decalages, MESUREE et non supposee
----------------------------------------------
Le decalage `~NNH` est ajoute BRUT a la plume (font.gc cfg-109 : `.itof.vf` sans
echelle). En ajustant le modele « centre de l'encre de l'accent = centre de l'encre de
la lettre » sur les 50 entrees livrees :
    - lu dans le repere de la GRANDE police : k = 1.000 (mediane), 0.816..1.119
    - lu dans le repere de la PETITE police : k = 0.411 (mediane)
Les decalages livres sont donc exprimes en PIXELS ECRAN DE LA GRANDE POLICE. Comme ils
sont appliques sans mise a l'echelle, ils sont FAUX d'un facteur ~2.4 en petite police.
C'est un defaut du jeu d'origine, il n'est pas corrige ici et il est publie tel quel
dans le rapport de phase.

Ce que ce script fait, et ce qu'il ne fait pas
----------------------------------------------
Il AJOUTE les entrees minuscules, calculees sur l'atlas Urbanist genere.
Il NE TOUCHE PAS aux entrees majuscules livrees : leurs decalages sont regles a la main
par Naughty Dog, l'avance moyenne A-Z ne bouge que de 5,6 % avec Urbanist, et les
recalculer echangerait un reglage connu contre un modele a +-12 % de dispersion.
"""
import json
import os
import re

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONTDIR = os.path.dirname(os.path.abspath(__file__))
ATLAS = os.path.join(ROOT, "custom_assets", "jak1", "recharged_textures",
                     "gamefontnew", "ascii.24lo.png")
DB = os.path.join(ROOT, "common", "util", "font", "dbs", "font_db_jak1.cpp")

DOTLESS = 0x19                     # cellule reaffectee au « i sans point »
CW, CH, SCALE = 24, 32, 2          # cellule du grand atlas, et son surechantillonnage
QUAD_H_RATIO = 0.5                 # quad 24 x 16 ecran pour une cellule 24 x 32 texels

MARK_CODE = {"ˇ": 0x10, "`": 0x11, "'": 0x12, "^": 0x13, "<TIL>": 0x14,
             "¨": 0x15, "º": 0x16, ",": 0x2C, "-": 0x2D, "/": 0x2F}

# Classement des marques. "-" est ambigu : macron AU-DESSUS dans Ū (V = -10), barre
# TRAVERSANTE dans Đ (V = -1). On tranche sur l'amplitude de V livree.
ABOVE = {"ˇ", "`", "'", "^", "<TIL>", "¨", "º"}
BELOW = {","}
THROUGH = {"/"}


def ink(img, code):
    idx = code - 16
    x0, y0 = (idx % 10) * CW * SCALE, (idx // 10) * CH * SCALE
    a = img.split()[3].crop((x0, y0, x0 + CW * SCALE, y0 + CH * SCALE))
    bb = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bb is None:
        return None
    return tuple(v / SCALE for v in bb)   # (l, t, r, b) en texels de la cellule


def main():
    img = Image.open(ATLAS).convert("RGBA")
    adv24 = {int(k): v for k, v in
             json.load(open(os.path.join(FONTDIR, "urbanist-tables.json")))["w_font24"].items()}
    src = open(DB, encoding="utf-8").read()
    blk = src[src.index("replace_info_jak1"):]
    blk = blk[:blk.index("\n};")]

    one = re.compile(r'\{"([A-Za-z])~Y~([-+]?\d+)H~([-+]?\d+)V(<TIL>|[^~])~Z",\s*"(.+?)"\}')
    two = re.compile(r'\{"([A-Za-z])~Y~([-+]?\d+)H~([-+]?\d+)V(<TIL>|[^~])~([-+]?\d+)H(.)~Z",\s*"(.+?)"\}')

    out, skipped, rows = [], [], []
    seen = set()

    def emit(base_up, H_up, V_up, mark, res_up, second=None):
        low = res_up.lower()
        base_lo = base_up.lower()
        # le i accentue se compose sur le i SANS POINT (cellule 0x19), sinon le point
        # du i et l'accent se superposent
        if base_lo == "i":
            base_lo = "ı"
        if len(low) != 1 or low == res_up or low in seen:
            skipped.append((res_up, "pas de minuscule simple"))
            return
        cb_up = ink(img, ord(base_up))
        cb_lo = ink(img, DOTLESS if base_lo == "ı" else ord(base_lo))
        cm = ink(img, MARK_CODE[mark])
        if not (cb_up and cb_lo and cm):
            skipped.append((res_up, "encre absente dans l'atlas"))
            return
        centre = lambda b: (b[0] + b[2]) / 2.0
        # horizontal : meme regle que celle ajustee sur les entrees livrees (k = 1.000)
        H = int(round(centre(cb_lo) - centre(cm)
                      - adv24[DOTLESS if base_lo == "ı" else ord(base_lo)]))
        # vertical : on conserve la RELATION visuelle de l'entree majuscule livree
        kind = mark
        if mark == "-":
            kind = "above" if abs(V_up) >= 6 else "through"
        elif mark in ABOVE:
            kind = "above"
        elif mark in BELOW:
            kind = "below"
        elif mark in THROUGH:
            kind = "through"
        if kind == "above":
            # y croit vers le BAS ; une minuscule a son sommet d'encre PLUS BAS, donc le
            # decalage doit etre MOINS negatif pour que l'accent descende avec elle.
            V = V_up + (cb_lo[1] - cb_up[1]) * QUAD_H_RATIO
        elif kind == "below":
            V = V_up
        else:  # traversante : on suit le MILIEU de la lettre
            mid = lambda b: (b[1] + b[3]) / 2.0
            V = V_up + (mid(cb_lo) - mid(cb_up)) * QUAD_H_RATIO
        V = int(round(V))
        seen.add(low)
        # SIGNE OBLIGATOIRE : sans signe, l'analyseur d'echappement FIXE la plume a la
        # valeur absolue au lieu de la decaler (font.gc cfg-113 : `.add.x.vf.x vf23 vf0
        # vf1`). `~0V` remettrait donc y a zero. Les entrees livrees portent toutes leur
        # signe pour cette raison ("~+3V" dans Ą).
        if second is None:
            enc = "%s~Y~%+dH~%+dV%s~Z" % (base_lo, H, V, mark)
        else:
            enc = "%s~Y~%+dH~%+dV%s~%+dH%s~Z" % (base_lo, H, V, mark, second[0], second[1])
        out.append('    {"%s", "%s"},' % (enc, low))
        rows.append((res_up, low, base_lo, mark, H_up, H, V_up, V))

    for m in two.finditer(blk):
        emit(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(7),
             second=(int(m.group(5)), m.group(6)))
    for m in one.finditer(blk):
        if m.group(4) not in MARK_CODE:
            skipped.append((m.group(5), "marque inconnue %r" % m.group(4)))
            continue
        emit(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5))

    report = []
    report.append("entrees minuscules fabriquees : %d" % len(out))
    report.append("resultat   base marque   H maj -> H min   V maj -> V min")
    for r in sorted(rows, key=lambda r: r[1]):
        report.append("  %-3s -> %-3s %-2s %-5s %6d -> %-6d %6d -> %-6d"
                      % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
    if skipped:
        report.append("ignorees : %d" % len(skipped))
        for s in skipped:
            report.append("  %s : %s" % s)
    print("\n".join(report))

    gen = ("    // ==== GENERE par recharged_assets/font/gen_accent_table.py — NE PAS "
           "EDITER A LA MAIN ====\n"
           "    // Composition des MINUSCULES accentuees. Les decalages sont en pixels\n"
           "    // ecran de la GRANDE police (unite mesuree sur les 50 entrees livrees,\n"
           "    // k = 1.000), et calcules sur l'atlas Urbanist genere.\n"
           + "\n".join(out) + "\n"
           "    // ==== FIN GENERE ====\n")
    marker = "    // ==== GENERE par recharged_assets/font/gen_accent_table.py"
    if marker in src:
        a = src.index(marker)
        b = src.index("    // ==== FIN GENERE ====\n", a) + len("    // ==== FIN GENERE ====\n")
        src = src[:a] + gen + src[b:]
    else:
        anchor = src.index("std::vector<ReplaceInfo> replace_info_jak1 = {")
        anchor = src.index("\n", anchor) + 1
        src = src[:anchor] + gen + src[anchor:]
    open(DB, "w").write(src)

    rp = os.path.join(ROOT, ".autoport", "reports", "Gfont-urbanist")
    os.makedirs(rp, exist_ok=True)
    open(os.path.join(rp, "accent-table.txt"), "w").write("\n".join(report) + "\n")


if __name__ == "__main__":
    main()
