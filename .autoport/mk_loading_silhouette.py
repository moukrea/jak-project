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
import re

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


def period_images(alphas, lo, hi):
    """Periode du cycle MESUREE SUR LES IMAGES : le decalage qui minimise l'ecart moyen
    |a(f) - a(f+P)|. Second instrument, INDEPENDANT de la trace du moteur -- les deux doivent
    tomber d'accord, sinon on ne livre rien.

    LA FENETRE DE RECHERCHE NE DOIT PAS BORNER LA REPONSE. Le cycle precedent cherchait dans
    [20, 80] et a rendu 20 avec une erreur STRICTEMENT CROISSANTE sur les cinq meilleurs : le
    minimum etait hors fenetre, en dessous. On cherche donc a partir de 6, et on REFUSE un
    resultat qui tombe sur une borne."""
    n = len(alphas)
    hi = min(hi, n - 8)
    tbl = []
    for q in range(lo, hi + 1):
        d = float(np.mean([np.abs(alphas[f] - alphas[f + q]).mean() for f in range(0, n - q, 2)]))
        tbl.append((q, d))
    tbl.sort(key=lambda t: t[1])
    emit("PERIODE_IMAGES=%d  ecart=%.5f  fenetre=[%d,%d]  (5 meilleurs : %s)"
         % (tbl[0][0], tbl[0][1], lo, hi, " ".join("%d:%.5f" % t for t in tbl[:5])))
    if tbl[0][0] in (lo, hi):
        raise SystemExit("ERREUR: la periode mesuree tombe sur une BORNE de la fenetre (%d) — "
                         "le minimum est dehors, le resultat ne veut rien dire." % tbl[0][0])
    return tbl[0][0]


NUMBER = r"[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?"


def parse_trace(path):
    """Apparier chaque CAPTURE a l'ETAT DU MOTEUR de la frame ou elle a ete prise.

    Le cycle precedent a monte une planche sans jamais savoir ce que Jak faisait : `grep -c ANIM`
    sur son log rend ZERO. Ici, `ls-capture-trace` publie trois lignes par frame (CAPFRAME /
    CAPRUN / CAPVUE) et le crochet de capture publie `AUTOPORT-SHOT f=`, sur le MEME flux. On
    associe donc a chaque PNG l'etat de la derniere frame tracee avant elle.

    RESERVE DECLAREE : le renderer dessine la frame que GOAL vient de finir, donc l'appariement
    peut etre decale d'UNE frame. Toutes les grandeurs qu'on en tire (melange, sens, periode)
    varient lentement ou pas du tout sur une frame ; aucune decision ici ne depend de ce bit."""
    # `cur` est la frame EN COURS d'assemblage, `last` la derniere COMPLETE. Une capture
    # s'apparie a `last`, jamais a `cur` : les trois lignes de la trace sont ecrites par le thread
    # GOAL et la ligne de capture par le thread de rendu, donc une capture peut tomber AU MILIEU
    # d'un triplet. S'y appuyer perdrait des captures et fragmenterait la plage de course
    # continue, qui est precisement ce qu'on cherche.
    rec, cur, last, out = {}, {}, None, {}
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            m = re.search(r"CAPFRAME afc=(\d+) marche=(\S+) f=(%s) len=(\d+)" % NUMBER, line)
            if m:
                cur = {"afc": int(m.group(1)), "walk": m.group(2),
                       "fwalk": float(m.group(3)), "lenwalk": int(m.group(4))}
                continue
            m = re.search(r"CAPRUN course=(\S+) f=(%s) len=(\d+) melange=(%s) v=(%s)"
                          % (NUMBER, NUMBER, NUMBER), line)
            if m and cur:
                cur.update(run=m.group(1), frun=float(m.group(2)), lenrun=int(m.group(3)),
                           blend=float(m.group(4)), v=float(m.group(5)))
                continue
            m = re.search(r"CAPVUE sx=(%s) dx=(%s) camy-jaky=(%s) fov=(%s)"
                          % (NUMBER, NUMBER, NUMBER, NUMBER), line)
            if m and cur:
                cur.update(sx=float(m.group(1)), dx=float(m.group(2)),
                           camy=float(m.group(3)), fov=float(m.group(4)))
                rec[cur["afc"]] = dict(cur)
                last = dict(cur)
                continue
            m = re.search(r"AUTOPORT-SHOT f=(\d+)", line)
            if m and last is not None:
                out[int(m.group(1))] = dict(last)
    return out


def period_from_anim(states):
    """Periode du cycle de course LUE SUR L'ANIMATION, en frames de logique.

    `frun` est le numero de frame du canal 3 (`eichar-run-ja`), qui boucle sur `lenrun-1`
    (num-func-loop!, process-drawable-h.gc:46-55). On mesure donc la periode par la PENTE de ce
    numero : nombre de frames de logique pour consommer `lenrun-1` frames d'animation. C'est la
    grandeur que le moteur lui-meme utilise, et elle ne depend d'aucun pixel."""
    ks = sorted(states)
    d, n = 0.0, 0
    for a, b in zip(ks, ks[1:]):
        if b - a != 1:
            continue
        step = states[b]["frun"] - states[a]["frun"]
        if step > 0:                      # on saute l'enroulement
            d += step
            n += 1
    if n == 0:
        raise SystemExit("ERREUR: la trace ne contient aucune paire de frames consecutives")
    per_frame = d / n
    length = states[ks[0]]["lenrun"]
    P = (length - 1) / per_frame
    emit("PERIODE_ANIMATION=%.2f frames de logique  (anim=%s longueur=%d frames, avance=%.4f "
         "frame d'anim par frame de logique, sur %d paires)"
         % (P, states[ks[0]]["run"], length, per_frame, n))
    return P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True)
    ap.add_argument("--trace", required=True,
                    help="log de la course de capture : c'est lui qui dit ce que Jak faisait")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--cell", type=int, default=512)
    ap.add_argument("--blend-min", type=float, default=0.99,
                    help="melange marche/course minimal. 1,0 = course PURE. jak1 n'a qu'un etat "
                         "de locomotion au sol et empile marche (canal 0) et course (canal 3) ; "
                         "le canal 6 porte le melange (target.gc:578). En dessous de ce seuil, "
                         "ce n'est PAS l'animation de course que l'owner demande.")
    ap.add_argument("--out", default="recharged_assets/loading_jak.png")
    ap.add_argument("--report", default=".autoport/reports/Gloading-screen/silhouette.txt")
    a = ap.parse_args()
    frames = a.cols * a.rows

    states = parse_trace(a.trace)
    emit("TRACE=%s  captures appariees a un etat du moteur=%d" % (a.trace, len(states)))
    if not states:
        raise SystemExit("ERREUR: aucune ligne CAPFRAME/AUTOPORT-SHOT appariee — l'instrument "
                         "*ls-capture-trace* n'a pas ete allume, ou la capture n'a rien ecrit.")

    # --- LA FENETRE : la plus longue suite de captures CONSECUTIVES en course PURE ---
    # Le defaut du cycle precedent n'etait pas le montage, c'est qu'on a monte des images ou Jak
    # ne courait pas. On ne choisit donc plus « les 200 dernieres » : on choisit la plus longue
    # plage ou le MELANGE est plein, et on publie sa taille.
    ks = sorted(states)
    best, cur = [], []
    for i, k in enumerate(ks):
        ok = states[k]["blend"] >= a.blend_min
        cont = ok and (not cur or k - cur[-1] == 1)
        cur = (cur + [k]) if cont else ([k] if ok else [])
        if len(cur) > len(best):
            best = list(cur)
    emit("MELANGE_MIN_EXIGE=%.2f  plage de course PURE la plus longue=%d captures consecutives "
         "(sur %d)" % (a.blend_min, len(best), len(states)))
    if len(best) < frames * 3:
        raise SystemExit("ERREUR: seulement %d captures consecutives en course pure, il en faut "
                         "au moins %d. Jak n'a pas couru assez longtemps." % (len(best), frames * 3))
    vv = [states[k]["v"] for k in best]
    dxs = [states[k]["dx"] for k in best]
    emit("VITESSE sur la plage : min=%.0f med=%.0f max=%.0f  (course pure au-dessus de 36864, "
         "marche pure sous 16384 — target.gc:556-559)" % (min(vv), float(np.median(vv)), max(vv)))
    emit("SENS_ECRAN dx min=%.1f max=%.1f  (dx>0 = il court vers la DROITE de l'ecran ; grandeur "
         "projetee par la matrice de camera du moteur, pas deduite d'un signe)"
         % (min(dxs), max(dxs)))
    emit("FOCALE=%.1f degres GOAL  ELEVATION_CAMERA=%.0f unites au-dessus de la racine de Jak"
         % (states[best[0]]["fov"] / 182.044, states[best[0]]["camy"]))
    mirror = float(np.median(dxs)) < 0.0
    emit("MIROIR=%s  (DECIDE PAR LA MESURE `dx`, plus par un drapeau pose a la main — c'est un "
         "miroir injustifie qui produisait le « ca va vers la gauche » du cycle precedent)"
         % ("oui" if mirror else "non"))

    fs = []
    for k in best:
        f = os.path.join(a.shots, "autoport_f%06d.png" % k)
        if os.path.exists(f):
            fs.append((k, f))
    emit("CAPTURES=%d  premiere=%s derniere=%s"
         % (len(fs), os.path.basename(fs[0][1]), os.path.basename(fs[-1][1])))
    im0 = Image.open(fs[0][1])
    emit("RESOLUTION_CAPTURE=%dx%d" % im0.size)

    alphas, keys, dropped, ecartees = [], [], 0, 0
    for k, f in fs:
        raw = alpha_of(f)
        if raw is None:
            ecartees += 1
            continue
        if mirror:
            raw = raw[:, ::-1].copy()
        al, d = isolate(raw)
        dropped += d
        alphas.append(al)
        keys.append(k)
    emit("IMAGES_SANS_FOND_UNI_ECARTEES=%d" % ecartees)
    if len(alphas) < frames * 3:
        raise SystemExit("ERREUR: %d images exploitables, il en faut %d" % (len(alphas), frames * 3))
    emit("PIXELS_ECARTES_HORS_COMPOSANTE=%d sur %d (%.4f %%) — autres acteurs du niveau"
         % (dropped, len(alphas) * alphas[0].size, 100.0 * dropped / (len(alphas) * alphas[0].size)))
    cov = [float((x >= 0.5).sum()) for x in alphas]
    emit("SURFACE_SUJET min=%d max=%d median=%d px  (variation %.1f %% — une variation forte "
         "signale un sujet coupe par le bord ou une composante parasite)"
         % (min(cov), max(cov), int(np.median(cov)), 100.0 * (max(cov) - min(cov)) / np.median(cov)))

    # --- DEUX INSTRUMENTS POUR LA PERIODE, ET ILS DOIVENT S'ACCORDER ---
    p_anim = period_from_anim({k: states[k] for k in keys})
    p_img = period_images(alphas, 6, min(120, len(alphas) - 9))
    ecart = abs(p_img - p_anim) / p_anim
    # Une silhouette vue de cote se repete PRESQUE a la demi-foulee (les deux jambes donnent un
    # contour voisin) : l'instrument d'IMAGES peut donc legitimement trouver P/2. On l'accepte
    # explicitement, on ne le confond pas avec un accord.
    demi = abs(p_img - p_anim / 2.0) / (p_anim / 2.0)
    emit("ACCORD_PERIODES ecart_a_P=%.1f %%  ecart_a_P/2=%.1f %%" % (100 * ecart, 100 * demi))
    if min(ecart, demi) > 0.15:
        raise SystemExit("ERREUR: les deux instruments de periode ne s'accordent ni sur P ni sur "
                         "P/2 (%.2f contre %.2f) — on ne livre pas une boucle non etablie."
                         % (p_img, p_anim))
    emit("PERIODE_RETENUE=%.2f frames de logique — celle de l'ANIMATION. Une silhouette laterale "
         "se repete presque a la demi-foulee, donc boucler sur P/2 ferait sauter la jambe la plus "
         "proche : la boucle DOIT porter la foulee ENTIERE." % p_anim)

    # --- LES CELLULES COUVRENT EXACTEMENT UNE PERIODE ---
    # Le cycle precedent imposait un pas ENTIER (16 cellules x 2 = 32 frames) et livrait donc une
    # boucle de 32 frames pour une periode de ~37 : le raccord sautait par construction. On place
    # la cellule k a round(k.P/N) : les pas valent alors 2 ou 3 frames, l'ecart de cadence est de
    # moins d'une demi-frame (8 ms) et la boucle se referme EXACTEMENT.
    P = p_anim
    span = int(round(P))
    starts = range(0, len(alphas) - span - 1)
    seams = sorted((float(np.abs(alphas[s] - alphas[s + span]).mean()), s) for s in starts)
    s0 = seams[0][1]
    picks = [s0 + int(round(k * P / frames)) for k in range(frames)]
    emit("PERIODE_LIVREE=%.2f frames (%d cellules, pas moyen %.2f)  RACCORD_ecart=%.5f  depart=%d"
         "  (pire raccord possible sur la meme fenetre : %.5f)"
         % (P, frames, P / frames, seams[0][0], s0, seams[-1][0]))
    emit("IMAGES_CHOISIES=%s" % [keys[i] for i in picks])
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
    # OU PASSE L'AXE OPTIQUE DANS LE SUJET. La camera vise la racine de Jak + `target-off y`, et
    # ce point tombe exactement au centre de l'image. Publier sa position DANS la boite du sujet
    # dit si le corps est vu de face ou en contre-plongee/plongee locale : a 50 % la deformation
    # de perspective est symetrique haut/bas, c'est le cadrage d'un profil. Le cycle precedent
    # etait a 65 % (l'axe visait les hanches) et l'owner a parle d'« angle bizarre ».
    axe = 100.0 * (H / 2.0 - y0) / float(bh)
    emit("AXE_OPTIQUE_DANS_LE_SUJET=%.1f %% depuis le haut (50 %% = profil centre)" % axe)

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
         "d'images de la capture)" % (span, span / 60.0))
    emit("LS_SIL_PERIOD_A_POSER=%d  (en FRAMES DE LOGIQUE a 60 Hz. `LS_SIL_PERIOD` s'exprime "
         "dans l'unite de `loading-screen-clock`, le 1/300 s : la conversion x5 est faite par "
         ".autoport/gls_apply_silhouette_constants.py et NULLE PART AILLEURS, pour qu'il n'y ait "
         "qu'un seul endroit ou la perdre. Valeur posee : %d)" % (span, span * 5))
    emit("LS_SIL_H_A_POSER=%.6f  (pour que le SUJET fasse 0,612115 de la hauteur d'ecran comme la "
         "maquette, la CELLULE doit en faire 0,612115 / %.4f)" % (0.612115 * a.cell / float(th), th / float(a.cell)))

    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    open(a.report, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
