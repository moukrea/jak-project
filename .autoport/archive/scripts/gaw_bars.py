#!/usr/bin/env python3
"""Gandroid-window-size — comptage des barres noires en bord d'image.

CE QUE CETTE MESURE EST, ET DANS QUEL REPERE (les trois questions du contrat) :

  NATURE  — un COMPTE de colonnes / de lignes, a chacun des quatre bords de l'image
            composee. Ce n'est ni une variance, ni un ratio, ni un jugement visuel :
            c'est le nombre de colonnes entierement noires que le compositeur laisse
            de chaque cote quand la region de dessin est plus petite que la fenetre.
  REPERE  — pixels de l'ECRAN de l'appareil, tels que `adb exec-out screencap -p` les
            rend, origine en haut a gauche, surface entiere. Pas l'espace jeu 512x224
            du HUD, pas la resolution interne du FBO 3D.
  LECTURE QUAND LE DEFAUT EST ABSENT — 0 aux quatre bords. Et parce qu'une image
            ENTIEREMENT noire donnerait elle aussi 0/0/0/0 sans rien prouver, la
            luminance de l'INTERIEUR est publiee a cote et l'image est REJETEE
            (verdict `vide`) si l'interieur est lui-meme noir. Un zero tire d'un
            domaine vide est le faux vert le plus facile a produire.

Une colonne compte comme NOIRE si au moins 99,9 % de ses pixels ont max(R,G,B) <= SEUIL
(defaut 8/255). Le compositeur efface a 0,0,0 exactement ; le seuil laisse la marge du
codage JPEG/PNG et du dithering du panneau, pas celle d'une scene sombre.
"""
import sys
import numpy as np
from PIL import Image, ImageFile

# Une capture peut etre tronquee si `screencap` est interrompu : on le DIT au lieu de
# rendre un chiffre sur une image incomplete.
ImageFile.LOAD_TRUNCATED_IMAGES = False

# SEUIL. Mesure du 2026-08-28 sur le Redmi (controle 4:3) : la barre de droite contient
# un element d'interface tres sombre, de valeur MAXIMALE 16/255, haut de 57 px, colle au
# bord (x 2360-2378, lignes 451-507). Avec un seuil a 8 il coupait le comptage a 21
# colonnes alors que la region DESSINEE se termine bien a x=1919 : bande reelle 480 px.
# Le seuil est donc porte a 24/255 (9,4 % de luminance -- toujours du noir a l'oeil), et
# la valeur MAXIMALE trouvee A L'INTERIEUR des bandes detectees est publiee a cote du
# compte : une "bande" qui ne serait pas vraiment noire se voit sur cette colonne-la, on
# ne se contente pas de la declarer sous le seuil.
THRESH = 24
# TOLERANCE PAR LIGNE. Une colonne compte comme NOIRE si au moins 99 % de ses pixels sont
# sous le seuil. Mesure du 2026-08-28, Redmi, controle 4:3 : la bande de droite contient
# UN element d'interface de 38x8 px a x=2314..2351, y=475..482, valeur maximale 25/255 --
# identique sur les quatre captures, donc statique (surcouche tactile, pas du jeu). Exiger
# 100 % de noir coupait le compte a 48 colonnes pour une bande qui en fait 480 : le
# constat est faux a cause de 175 pixels sur 518 400. Le compte des pixels au-dessus du
# seuil DANS les bandes est publie (`bande_px`) avec leur valeur maximale (`bande_max`) :
# une vraie image dans la bande s'y verrait immediatement (des dizaines de milliers de
# pixels, valeur max 255), une poussiere d'interface non.
FRAC = 0.99


def black_mask(a):
    return a.max(axis=2) <= THRESH


def count_edge(black, axis, reverse):
    # black: HxW bool. axis=1 -> colonnes (bords gauche/droite), axis=0 -> lignes.
    if axis == 1:
        line_black = black.mean(axis=0)          # une valeur par colonne
    else:
        line_black = black.mean(axis=1)          # une valeur par ligne
    idx = range(len(line_black) - 1, -1, -1) if reverse else range(len(line_black))
    n = 0
    for i in idx:
        if line_black[i] >= FRAC:
            n += 1
        else:
            break
    return n


def measure(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.uint8)
    h, w, _ = a.shape
    black = black_mask(a)
    left = count_edge(black, 1, False)
    right = count_edge(black, 1, True)
    top = count_edge(black, 0, False)
    bottom = count_edge(black, 0, True)
    # interieur = ce qui reste une fois les bandes retirees
    x0, x1 = left, w - right
    y0, y1 = top, h - bottom
    if x1 <= x0 or y1 <= y0:
        inner_mean = inner_max = 0.0
        lit = 0.0
    else:
        inner = a[y0:y1, x0:x1]
        m = inner.max(axis=2)
        inner_mean = float(m.mean())
        inner_max = float(m.max())
        lit = float((m > 32).mean())
    # valeur la plus claire DANS les bandes detectees (0 s'il n'y a pas de bande)
    full = a.max(axis=2)
    bar_pix = []
    if left:
        bar_pix.append(full[:, :left].max())
    if right:
        bar_pix.append(full[:, w - right:].max())
    if top:
        bar_pix.append(full[:top, :].max())
    if bottom:
        bar_pix.append(full[h - bottom:, :].max())
    bar_max = int(max(bar_pix)) if bar_pix else 0
    bar_px = 0
    if left:
        bar_px += int((full[:, :left] > THRESH).sum())
    if right:
        bar_px += int((full[:, w - right:] > THRESH).sum())
    if top:
        bar_px += int((full[:top, :] > THRESH).sum())
    if bottom:
        bar_px += int((full[h - bottom:, :] > THRESH).sum())
    return dict(path=path, w=w, h=h, left=left, right=right, top=top, bottom=bottom,
                inner_mean=inner_mean, inner_max=inner_max, lit=lit, bar_max=bar_max,
                bar_px=bar_px, box_w=x1 - x0, box_h=y1 - y0)


def verdict(r):
    # Une image dont l'interieur n'est pas eclaire ne mesure RIEN : elle ne peut pas
    # distinguer « pas de bandes » de « ecran noir ».
    if r["lit"] < 0.02 or r["inner_max"] < 64:
        return "VIDE(image noire — ne compte pas)"
    if r["left"] or r["right"] or r["top"] or r["bottom"]:
        return "BANDES"
    return "0-BANDE"


def main():
    for p in sys.argv[1:]:
        try:
            r = measure(p)
        except Exception as e:  # noqa: BLE001
            print(f"GAW-BARS file={p} ERREUR {e}")
            continue
        print("GAW-BARS file=%s image=%dx%d gauche=%d droite=%d haut=%d bas=%d "
              "cadre_dessine=%dx%d bande_px=%d bande_max=%d interieur_moy=%.1f "
              "interieur_max=%.0f eclaire=%.3f verdict=%s"
              % (p.split('/')[-1], r["w"], r["h"], r["left"], r["right"], r["top"],
                 r["bottom"], r["box_w"], r["box_h"], r["bar_px"], r["bar_max"],
                 r["inner_mean"], r["inner_max"], r["lit"], verdict(r)))


if __name__ == "__main__":
    main()
