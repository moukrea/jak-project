#!/usr/bin/env python3
"""Gloading-screen — la silhouette ANIMEE, depuis une capture en jeu de la course reelle.

Owner 2026-08-29 : « capturer cette animation in game (mets un fond vert ou whatever) en haute
resolution pour ensuite en faire une sequence d'images animees en haute definition ou toute
l'image extraite du fond vert est transformee en blanc plein (silhouette) ».

ENTREE  : les PNG de .autoport/gls_capture_silhouette.sh (Jak + Daxter, vue laterale, fond uni).
SORTIE  : recharged_assets/loading_jak.png -- une PLANCHE de COLS x ROWS cellules.

POURQUOI MAGENTA ET PAS VERT. Il faut separer le fond du SUJET, et le sujet porte du vert (les
cheveux de Jak) et de l'orange (Daxter) : sur un fond vert l'incrustation trouerait sa tete, et
elle le ferait EN SILENCE. Le magenta n'apparait ni sur l'un ni sur l'autre. La grandeur
d'incrustation est `min(r,b) - g`, qui vaut 255 sur le fond et ~0 sur toute matiere non magenta.
Le debordement de teinte sur les bords n'a aucune importance ici : le sujet devient un BLANC PLEIN,
seul l'alpha porte la forme.

POURQUOI UNE COMPOSANTE CONNEXE. La capture garde `merc` et `generic` allumes -- il le faut, Jak
et Daxter y sont dessines -- donc les AUTRES acteurs du niveau restent visibles (mesure : une
masse d'un decor lointain, a hauteur de taille). On ne garde que la composante connexe qui
contient le CENTRE DE L'IMAGE, et ce centre n'est pas un choix arbitraire : la camera orbite vise
la racine de Jak a chaque frame (cam-states-dbg.gc:377), donc le centre EST sur lui, par
construction. Le nombre de pixels ecartes est publie.
"""

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw

lines = []


def emit(s):
    print(s)
    lines.append(s)


def alpha_of(path):
    """Incrustation : `key = min(r,b) - g`. Le NIVEAU du fond est MESURE sur les quatre coins de
    l'image, jamais suppose : `bg-clear-color` est pose en composantes 0-255 et le magenta livre
    vaut (128,0,128), pas (255,0,255). Diviser par une constante ecrite en dur aurait rendu des
    alphas satures a mi-course sans que rien ne le signale."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    key = np.minimum(a[:, :, 0], a[:, :, 2]) - a[:, :, 1]
    kbg = float(np.median([key[2, 2], key[2, -3], key[-3, 2], key[-3, -3]]))
    if kbg < 32:
        return None            # image prise avant que le fond uni soit pose : ecartee, pas fatale
    return np.clip(1.0 - key / kbg, 0.0, 1.0)


def _components(mask):
    """Etiquetage des composantes connexes en 4-voisinage, par PLAGES (run-length) + union-find.

    Ecrit a la main parce que ni scipy, ni skimage, ni cv2 ne sont installes, et parce que
    `PIL.ImageDraw.floodfill` NE REMPLIT RIEN sous Pillow 12.2 (verifie sur un cas jouet de 10x10 :
    la sortie est identique a l'entree). Une composante lue avec cet outil aurait rendu un masque
    VIDE -- et le rendu, un ecran de chargement sans silhouette.

    Rend (labels, n) avec labels[y,x] = -1 hors du masque."""
    H, W = mask.shape
    runs = []
    row_runs = []
    for y in range(H):
        r = mask[y]
        if not r.any():
            row_runs.append([])
            continue
        d = np.diff(r.astype(np.int8))
        starts = (np.where(d == 1)[0] + 1).tolist()
        ends = (np.where(d == -1)[0] + 1).tolist()
        if r[0]:
            starts.insert(0, 0)
        if r[-1]:
            ends.append(W)
        idx = []
        for a, b in zip(starts, ends):
            idx.append(len(runs))
            runs.append((y, a, b))
        row_runs.append(idx)

    parent = list(range(len(runs)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for y in range(1, H):
        A, B = row_runs[y - 1], row_runs[y]
        i = j = 0
        while i < len(A) and j < len(B):
            _, sa, ea = runs[A[i]]
            _, sb, eb = runs[B[j]]
            if sa < eb and sb < ea:
                ra, rb = find(A[i]), find(B[j])
                if ra != rb:
                    parent[rb] = ra
            if ea <= eb:
                i += 1
            else:
                j += 1

    labels = np.full((H, W), -1, dtype=np.int32)
    for k, (y, a, b) in enumerate(runs):
        labels[y, a:b] = find(k)
    return labels


def isolate(alpha):
    """Ne garder que la composante connexe qui contient le centre, trous interieurs bouches.
    Rend (alpha_filtre, pixels_ecartes).

    POURQUOI LE CENTRE EST UN POINT LEGITIME ET PAS UN CHOIX ARBITRAIRE : la camera orbite
    recalcule sa cible a CHAQUE frame sur la racine de Jak (cam-states-dbg.gc:377), donc le centre
    de l'image est sur lui par construction, quelle que soit sa position dans le monde.

    ORDRE DES DEUX ETAPES, ET IL COMPTE. On bouche D'ABORD les trous (le fond qui n'est PAS relie
    au bord de l'image), on isole ENSUITE la composante du centre : l'inverse laisserait un trou
    interieur couper la silhouette en deux et on n'en garderait qu'une moitie. Le vide ENTRE LES
    JAMBES, lui, EST relie au bord et reste donc un vide -- c'est pour ca que le bouchage se fait
    par le bord, et non par une fermeture morphologique qui l'aurait comble."""
    core = (alpha >= 0.5)
    h, w = core.shape
    if not core.any():
        return alpha * 0.0, 0

    lab_bg = _components(~core)
    border = set(lab_bg[0].tolist()) | set(lab_bg[-1].tolist()) \
        | set(lab_bg[:, 0].tolist()) | set(lab_bg[:, -1].tolist())
    border.discard(-1)
    outside = np.isin(lab_bg, list(border)) if border else np.zeros_like(core)
    solid = core | ((~core) & ~outside)      # sujets + trous interieurs bouches
    holes = solid & ~core

    cy, cx = h // 2, w // 2
    if not solid[cy, cx]:
        ys, xs = np.where(solid)
        i = int(np.argmin((ys - cy) ** 2 + (xs - cx) ** 2))
        cy, cx = int(ys[i]), int(xs[i])
    lab = _components(solid)
    keep = lab == lab[cy, cx]

    out = np.where(keep, np.maximum(alpha, holes.astype(np.float64)), 0.0)
    # BLANC PLEIN. L'owner demande que « toute l'image extraite du fond soit transformee en blanc
    # PLEIN ». L'incrustation, elle, rend une couverture continue : les parties du sujet dont la
    # teinte s'approche du fond ressortent a 0,6-0,9 et la silhouette est alors GRISE par plaques
    # (mesure : 12 530 pixels sur 115 549, soit 10,8 %, sous 0,9). On redresse donc la couverture
    # a 1 des qu'elle depasse le seuil, en ne laissant la rampe que sur la bande de bord — ce qui
    # donne un aplat blanc avec un contour antialiase d'un pixel, exactement le livrable demande.
    out = np.clip((out - 0.35) / 0.30, 0.0, 1.0)
    return out, int((core & ~keep).sum())


def period(alphas, lo, hi):
    """Periode du cycle, MESUREE : le decalage qui minimise l'ecart moyen |a(f) - a(f+P)|.
    On ne postule pas les 60 frames de `*TARGET-bank* run-cycle-length` -- on les verifie."""
    n = len(alphas)
    tbl = []
    for p in range(lo, min(hi, n - 8) + 1):
        d = float(np.mean([np.abs(alphas[f] - alphas[f + p]).mean() for f in range(0, n - p, 2)]))
        tbl.append((p, d))
    tbl.sort(key=lambda t: t[1])
    emit("PERIODE_MESUREE=%d  ecart=%.5f   (5 meilleurs : %s)"
         % (tbl[0][0], tbl[0][1], " ".join("%d:%.5f" % t for t in tbl[:5])))
    return tbl[0][0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True)
    ap.add_argument("--skip", type=int, default=20, help="images ignorees en tete (mise en place)")
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--cell", type=int, default=512)
    ap.add_argument("--step", type=int, default=2, help="frames de logique entre deux cellules")
    ap.add_argument("--out", default="recharged_assets/loading_jak.png")
    ap.add_argument("--report", default=".autoport/reports/Gloading-screen/silhouette.txt")
    ap.add_argument("--mirror", action="store_true",
                    help="miroir horizontal : l'owner demande une course vers la DROITE, et "
                         "l'angle de camera qui ecarte le decor du niveau donne une course vers "
                         "la gauche. Un miroir d'une silhouette est exact — aucune information "
                         "n'est inventee, seul le cote de l'epaule de Daxter change.")
    a = ap.parse_args()
    frames = a.cols * a.rows

    fs = sorted(glob.glob(os.path.join(a.shots, "autoport_f*.png")))[a.skip:a.skip + a.count]
    if len(fs) < frames * 2:
        raise SystemExit("ERREUR: %d captures, il en faut au moins %d" % (len(fs), frames * 2))
    emit("CAPTURES=%d  premiere=%s derniere=%s"
         % (len(fs), os.path.basename(fs[0]), os.path.basename(fs[-1])))
    im0 = Image.open(fs[0])
    emit("RESOLUTION_CAPTURE=%dx%d" % im0.size)

    alphas, dropped, ecartees = [], 0, 0
    for f in fs:
        raw = alpha_of(f)
        if raw is None:
            ecartees += 1
            continue
        if a.mirror:
            raw = raw[:, ::-1].copy()
        al, d = isolate(raw)
        dropped += d
        alphas.append(al)
    emit("IMAGES_SANS_FOND_UNI_ECARTEES=%d  (prises avant que la mise en scene soit posee)" % ecartees)
    emit("MIROIR=%s" % ("oui" if a.mirror else "non"))
    if len(alphas) < frames * 2:
        raise SystemExit("ERREUR: %d images exploitables, il en faut %d" % (len(alphas), frames * 2))
    emit("PIXELS_ECARTES_HORS_COMPOSANTE=%d sur %d (%.4f %%) — autres acteurs du niveau"
         % (dropped, len(fs) * alphas[0].size, 100.0 * dropped / (len(fs) * alphas[0].size)))
    cov = [float((x >= 0.5).sum()) for x in alphas]
    emit("SURFACE_SUJET min=%d max=%d median=%d px" % (min(cov), max(cov), int(np.median(cov))))

    # PAS ENTIER ENTRE CELLULES. Avec 16 cellules sur une periode de 30 frames l'ecart tombe a
    # 1,875 frame : arrondi, il donne des cellules a 2 et d'autres a 1 frame d'intervalle, donc une
    # boucle qui accelere et ralentit. On impose donc `step` frames ENTIERES entre cellules ; la
    # periode livree vaut `step x cellules`.
    p_mes = period(alphas, 20, 80)
    p = a.step * frames
    seams = []
    for s0 in range(0, len(alphas) - p - 1):
        seams.append((float(np.abs(alphas[s0] - alphas[s0 + p]).mean()), s0))
    seams.sort()
    s0 = seams[0][1]
    emit("PERIODE_LIVREE=%d frames (%d cellules x %d)  RACCORD_ecart=%.5f  depart=%d  "
         "(pire raccord possible sur la meme fenetre : %.5f)"
         % (p, frames, a.step, seams[0][0], s0, seams[-1][0]))
    picks = [s0 + k * a.step for k in range(frames)]
    emit("IMAGES_CHOISIES=%s" % picks)
    chosen = [alphas[i] for i in picks]

    # BOITE COMMUNE : la silhouette ne doit pas changer de taille d'une image a l'autre. La camera
    # orbite garde Jak centre sur sa RACINE, donc le ballant du corps est CONSERVE -- il ne faut
    # surtout pas normaliser image par image, ce serait supprimer le mouvement qu'on capture.
    ys, xs = [], []
    for m in chosen:
        wgt = np.where(m > 0.35)
        if len(wgt[0]) == 0:
            raise SystemExit("ERREUR: image vide (incrustation ratee ?)")
        ys += [wgt[0].min(), wgt[0].max()]
        xs += [wgt[1].min(), wgt[1].max()]
    y0, y1, x0, x1 = int(min(ys)), int(max(ys)) + 1, int(min(xs)), int(max(xs)) + 1
    pad = int(0.04 * max(y1 - y0, x1 - x0))
    H, W = chosen[0].shape
    y0 = max(0, y0 - pad); x0 = max(0, x0 - pad)
    y1 = min(H, y1 + pad); x1 = min(W, x1 + pad)
    bw, bh = x1 - x0, y1 - y0
    emit("BOITE_COMMUNE=(%d,%d,%d,%d) %dx%d rapport_l/h=%.4f" % (x0, y0, x1, y1, bw, bh, bw / float(bh)))

    # Cellule CARREE, sujet inscrit avec une marge transparente. La marge n'est pas cosmetique :
    # sans elle le filtrage bilineaire et les mipmaps de la planche melangeraient deux images
    # voisines.
    inner = int(a.cell * 0.94)
    if bw >= bh:
        tw, th = inner, max(1, int(round(inner * bh / float(bw))))
    else:
        th, tw = inner, max(1, int(round(inner * bw / float(bh))))
    ox, oy = (a.cell - tw) // 2, (a.cell - th) // 2
    emit("CELLULE=%dx%d sujet=%dx%d marge=(%d,%d) hauteur_sujet/cellule=%.4f"
         % (a.cell, a.cell, tw, th, ox, oy, th / float(a.cell)))

    sheet = Image.new("RGBA", (a.cols * a.cell, a.rows * a.cell), (255, 255, 255, 0))
    for k, m in enumerate(chosen):
        crop = Image.fromarray(np.round(m[y0:y1, x0:x1] * 255).astype(np.uint8), mode="L")
        crop = crop.resize((tw, th), Image.LANCZOS)
        # BLANC PLEIN : seul l'alpha porte la forme.
        cell = Image.merge("RGBA", (Image.new("L", (tw, th), 255),
                                    Image.new("L", (tw, th), 255),
                                    Image.new("L", (tw, th), 255), crop))
        sheet.paste(cell, ((k % a.cols) * a.cell + ox, (k // a.cols) * a.cell + oy))
    sheet.save(a.out)
    emit("PLANCHE=%s %dx%d  images=%d (%d x %d cellules de %d px)"
         % (a.out, sheet.size[0], sheet.size[1], frames, a.cols, a.rows, a.cell))
    emit("BOUCLE_FRAMES_LOGIQUE=%d  BOUCLE_SECONDES=%.4f  (pas de temps FORCE a 1/60 s par le "
         "rejeu de manette, pad_replay.cpp:313-318 — la duree ne depend donc pas du debit "
         "d'images de la capture ; periode MESUREE independamment : %d frames)"
         % (p, p / 60.0, p_mes))
    emit("LS_SIL_H_A_POSER=%.6f  (pour que le SUJET fasse 0,612115 de la hauteur d'ecran comme la "
         "maquette, la CELLULE doit en faire 0,612115 / %.4f)" % (0.612115 * a.cell / float(th), th / float(a.cell)))

    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    open(a.report, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
