#!/usr/bin/env python3
"""Gloading-screen-window — MESURE, DANS L'IMAGE PRODUITE, la taille et la position du bloc de
texte de l'ecran de chargement.

Owner 2026-08-30 (D2) : « Le texte Chargement... et les glyphs Precursor en dessous est toujours
beaucoup trop gros, ca devrait etre plus bas a droite et surtout bien plus petit, genre moitie
moins gros. »

NATURE : trois grandeurs sans dimension — une HAUTEUR de bande, une abscisse de BORD DROIT, une
  ordonnee de BORD HAUT, toutes rapportees a la taille de l'image.
REPERE : l'image rendue elle-meme, en fractions de sa hauteur / largeur. Ni la toile 512, ni le
  modele de mise en page. C'est ce qui rend la mesure INDEPENDANTE du calcul qu'elle verifie : la
  ligne `LOADSCREEN-COSM` du moteur republie les constantes qu'on vient de poser et ne pourrait
  pas se contredire — ce serait un miroir.
CE QU'ELLE LIT QUAND LE DEFAUT EST ABSENT : le rapport des deux hauteurs de bande vaut 0,5.

LA SILHOUETTE EST ETEINTE PENDANT LA MESURE (`*ls-draw-silhouette*` = #f). Elle chevauche la bande
de texte en x ET en y depuis qu'elle porte une foulee de course : mesuree avec, l'allemand rendait
1 456 px de « largeur de texte » au lieu de 855 parce que l'instrument agregeait le personnage et
la phrase. On isole donc ce qu'on pretend mesurer. Le fond etant un noir plein, tout pixel allume
est de l'encre du bloc de texte.
"""

import argparse
import sys

import numpy as np
from PIL import Image

INK = 40  # luminance au-dessus de laquelle un pixel est de l'encre (le fond est noir plein)


def bands(ink):
    """Bandes horizontales continues d'encre : [(y0, y1), ...]."""
    rows = ink.any(axis=1)
    out, inb, y0 = [], False, 0
    for y, v in enumerate(rows):
        if v and not inb:
            y0, inb = y, True
        elif not v and inb:
            out.append((y0, y))
            inb = False
    if inb:
        out.append((y0, len(rows)))
    return out


def measure(path):
    a = np.asarray(Image.open(path).convert("L")).astype(np.int16)
    h, w = a.shape
    ink = a > INK
    bs = [b for b in bands(ink) if (b[1] - b[0]) >= 3]
    if not bs:
        return None
    xs = np.where(ink.any(axis=0))[0]
    res = {
        "w": w,
        "h": h,
        "bandes": len(bs),
        # bloc entier : c'est lui qui porte la POSITION
        "top": int(bs[0][0]),
        "bottom": int(bs[-1][1]),
        "left": int(xs[0]),
        "right": int(xs[-1]) + 1,
    }
    # bande de texte = la PREMIERE (le « Loading... » est au-dessus des glyphes precurseurs)
    ty0, ty1 = bs[0]
    res["texte_h"] = int(ty1 - ty0)
    txs = np.where(ink[ty0:ty1].any(axis=0))[0]
    res["texte_left"] = int(txs[0])
    res["texte_right"] = int(txs[-1]) + 1
    if len(bs) > 1:
        gy0, gy1 = bs[-1]
        res["glyphes_h"] = int(gy1 - gy0)
        res["glyphes_top"] = int(gy0)
    else:
        res["glyphes_h"] = 0
        res["glyphes_top"] = 0
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("avant")
    ap.add_argument("apres")
    args = ap.parse_args()
    a = measure(args.avant)
    b = measure(args.apres)
    if not a or not b:
        print("FAIL: aucune encre dans une des deux captures", file=sys.stderr)
        return 1
    for nom, m in (("avant", a), ("apres", b)):
        print(
            "COSM-{} image={}x{} bandes={} texte_h={}px bloc_top={}px bloc_droite={}px "
            "glyphes_h={}px".format(
                nom, m["w"], m["h"], m["bandes"], m["texte_h"], m["top"], m["right"],
                m["glyphes_h"]
            )
        )
    # Les trois grandeurs du verdict, en fractions de l'image.
    sa = a["texte_h"] / a["h"]
    sb = b["texte_h"] / b["h"]
    print(
        "LSTEXT scale_before={:.6f} scale_after={:.6f} xfrac_before={:.6f} xfrac_after={:.6f} "
        "yfrac_before={:.6f} yfrac_after={:.6f}".format(
            sa, sb, a["right"] / a["w"], b["right"] / b["w"], a["top"] / a["h"], b["top"] / b["h"]
        )
    )
    print("LSTEXT-RAPPORT taille={:.4f} (cible 0,5)".format(sb / sa if sa else 0.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
