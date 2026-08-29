#!/usr/bin/env python3
"""Gloading-screen — atlas des glyphes precurseurs, HAUTE RESOLUTION et ANTIALIASE.

Rejouable : ecrase ses sorties, ne modifie jamais la planche source.

DEUX DEFAUTS MESURES QUE CE SCRIPT CORRIGE (owner 2026-08-29 : « les glyphs precursor sont
pixellisés et certains sont inversés ») :

  1. POLARITE. L'ancienne generation devinait la polarite PAR GLYPHE avec la regle « l'encre est
     minoritaire ». Fausse pour les formes pleines : E, G, H, K, M, P, S couvrent plus de la
     moitie de leur boite. Ici la polarite est etablie UNE SEULE FOIS sur la planche entiere
     (l'encre y est SOMBRE sur fond clair) et appliquee uniformement. Aucune heuristique par glyphe.

  2. PIXELLISATION, et elle a DEUX causes cumulees, toutes deux mesurees :
     (a) l'atlas livre etait STRICTEMENT BINAIRE — 2 niveaux de gris, 0 pixel intermediaire —
         alors que la planche source est ANTIALIASEE (2408 pixels intermediaires dans la seule
         premiere bande). Le seuillage jetait l'antialiasing de l'auteur.
     (b) les glyphes ne faisaient que 33 a 63 px de large pour un rendu ecran de ~52 a 61 px :
         un agrandissement de ~1,1x d'un masque binaire, c'est exactement l'escalier que
         l'owner decrit.
     Correctif : on garde la COUVERTURE antialiasee de la planche, on la reconstruit par un
     CHAMP DE DISTANCE SIGNE sous-pixel (la seule grandeur d'un masque qui se reechantillonne
     proprement — une couverture, elle, se floute), et on rasterise a UPSCALE fois l'em d'origine.
     Le rendu ecran devient alors une REDUCTION, jamais un agrandissement.

Entree  : recharged_assets/font/precursor/source-precurian-latin.png  (1607x1181 RGB)
Sorties : recharged_assets/font/precursor/precursor-atlas.png         (L, ATLAS_PX carre)
          recharged_assets/font/precursor/precursor.json              (metriques + UV)
          .autoport/design/precursor-alphabet.png                     (planche de controle)
          .autoport/reports/Gloading-screen/precursor-atlas.txt       (mesures publiees)
"""

import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "recharged_assets", "font", "precursor", "source-precurian-latin.png")
OUT_ATLAS = os.path.join(ROOT, "recharged_assets", "font", "precursor", "precursor-atlas.png")
OUT_JSON = os.path.join(ROOT, "recharged_assets", "font", "precursor", "precursor.json")
OUT_PROOF = os.path.join(ROOT, ".autoport", "design", "precursor-alphabet.png")
OUT_TXT = os.path.join(ROOT, ".autoport", "reports", "Gloading-screen", "precursor-atlas.txt")

UPSCALE = 4          # em 72 -> 288 px de dessin
ATLAS_PX = 2048      # 6 colonnes x 5 rangees de cellules de 336 px : 2016 <= 2048
CELL = 336
COLS = 6
EM_SRC = 72.0        # em de dessin de la planche = hauteur de sa bande la plus haute (mesuree : 72)
ADV_PAD_EM = 0.16    # CONVENTION d'avance, reglable : avance = largeur + ADV_PAD_EM * em
MERGE_GAP = 40       # px : deux morceaux plus proches que ca appartiennent au meme glyphe
INK_BLACK = 0.60     # couverture au-dela de laquelle on est dans l'encre NOIRE d'un glyphe.
                     # Les ETIQUETTES latines de la planche sont GRISES (couverture ~0,5) : ce
                     # seuil les ecarte de la SEGMENTATION. Il ne sert qu'a delimiter les boites ;
                     # le reechantillonnage, lui, lit la couverture ANTIALIASEE complete.
BAND_MIN_H = 20      # px : une bande plus courte que ca est une etiquette, pas des glyphes

LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

lines = []


def emit(s):
    print(s)
    lines.append(s)


def coverage_from_plate():
    """Couverture d'encre dans [0,1], ANTIALIASING CONSERVE.

    POLARITE ETABLIE UNE SEULE FOIS ICI : sur la planche entiere le fond est clair
    (mediane proche de 255) et l'encre sombre. On publie les deux nombres pour que ce soit
    verifiable et non postule."""
    plate = np.asarray(Image.open(SRC).convert("L")).astype(np.float64)
    med = float(np.median(plate))
    dark_frac = float((plate < 128).mean())
    emit("PLATE_SIZE=%dx%d" % (plate.shape[1], plate.shape[0]))
    emit("PLATE_MEDIAN=%.1f" % med)
    emit("PLATE_DARK_FRACTION=%.4f" % dark_frac)
    if not (med > 128 and dark_frac < 0.5):
        raise SystemExit("ERREUR: la planche n'est pas 'encre sombre sur fond clair' — polarite a revoir")
    emit("PLATE_POLARITE=encre-sombre-sur-fond-clair (etablie UNE FOIS, appliquee a TOUS les glyphes)")
    # Le fond de la planche est a ~245-253, pas a 255 : normaliser sur SA valeur, sinon un voile
    # de couverture ~0,03 subsiste partout et deborde des boites de glyphes.
    cov = np.clip((med - plate) / med, 0.0, 1.0)
    aa = int(((cov > 0.10) & (cov < 0.90)).sum())
    emit("PLATE_PIXELS_ANTIALIASES=%d" % aa)
    emit("PLATE_FOND_NORMALISE_SUR=%.1f" % med)
    return cov


def segment(cov):
    """Bandes puis colonnes, exactement comme la generation d'origine (fusion des morceaux
    distants de moins de MERGE_GAP px : plusieurs glyphes ont des points detaches)."""
    ink = cov > INK_BLACK
    rows = ink.sum(axis=1)
    bands, inb, y0 = [], False, 0
    for y, v in enumerate(rows):
        if v > 0 and not inb:
            y0, inb = y, True
        elif v == 0 and inb:
            bands.append((y0, y))
            inb = False
    if inb:
        bands.append((y0, len(rows)))
    bands = [b for b in bands if b[1] - b[0] >= BAND_MIN_H]

    boxes = []
    for (by0, by1) in bands:
        cols = ink[by0:by1].sum(axis=0)
        segs, inc, x0 = [], False, 0
        for x, v in enumerate(cols):
            if v > 0 and not inc:
                x0, inc = x, True
            elif v == 0 and inc:
                segs.append((x0, x))
                inc = False
        if inc:
            segs.append((x0, len(cols)))
        merged = []
        for s in segs:
            if merged and s[0] - merged[-1][1] < MERGE_GAP:
                merged[-1] = (merged[-1][0], s[1])
            else:
                merged.append((s[0], s[1]))
        # une bande d'etiquette est une seule colonne tres large : elle ne porte pas de glyphes
        if len(merged) == 1 and (merged[0][1] - merged[0][0]) > 6 * CELL // UPSCALE:
            emit("BANDE_IGNOREE y=%d..%d largeur=%d (etiquette, pas des glyphes)"
                 % (by0, by1, merged[0][1] - merged[0][0]))
            continue
        for (mx0, mx1) in merged:
            # recadrage vertical serre sur l'encre de CE glyphe
            sub = ink[by0:by1, mx0:mx1]
            ys = np.where(sub.any(axis=1))[0]
            boxes.append((mx0, by0 + int(ys[0]), mx1, by0 + int(ys[-1]) + 1))
        emit("BANDE y=%d..%d colonnes=%d" % (by0, by1, len(merged)))
    return boxes


def resample_glyph(cov, box):
    """Reechantillonne le glyphe de `box` a UPSCALE fois sa taille en RESTITUANT UN BORD NET.

    POURQUOI PAS UN SIMPLE AGRANDISSEMENT DE LA COUVERTURE : agrandir une couverture FLOUTE le
    bord — le degrade s'etale sur UPSCALE pixels au lieu d'un, et un glyphe flou n'est pas mieux
    qu'un glyphe en escalier.

    CE QU'ON FAIT, ET POURQUOI C'EST EXACT AU VOISINAGE D'UN BORD. Le long d'un contour, la
    couverture d'un pixel vaut `0,5 + d` ou `d` est la distance signee au contour, en pixels
    source (c'est la definition meme de l'antialiasing par aire). Un agrandissement bicubique
    preserve cette rampe. La remettre a la pente 1 dans la NOUVELLE grille, c'est donc
    `alpha = (c - 0,5) * UPSCALE + 0,5`, borne a [0,1] : le bord retrouve une largeur d'UN pixel
    a la nouvelle resolution, et sa POSITION SOUS-PIXEL — celle que l'auteur a dessinee dans
    l'antialiasing de la planche — est conservee. Loin du bord la couverture sature a 0 ou 1 et
    le bornage rend exactement 0 ou 1.

    C'est la meme construction qu'un champ de distance signe, restreinte a la seule bande ou elle
    est valide : la seule ou on en a besoin."""
    x0, y0, x1, y1 = box
    pad = 2
    g = np.zeros((y1 - y0 + 2 * pad, x1 - x0 + 2 * pad), dtype=np.float32)
    g[pad:-pad, pad:-pad] = cov[y0:y1, x0:x1]
    if not (g >= 0.5).any():
        raise SystemExit("ERREUR: glyphe vide")

    big = np.asarray(
        Image.fromarray(g, mode="F").resize(
            (g.shape[1] * UPSCALE, g.shape[0] * UPSCALE), Image.BICUBIC
        )
    ).astype(np.float64)
    alpha = np.clip((big - 0.5) * UPSCALE + 0.5, 0.0, 1.0)

    p = pad * UPSCALE
    alpha = alpha[p:alpha.shape[0] - p, p:alpha.shape[1] - p]
    return alpha


def main():
    os.makedirs(os.path.dirname(OUT_TXT), exist_ok=True)
    emit("# Gloading-screen — atlas precurseur, produit par .autoport/mk_precursor_atlas.py")
    cov = coverage_from_plate()
    boxes = segment(cov)
    emit("GLYPHES_DETECTES=%d" % len(boxes))
    if len(boxes) != 26:
        raise SystemExit("ERREUR: %d glyphes detectes, 26 attendus" % len(boxes))

    atlas = np.zeros((ATLAS_PX, ATLAS_PX), dtype=np.float64)
    em_px = EM_SRC * UPSCALE
    glyphs = []
    for i, box in enumerate(boxes):
        a = resample_glyph(cov, box)
        gh, gw = a.shape
        if gw > CELL or gh > CELL:
            raise SystemExit("ERREUR: glyphe %s (%dx%d) plus grand que la cellule %d"
                             % (LETTERS[i], gw, gh, CELL))
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        # marge de 8 px dans la cellule : evite que les mipmaps de l'atlas melangent deux glyphes
        ox, oy = cx + 8, cy + 8
        atlas[oy:oy + gh, ox:ox + gw] = a
        # PLACEMENT VERTICAL. Les glyphes de la planche sont CENTRES dans leur bande : sur les
        # 26, l'ecart entre le centre du glyphe et le centre de sa bande vaut au plus 3 px sur 72,
        # soit 4 %. On centre donc chaque glyphe dans une boite d'em COMMUNE, ce qui donne une
        # ligne dont tous les glyphes partagent une mediane — et non des SOMMETS alignes, qui
        # feraient sautiller les glyphes courts (P : 53 px de haut) au-dessus des longs (Z : 70).
        by = (em_px - gh) * 0.5
        glyphs.append({
            "char": LETTERS[i],
            "cp": ord(LETTERS[i]),
            "u0": ox / float(ATLAS_PX),
            "v0": oy / float(ATLAS_PX),
            "u1": (ox + gw) / float(ATLAS_PX),
            "v1": (oy + gh) / float(ATLAS_PX),
            "w": gw,
            "h": gh,
            "by": round(by, 4),
            "adv": gw + ADV_PAD_EM * em_px,
            "src_box": list(map(int, box)),
        })

    img = Image.fromarray(np.round(atlas * 255.0).astype(np.uint8), mode="L")
    img.save(OUT_ATLAS)
    hist = img.histogram()
    mid = sum(hist[9:248])
    emit("ATLAS_OUT=%s %dx%d L" % (OUT_ATLAS, ATLAS_PX, ATLAS_PX))
    emit("ATLAS_EM_PX=%d  (etait 72 — facteur %d)" % (int(em_px), UPSCALE))
    emit("ATLAS_LARGEUR_GLYPHE_MIN=%d MAX=%d" % (min(g["w"] for g in glyphs),
                                                 max(g["w"] for g in glyphs)))
    emit("ATLAS_PIXELS_ANTIALIASES=%d  (etait 0 — l'atlas precedent etait strictement binaire)" % mid)

    with open(OUT_JSON, "w") as f:
        json.dump({
            "size_px": int(em_px),
            "atlas": [ATLAS_PX, ATLAS_PX],
            "count": 26,
            "upscale": UPSCALE,
            "note": ("Encre=255, fond=0. Polarite determinee UNE FOIS depuis la planche "
                     "(encre sombre sur fond clair), jamais par glyphe. Reechantillonnage par "
                     "champ de distance signe sous-pixel, antialiasing conserve. "
                     "Avance = largeur + %.2f x em, CONVENTION reglable. `by` = decalage "
                     "vertical depuis le haut de la boite d'em, glyphe CENTRE." % ADV_PAD_EM),
            "glyphs": glyphs,
        }, f, indent=1)
    emit("JSON_OUT=%s" % OUT_JSON)

    # planche de controle : les 26 glyphes a la suite, blanc sur noir
    ph = 320
    pw = sum(int(g["w"] * ph / float(g["h"])) + 8 for g in glyphs)
    proof = Image.new("L", (pw, ph + 16), 0)
    px = 4
    for g, box in zip(glyphs, boxes):
        gw = int(g["w"] * ph / float(g["h"]))
        cell = img.crop((int(g["u0"] * ATLAS_PX), int(g["v0"] * ATLAS_PX),
                         int(g["u1"] * ATLAS_PX), int(g["v1"] * ATLAS_PX)))
        proof.paste(cell.resize((gw, ph), Image.LANCZOS), (px, 8))
        px += gw + 8
    proof.save(OUT_PROOF)
    emit("PLANCHE_CONTROLE=%s %dx%d (26 glyphes, tous blancs sur noir)" % (OUT_PROOF, pw, ph + 16))

    with open(OUT_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
