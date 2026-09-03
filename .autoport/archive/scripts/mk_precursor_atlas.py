#!/usr/bin/env python3
"""Gloading-screen — atlas des glyphes precurseurs, VECTORISE puis rasterise en haute resolution.

Rejouable : ecrase ses sorties, ne modifie jamais la planche source.

OWNER 2026-08-30 : « je pense que tu pourrais les vectoriser via imagick/inkscape
programmatiquement en s'assurant que ça soit pas jagged, en extraire des bitmaps en haute
résolution ».

CE QUI A ETE FAIT AVANT, ET POURQUOI CA NE SUFFISAIT PAS. Le cycle du 2026-08-29 remontait la
couverture antialiasee de la planche a 4x par une rampe de champ de distance
(`alpha = (c-0,5)*4 + 0,5`). Cette operation est FIDELE : elle reproduit le contour de la planche
a la position sous-pixel pres. Mais la fidelite est justement le probleme — la planche est
dessinee a un em de 72 px, donc SON contour porte deja l'escalier de sa propre grille, et le
remonter a 4x le remonte AVEC. On ne peut pas retirer un escalier en agrandissant : il faut
retrouver la COURBE, ce qui est exactement ce que fait un traceur de contours.

CE QUE FAIT CE SCRIPT MAINTENANT, ET AVEC QUOI. `potrace` — l'algorithme que l'owner nomme —
via `potracer`, son portage Python pur (aucun binaire systeme a installer, donc rejouable sur une
machine nue). Trois etapes :

  1. ISOLIGNE SOUS-PIXEL. La planche est ANTIALIASEE : la position exacte du bord n'est pas sur la
     grille de ses pixels, elle est ENCODEE dans la couverture. On sur-echantillonne donc la
     couverture par SUB avant de la binariser a 0,5. Le contour vu par potrace est alors la vraie
     isoligne de l'auteur, echantillonnee au 1/SUB de pixel source, et non la grille de la
     planche. Binariser d'abord et agrandir ensuite aurait jete cette information.
  2. TRACE. potrace rend des contours fermes composes de segments droits (coins) et de cubiques.
     `ALPHAMAX` decide de ce qui est un coin : ces glyphes sont anguleux, on garde donc la valeur
     qui PRESERVE les coins et n'arrondit que le bruit.
  3. RASTERISATION. Balayage maison, couverture EXACTE en x et SS sous-lignes en y, regle
     PAIR-IMPAIR (les contours imbriques donnent donc les trous sans avoir a lire une hierarchie).
     PIL ne sait pas remplir un polygone en antialiasant, et `ImageDraw` seul aurait rendu un
     masque binaire — c'est-a-dire le defaut qu'on corrige.

ET LA MESURE QUI TRANCHE, PARCE QU'UNE APPRECIATION N'EST PAS UNE PREUVE. `DENTELURE` mesure
l'escalier sur le bord OBLIQUE lui-meme : pour chaque ligne du glyphe on releve la position
SOUS-PIXEL du bord (elle se lit dans la couverture), et on prend la derivee seconde de cette
position le long de y. Un bord droit oblique rend 0. Un escalier d'une marche de 1 px tous les k
pixels rend ~sqrt(2/k). Le nombre de MARCHES est le compte des lignes ou |derivee seconde| > 0,5 px.
Les deux sont publies AVANT (l'ancienne rampe) et APRES (le trace vectoriel), sur les MEMES
glyphes et au MEME em : c'est une ablation, pas deux mesures separees.

Entree  : recharged_assets/font/precursor/source-precurian-latin.png  (1607x1181 RGB)
Sorties : recharged_assets/font/precursor/precursor-atlas.png         (L, ATLAS_PX carre)
          recharged_assets/font/precursor/precursor.json              (metriques + UV)
          .autoport/design/precursor-alphabet.png                     (planche de controle)
          .autoport/reports/Gloading-screen/precursor-atlas.txt        (mesures publiees)
"""

import json
import os

import numpy as np
import potrace
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
                     # le trace, lui, lit la couverture ANTIALIASEE complete.
BAND_MIN_H = 20      # px : une bande plus courte que ca est une etiquette, pas des glyphes

SUB = 8              # sur-echantillonnage de la couverture AVANT binarisation : la resolution a
                     # laquelle potrace voit l'isoligne. 8 = 1/8 de pixel source.
SS = 8               # sous-lignes par pixel de sortie a la rasterisation (la couverture en x,
                     # elle, est EXACTE — ce n'est donc pas un sur-echantillonnage 2D).
ALPHAMAX = 1.0       # seuil de coin de potrace. 0 = tout en coins (on garderait l'escalier),
                     # 1,334 = tout en courbes (les coins de ces glyphes seraient arrondis).
                     # 1,0 est la valeur de reference de potrace ; l'effet sur les coins est
                     # publie : ANGLE_MIN_CONSERVE ci-dessous.
OPTTOLERANCE = 0.2   # tolerance d'optimisation des courbes, en unites de la grille SUB — donc
                     # 0,2/8 = 0,025 pixel source. Elle ne peut pas deplacer un contour de facon
                     # visible.

LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

lines = []


def emit(s):
    print(s)
    lines.append(s)


def coverage_from_plate():
    """Couverture d'encre dans [0,1], ANTIALIASING CONSERVE.

    POLARITE ETABLIE UNE SEULE FOIS ICI : sur la planche entiere le fond est clair
    (mediane proche de 255) et l'encre sombre. On publie les deux nombres pour que ce soit
    verifiable et non postule. C'est le correctif de « certains glyphes sont inverses (fond blanc
    glyphe noir) » : l'ancienne generation devinait la polarite PAR GLYPHE avec la regle
    « l'encre est minoritaire », fausse pour E, G, H, K, M, P, S dont l'encre couvre plus de la
    moitie de leur boite."""
    plate = np.asarray(Image.open(SRC).convert("L")).astype(np.float64)
    med = float(np.median(plate))
    dark_frac = float((plate < 128).mean())
    emit("PLATE_SIZE=%dx%d" % (plate.shape[1], plate.shape[0]))
    emit("PLATE_MEDIAN=%.1f" % med)
    emit("PLATE_DARK_FRACTION=%.4f" % dark_frac)
    if not (med > 128 and dark_frac < 0.5):
        raise SystemExit("ERREUR: la planche n'est pas 'encre sombre sur fond clair' — polarite a revoir")
    emit("PLATE_POLARITE=encre-sombre-sur-fond-clair (etablie UNE FOIS, appliquee a TOUS les "
         "glyphes — E, G, H, K, M, P, S compris, les sept que la regle par glyphe inversait)")
    # Le fond de la planche est a ~245-253, pas a 255 : normaliser sur SA valeur, sinon un voile
    # de couverture ~0,03 subsiste partout et deborde des boites de glyphes.
    cov = np.clip((med - plate) / med, 0.0, 1.0)
    aa = int(((cov > 0.10) & (cov < 0.90)).sum())
    emit("PLATE_PIXELS_ANTIALIASES=%d  (c'est cette information sous-pixel que la vectorisation "
         "exploite : sans elle, le contour tracable serait la grille de la planche)" % aa)
    emit("PLATE_FOND_NORMALISE_SUR=%.1f" % med)
    return cov


def segment(cov):
    """Bandes puis colonnes (fusion des morceaux distants de moins de MERGE_GAP px : plusieurs
    glyphes ont des points detaches)."""
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


# ------------------------------------------------------------------------------------------------
# 1. L'ANCIEN CHEMIN, GARDE COMME TEMOIN — c'est lui qui donne la colonne AVANT de la dentelure.
# ------------------------------------------------------------------------------------------------
def resample_ramp(cov, box):
    """Le reechantillonnage du cycle precedent : rampe de champ de distance sur la couverture
    agrandie. Il n'est PLUS livre ; il sert de temoin, pour que l'amelioration soit une ABLATION
    sur le meme glyphe et pas deux mesures sans rapport."""
    x0, y0, x1, y1 = box
    pad = 2
    g = np.zeros((y1 - y0 + 2 * pad, x1 - x0 + 2 * pad), dtype=np.float32)
    g[pad:-pad, pad:-pad] = cov[y0:y1, x0:x1]
    big = np.asarray(
        Image.fromarray(g, mode="F").resize(
            (g.shape[1] * UPSCALE, g.shape[0] * UPSCALE), Image.BICUBIC
        )
    ).astype(np.float64)
    alpha = np.clip((big - 0.5) * UPSCALE + 0.5, 0.0, 1.0)
    p = pad * UPSCALE
    return alpha[p:alpha.shape[0] - p, p:alpha.shape[1] - p]


# ------------------------------------------------------------------------------------------------
# 2. LE CHEMIN LIVRE : ISOLIGNE -> POTRACE -> RASTERISATION ANTIALIASEE
# ------------------------------------------------------------------------------------------------
def _flatten(curve):
    """Un contour potrace -> une polyligne fermee. Les cubiques sont echantillonnees avec un pas
    d'environ 1/3 de pixel de la grille SUB, donc ~1/24 de pixel source : l'erreur de flechissement
    est tres en dessous de ce que la rasterisation peut representer."""
    pts = [(curve.start_point.x, curve.start_point.y)]
    for seg in curve.segments:
        p0 = pts[-1]
        if seg.is_corner:
            pts.append((seg.c.x, seg.c.y))
            pts.append((seg.end_point.x, seg.end_point.y))
        else:
            c1, c2, p3 = seg.c1, seg.c2, seg.end_point
            chord = (abs(c1.x - p0[0]) + abs(c2.x - c1.x) + abs(p3.x - c2.x)
                     + abs(c1.y - p0[1]) + abs(c2.y - c1.y) + abs(p3.y - c2.y))
            n = max(4, min(96, int(chord * 3)))
            for i in range(1, n + 1):
                t = i / n
                mt = 1.0 - t
                x = (mt ** 3 * p0[0] + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t ** 3 * p3.x)
                y = (mt ** 3 * p0[1] + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t ** 3 * p3.y)
                pts.append((x, y))
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts


def _rasterize(polys, w, h):
    """Rasterise des polylignes fermees (regle PAIR-IMPAIR) dans une image de couverture w x h.

    COUVERTURE EXACTE EN X, SS SOUS-LIGNES EN Y. Pour chaque sous-ligne on calcule les abscisses
    d'intersection avec toutes les aretes, on trie, et on remplit les intervalles de rang pair.
    Le remplissage d'un intervalle [a,b] ajoute a CHAQUE pixel la longueur d'intersection avec
    lui — donc un bord vertical rend une couverture exacte, et un bord oblique une erreur bornee
    par 1/SS. C'est ce que PIL ne sait pas faire : `ImageDraw.polygon` remplit en TOUT ou RIEN,
    et un masque binaire est precisement le defaut que ce script corrige."""
    acc = np.zeros((h, w), dtype=np.float64)
    edges = []
    for poly in polys:
        for (ax, ay), (bx, by) in zip(poly, poly[1:]):
            if ay != by:
                edges.append((ax, ay, bx, by))
    if not edges:
        return acc
    E = np.asarray(edges, dtype=np.float64)
    ax, ay, bx, by = E[:, 0], E[:, 1], E[:, 2], E[:, 3]
    ylo = np.minimum(ay, by)
    yhi = np.maximum(ay, by)
    inv = (bx - ax) / (by - ay)

    for row in range(h):
        for k in range(SS):
            y = row + (k + 0.5) / SS
            m = (ylo <= y) & (y < yhi)
            if not m.any():
                continue
            xs = np.sort(ax[m] + (y - ay[m]) * inv[m])
            for i in range(0, len(xs) - 1, 2):
                a, b = xs[i], xs[i + 1]
                if b <= 0 or a >= w or b <= a:
                    continue
                a = max(a, 0.0)
                b = min(b, float(w))
                ia, ib = int(a), int(min(b, w - 1e-9))
                if ia == ib:
                    acc[row, ia] += (b - a) / SS
                else:
                    acc[row, ia] += (ia + 1 - a) / SS
                    if ib > ia + 1:
                        acc[row, ia + 1:ib] += 1.0 / SS
                    acc[row, ib] += (b - ib) / SS
    return np.clip(acc, 0.0, 1.0)


def vectorize_glyph(cov, box):
    """Couverture antialiasee -> contours potrace -> bitmap haute resolution antialiasee.

    Rend (alpha, n_contours, n_segments, angle_min_deg)."""
    x0, y0, x1, y1 = box
    pad = 2
    g = np.zeros((y1 - y0 + 2 * pad, x1 - x0 + 2 * pad), dtype=np.float32)
    g[pad:-pad, pad:-pad] = cov[y0:y1, x0:x1]
    if not (g >= 0.5).any():
        raise SystemExit("ERREUR: glyphe vide")

    # ISOLIGNE : on sur-echantillonne la COUVERTURE puis on binarise, jamais l'inverse.
    big = np.asarray(
        Image.fromarray(g, mode="F").resize(
            (g.shape[1] * SUB, g.shape[0] * SUB), Image.BICUBIC
        )
    ).astype(np.float64)
    mask = big >= 0.5

    # `potrace.Bitmap` INVERSE ce qu'on lui donne (Bitmap.__init__ appelle self.invert()) : le
    # vrai avant-plan est donc le complement. Verifie sur un anneau synthetique — passer le masque
    # tel quel faisait tracer le FOND, et le premier contour rendu etait le rectangle de l'image.
    path = potrace.Bitmap(~mask).trace(
        turdsize=max(2, SUB * SUB // 4),   # < 1/4 de pixel source : du bruit, pas un point de glyphe
        alphamax=ALPHAMAX,
        opticurve=True,
        opttolerance=OPTTOLERANCE,
    )
    polys = [_flatten(c) for c in path.curves]
    nseg = sum(len(c.segments) for c in path.curves)

    # Angle le plus AIGU conserve : si potrace avait arrondi les coins, ce nombre monterait vers
    # 180. C'est un des deux controles que ALPHAMAX ne detruit pas la forme (l'autre est le
    # recouvrement avec le temoin, mesure dans main()).
    amin = 180.0
    corners = [(p, q, r) for poly in polys for p, q, r in zip(poly, poly[1:], poly[2:])]
    for p, q, r in corners:
        v1 = np.array([q[0] - p[0], q[1] - p[1]])
        v2 = np.array([r[0] - q[0], r[1] - q[1]])
        n1, n2 = np.linalg.norm(v1), np.linalg.norm(v2)
        if n1 < SUB * 0.5 or n2 < SUB * 0.5:      # segments courts = flechissement, pas un coin
            continue
        cosang = float(np.clip(np.dot(v1, v2) / (n1 * n2), -1.0, 1.0))
        amin = min(amin, 180.0 - np.degrees(np.arccos(cosang)))

    # RASTERISATION a l'em de l'atlas. Les contours sont en unites de la grille SUB.
    scale = float(UPSCALE) / SUB
    w = int(round(g.shape[1] * UPSCALE))
    h = int(round(g.shape[0] * UPSCALE))
    polys = [[(px * scale, py * scale) for (px, py) in poly] for poly in polys]
    alpha = _rasterize(polys, w, h)

    p = pad * UPSCALE
    return alpha[p:alpha.shape[0] - p, p:alpha.shape[1] - p], len(path.curves), nseg, amin


# ------------------------------------------------------------------------------------------------
# 3. LA MESURE DE DENTELURE
# ------------------------------------------------------------------------------------------------
def _edge_positions(a, side):
    """Position SOUS-PIXEL du bord gauche (side=-1) ou droit (side=+1) de l'encre, ligne par ligne.

    La couverture d'un pixel de bord vaut la fraction de sa surface couverte : le bord tombe donc
    a `x_premier_plein - couverture_de_la_rampe`. On somme la rampe au lieu de chercher un seuil,
    ce qui donne une position continue et non quantifiee — sans quoi on ne pourrait PAS distinguer
    un escalier d'une droite."""
    h, w = a.shape
    out = np.full(h, np.nan)
    for y in range(h):
        row = a[y] if side < 0 else a[y][::-1]
        nz = np.nonzero(row > 0.02)[0]
        if len(nz) == 0:
            continue
        i0 = int(nz[0])
        j = i0
        while j < w and row[j] < 0.98:
            j += 1
        if j >= w or j - i0 > 6:      # rampe trop longue = bord quasi horizontal, non exploitable
            continue
        out[y] = i0 + float(np.sum(1.0 - row[i0:j]))
    return out


SLOPE_LO = 0.30      # px de bord par ligne : en dessous, le bord est quasi VERTICAL — il n'a pas
SLOPE_HI = 3.00      # d'escalier a montrer. Au-dessus, il est quasi HORIZONTAL et la position
                     # sous-pixel n'y est plus definie ligne par ligne.


def dentelure(a, mask=None):
    """(RMS de la derivee seconde du bord, en px), (nombre de MARCHES : |d2| > 0,5 px),
    (nombre de lignes retenues), et le masque des lignes retenues.

    NATURE : une COURBURE de bord, pas une amplitude. REPERE : la grille de l'atlas, en pixels.
    CE QU'ELLE LIT QUAND LE DEFAUT EST ABSENT : 0 pour un bord rectiligne, quelle que soit sa
    pente. CE QU'ELLE LIT QUAND IL EST PRESENT : ~1 px par marche.

    POPULATION RESTREINTE AUX BORDS REELLEMENT OBLIQUES, et c'est ce qui rend la mesure lisible.
    Un bord vertical n'a pas d'escalier a montrer ; un bord horizontal n'a pas de position
    sous-pixel definie par ligne ; et un COIN produit une derivee seconde enorme qui n'a rien a
    voir avec la dentelure. On ne garde donc que les lignes ou la pente locale du bord est entre
    SLOPE_LO et SLOPE_HI px/ligne DES DEUX COTES. `mask` permet d'imposer EXACTEMENT la meme
    population aux deux colonnes de l'ablation : sans lui, les deux chemins choisiraient des
    lignes differentes et l'ecart ne voudrait plus rien dire."""
    vals, steps, n = [], 0, 0
    keep = {}
    for side in (-1, +1):
        e = _edge_positions(a, side)
        for y in range(1, len(e) - 1):
            if np.isnan(e[y - 1]) or np.isnan(e[y]) or np.isnan(e[y + 1]):
                continue
            s1 = abs(e[y] - e[y - 1])
            s2 = abs(e[y + 1] - e[y])
            own = (SLOPE_LO <= s1 <= SLOPE_HI) and (SLOPE_LO <= s2 <= SLOPE_HI)
            keep[(side, y)] = own
            if mask is not None:
                if not mask.get((side, y), False):
                    continue
            elif not own:
                continue
            d2 = e[y + 1] - 2 * e[y] + e[y - 1]
            vals.append(d2 * d2)
            n += 1
            if abs(d2) > 0.5:
                steps += 1
    if not vals:
        return 0.0, 0, 0, keep
    return float(np.sqrt(np.mean(vals))), steps, n, keep


def main():
    os.makedirs(os.path.dirname(OUT_TXT), exist_ok=True)
    emit("# Gloading-screen — atlas precurseur VECTORISE, .autoport/mk_precursor_atlas.py")
    emit("TRACEUR=potrace (portage python `potracer` %s) alphamax=%.3f opttolerance=%.2f "
         "turdsize=%d  SUB=%d  SS=%d"
         % (getattr(potrace, "name", "?"), ALPHAMAX, OPTTOLERANCE, max(2, SUB * SUB // 4), SUB, SS))
    cov = coverage_from_plate()
    boxes = segment(cov)
    emit("GLYPHES_DETECTES=%d" % len(boxes))
    if len(boxes) != 26:
        raise SystemExit("ERREUR: %d glyphes detectes, 26 attendus" % len(boxes))

    atlas = np.zeros((ATLAS_PX, ATLAS_PX), dtype=np.float64)
    em_px = EM_SRC * UPSCALE
    glyphs = []
    d_before, d_after, iou = [], [], []
    s_before, s_after = 0, 0
    n_before, n_after = 0, 0
    tot_curves, tot_segs, amin_all = 0, 0, 180.0

    for i, box in enumerate(boxes):
        ramp = resample_ramp(cov, box)
        a, ncur, nseg, amin = vectorize_glyph(cov, box)
        tot_curves += ncur
        tot_segs += nseg
        amin_all = min(amin_all, amin)

        # MEME POPULATION DE LIGNES POUR LES DEUX COLONNES : on l'etablit sur le temoin, puis on
        # l'IMPOSE au chemin livre. C'est ce qui fait de la comparaison une ablation.
        _, _, _, keep = dentelure(ramp)
        rb, sb, nb, _ = dentelure(ramp, keep)
        ra, sa, na, _ = dentelure(a, keep)
        d_before.append(rb)
        d_after.append(ra)
        s_before += sb
        s_after += sa
        n_before += nb
        n_after += na
        # CONTROLE DE FORME : recouvrement entre le temoin et le trace, sur la meme grille.
        # Un traceur qui aurait arrondi ou deforme le glyphe le ferait CHUTER. C'est le controle
        # negatif de la vectorisation : sans lui, « moins dentele » pourrait vouloir dire
        # « moins ressemblant ».
        hh = min(ramp.shape[0], a.shape[0])
        ww = min(ramp.shape[1], a.shape[1])
        A = ramp[:hh, :ww] >= 0.5
        B = a[:hh, :ww] >= 0.5
        inter = float((A & B).sum())
        union = float((A | B).sum())
        iou.append(inter / union if union else 1.0)

        # recadrage serre sur l'encre tracee (la rasterisation peut laisser une ligne vide)
        ys = np.where((a > 0.02).any(axis=1))[0]
        xs = np.where((a > 0.02).any(axis=0))[0]
        a = a[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1]

        gh, gw = a.shape
        if gw > CELL - 16 or gh > CELL - 16:
            raise SystemExit("ERREUR: glyphe %s (%dx%d) plus grand que la cellule %d"
                             % (LETTERS[i], gw, gh, CELL))
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        # marge de 8 px dans la cellule : evite que les mipmaps de l'atlas melangent deux glyphes
        ox, oy = cx + 8, cy + 8
        atlas[oy:oy + gh, ox:ox + gw] = a
        # PLACEMENT VERTICAL : glyphe CENTRE dans une boite d'em COMMUNE (les glyphes de la
        # planche sont centres dans leur bande a 4 % pres). Aligner les SOMMETS ferait sautiller
        # les glyphes courts au-dessus des longs.
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
            "contours": ncur,
        })

    img = Image.fromarray(np.round(atlas * 255.0).astype(np.uint8), mode="L")
    img.save(OUT_ATLAS)
    hist = img.histogram()
    mid = sum(hist[9:248])
    emit("ATLAS_OUT=%s %dx%d L" % (OUT_ATLAS, ATLAS_PX, ATLAS_PX))
    emit("ATLAS_EM_PX=%d  (planche source : %d — facteur %d)" % (int(em_px), int(EM_SRC), UPSCALE))
    emit("ATLAS_LARGEUR_GLYPHE_MIN=%d MAX=%d" % (min(g["w"] for g in glyphs),
                                                 max(g["w"] for g in glyphs)))
    emit("ATLAS_PIXELS_ANTIALIASES=%d" % mid)
    emit("CONTOURS_TRACES=%d  SEGMENTS=%d  (moyenne %.1f contours et %.1f segments par glyphe)"
         % (tot_curves, tot_segs, tot_curves / 26.0, tot_segs / 26.0))
    emit("ANGLE_LE_PLUS_AIGU_CONSERVE=%.1f degres  (controle que alphamax=%.2f n'arrondit pas les "
         "coins : s'il montait vers 180, la forme serait detruite)" % (amin_all, ALPHAMAX))
    emit("RECOUVREMENT_AVEC_LE_TEMOIN min=%.4f moyen=%.4f  (intersection/union des deux masques "
         "a 0,5, glyphe par glyphe. CONTROLE NEGATIF DE LA VECTORISATION : « moins dentele » ne "
         "doit pas vouloir dire « moins ressemblant »)" % (min(iou), float(np.mean(iou))))

    # --- L'ABLATION : meme glyphes, meme em, deux chemins ---
    emit("")
    emit("DENTELURE — derivee seconde de la position SOUS-PIXEL du bord, en pixels d'atlas.")
    emit("  AVANT (rampe de champ de distance, le chemin du 2026-08-29) :")
    emit("    RMS_moyen=%.4f px   RMS_max=%.4f px (glyphe %s)   MARCHES=%d sur %d lignes de bord "
         "(%.2f %%)"
         % (float(np.mean(d_before)), float(np.max(d_before)),
            LETTERS[int(np.argmax(d_before))], s_before, n_before,
            100.0 * s_before / max(1, n_before)))
    emit("  APRES (contours potrace rasterises) :")
    emit("    RMS_moyen=%.4f px   RMS_max=%.4f px (glyphe %s)   MARCHES=%d sur %d lignes de bord "
         "(%.2f %%)"
         % (float(np.mean(d_after)), float(np.max(d_after)),
            LETTERS[int(np.argmax(d_after))], s_after, n_after,
            100.0 * s_after / max(1, n_after)))
    for slope in (0.5, 1.0, 2.0):
        W = H = 200
        poly = [(20, 0), (20 + slope * H, H), (180, H), (180, 0), (20, 0)]
        fr, fs, fn, _ = dentelure(_rasterize([poly], W, H))
        emit("  PLANCHER DE L'INSTRUMENT (droite oblique PARFAITE, pente %.1f, meme rasteriseur) : "
             "RMS=%.4f px  MARCHES=%d/%d (%.2f %%)" % (slope, fr, fs, fn, 100.0 * fs / max(1, fn)))
    emit("  FACTEUR RMS=%.2f   FACTEUR MARCHES=%.2f"
         % (float(np.mean(d_before)) / max(1e-9, float(np.mean(d_after))),
            (s_before / max(1, n_before)) / max(1e-9, s_after / max(1, n_after))))
    emit("  Les vrais COINS des glyphes comptent dans LES DEUX colonnes : ils ne peuvent pas "
         "expliquer l'ecart, seulement le borner par le bas.")

    with open(OUT_JSON, "w") as f:
        json.dump({
            "size_px": int(em_px),
            "atlas": [ATLAS_PX, ATLAS_PX],
            "count": 26,
            "upscale": UPSCALE,
            "tracer": "potrace(potracer) alphamax=%.3f opttolerance=%.2f sub=%d" % (
                ALPHAMAX, OPTTOLERANCE, SUB),
            "note": ("Encre=255, fond=0. Polarite determinee UNE FOIS depuis la planche "
                     "(encre sombre sur fond clair), jamais par glyphe. Contours VECTORISES par "
                     "potrace sur l'isoligne sous-pixel de la couverture antialiasee, puis "
                     "rasterises (couverture exacte en x, %d sous-lignes en y). "
                     "Avance = largeur + %.2f x em, CONVENTION reglable. `by` = decalage "
                     "vertical depuis le haut de la boite d'em, glyphe CENTRE." % (SS, ADV_PAD_EM)),
            "glyphs": glyphs,
        }, f, indent=1)
    emit("JSON_OUT=%s" % OUT_JSON)

    # planche de controle : les 26 glyphes a la suite, blanc sur noir
    ph = 320
    pw = sum(int(g["w"] * ph / float(g["h"])) + 8 for g in glyphs)
    proof = Image.new("L", (pw, ph + 16), 0)
    px = 4
    for g in glyphs:
        gw = int(g["w"] * ph / float(g["h"]))
        cell = img.crop((int(round(g["u0"] * ATLAS_PX)), int(round(g["v0"] * ATLAS_PX)),
                         int(round(g["u1"] * ATLAS_PX)), int(round(g["v1"] * ATLAS_PX))))
        proof.paste(cell.resize((gw, ph), Image.LANCZOS), (px, 8))
        px += gw + 8
    proof.save(OUT_PROOF)
    emit("PLANCHE_CONTROLE=%s %dx%d (26 glyphes, tous blancs sur noir)" % (OUT_PROOF, pw, ph + 16))

    with open(OUT_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
