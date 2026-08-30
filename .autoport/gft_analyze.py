#!/usr/bin/env python3
"""Gfixed-tick-interpolation — depouillement des courses x86.

DEUX grandeurs, DEUX instruments, et ils ne mesurent pas la meme chose :

1. TRAJECTOIRE DE SAUT — lue dans la trace `pad_replay` (« CAM frame= »), une ligne par
   TICK DE LOGIQUE. C'est la position que le moteur a REELLEMENT ecrite pour Jak, pas
   une reconstruction. Deux courses au meme etat de depart et aux memes entrees doivent
   rendre la meme trajectoire ; si elles different, c'est le pas de temps qui a change
   la physique.

2. JUDDER DE CAMERA — lu dans les lignes « GFT n= » du journal gk, une par image
   DESSINEE. Le lacet publie est celui que le RENDU a consomme (la sonde est posee
   apres `cam-render-interp!` et apres la construction de la chaine DMA). Le judder est
   la dispersion de la DERIVEE SECONDE de ce lacet : une camera qui tourne a vitesse
   constante a une derivee seconde nulle ; ce qui se voit a l'ecran, ce sont ses sauts.
   On ne le mesure que pendant une rotation reelle, sinon on mesure du bruit sur zero.

CE QUE CHAQUE MESURE LIT QUAND LE DEFAUT EST ABSENT : trajectoires identiques au bit
entre framerates, et derivee seconde du lacet a dispersion nulle.
"""

import argparse
import math
import os
import re
import struct
import sys

METER = 4096.0


def parse_trace(path):
    """-> {frame: (cam(3), yaw, jak(3))}"""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, "rb") as f:
        for raw in f:
            if not raw.startswith(b"CAM frame="):
                continue
            try:
                head, rest = raw.split(b" ", 2)[1], raw.split(b" ", 2)[2]
            except IndexError:
                continue
            fr = int(head.split(b"=")[1])
            hexs = rest.split()
            if len(hexs) < 92:
                continue
            b = bytes(int(h, 16) for h in hexs[:92])
            cam = struct.unpack_from("<3f", b, 0)
            fwd = struct.unpack_from("<3f", b, 48)  # camera-rot ligne 2 == avant
            jak = struct.unpack_from("<3f", b, 80)
            yaw = math.degrees(math.atan2(fwd[0], fwd[2]))
            out[fr] = (cam, yaw, jak)
    return out


def parse_gft(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, "rb") as f:
        for raw in f:
            if not raw.startswith(b"GFT n="):
                continue
            d = {}
            for tok in raw.decode("utf-8", "replace").split():
                if "=" in tok:
                    k, v = tok.split("=", 1)
                    d[k] = v
            try:
                rows.append({
                    "n": int(d["n"]), "lf": int(d["lf"]), "armed": int(d["armed"]),
                    "k": int(d["k"]), "alpha": int(d["alpha"]),
                    "dt_ms": float(d["dt_ms"]), "yaw": float(d["yaw"]),
                })
            except (KeyError, ValueError):
                continue
    return rows


def jump_metrics(tr, windows):
    """Par saut : apex (hauteur max au-dessus du point de decollage) et longueur au sol
    du DECOLLAGE a l'ATTERRISSAGE.

    L'atterrissage est detecte, pas suppose : premier tick APRES l'apex ou Jak est
    redescendu a moins de 2 cm au-dessus de son altitude de decollage. Prendre la fin de
    la fenetre a la place melangerait la distance de COURSE avec la distance de VOL, et
    les deux ne dependent pas du pas de temps de la meme facon."""
    res = []
    for (t0, t1) in windows:
        pts = [(f, tr[f][2]) for f in range(t0, t1 + 1) if f in tr]
        if len(pts) < 10:
            res.append(None)
            continue
        y0 = pts[0][1][1]
        ia = max(range(len(pts)), key=lambda i: pts[i][1][1])
        apex = pts[ia][1][1] - y0
        land = len(pts) - 1
        for i in range(ia + 1, len(pts)):
            if pts[i][1][1] <= y0 + 0.02 * METER:
                land = i
                break
        p0, p1 = pts[0][1], pts[land][1]
        length = math.hypot(p1[0] - p0[0], p1[2] - p0[2])
        res.append((apex, length, pts[land][0] - pts[0][0]))
    return res


def unwrap(ys):
    for i in range(1, len(ys)):
        while ys[i] - ys[i - 1] > 180.0:
            ys[i] -= 360.0
        while ys[i] - ys[i - 1] < -180.0:
            ys[i] += 360.0
    return ys


def judder(rows, lo, hi):
    """Judder = dispersion de la DERIVEE SECONDE du lacet, par image dessinee.

    Publie l'ecart-type ET la mediane de |d2|. L'ecart-type seul est domine par les
    COUPURES de camera (changement de plan, teleportation), qui ne sont pas du judder :
    la mediane les ignore et decrit ce qu'on voit pendant une rotation continue. On ne
    retient que les images ou la camera TOURNE vraiment (|d1| non nul), sinon on mesure
    du bruit sur zero."""
    ys = unwrap([r["yaw"] for r in rows[lo:hi]])
    if len(ys) < 16:
        return None
    d1 = [ys[i + 1] - ys[i] for i in range(len(ys) - 1)]
    d2 = [abs(d1[i + 1] - d1[i]) for i in range(len(d1) - 1)]
    # ne garder que les images ou la camera tourne (les deux pas encadrants non nuls)
    keep = [d2[i] for i in range(len(d2))
            if abs(d1[i]) > 1e-4 or abs(d1[i + 1]) > 1e-4]
    if len(keep) < 16:
        return None
    n = len(keep)
    m = sum(keep) / n
    sd = math.sqrt(sum((x - m) ** 2 for x in keep) / n)
    sk = sorted(keep)
    med = sk[n // 2]
    p95 = sk[int(0.95 * (n - 1))]
    am = sum(abs(x) for x in d1) / len(d1)
    return sd, med, p95, am, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".autoport/reports/Gfixed-tick-interpolation")
    ap.add_argument("--windows", default="410-560,670-820,930-1080")
    ap.add_argument("--legs", nargs="+", required=True)
    a = ap.parse_args()
    windows = [tuple(int(x) for x in w.split("-")) for w in a.windows.split(",")]

    print("== TRAJECTOIRE DE SAUT (trace pad_replay, une ligne par TICK de logique) ==")
    print("   apex = hauteur max au-dessus du point de decollage ; longueur = distance au sol")
    print("   %-18s %6s %7s   %s" % ("leg", "ticks", "", "sauts (apex m / longueur m / duree ticks)"))
    traj = {}
    for leg in a.legs:
        tr = parse_trace(os.path.join(a.dir, leg + ".trace"))
        traj[leg] = tr
        jm = jump_metrics(tr, windows)
        cells = []
        for j in jm:
            cells.append("--" if j is None else "%.4f/%.4f/%dt" % (j[0] / METER, j[1] / METER, j[2]))
        print("   %-18s %6d       %s" % (leg, len(tr), "  ".join(cells)))

    print()
    print("== ECART DE TRAJECTOIRE ENTRE LEGS (position de Jak, tick par tick) ==")
    ref = a.legs[0]
    for leg in a.legs[1:]:
        common = sorted(set(traj[ref]) & set(traj[leg]))
        if not common:
            print("   %-18s vs %-18s : AUCUN tick commun" % (leg, ref))
            continue
        worst = 0.0
        nbit = 0
        for f in common:
            p, q = traj[ref][f][2], traj[leg][f][2]
            d = math.dist(p, q)
            worst = max(worst, d)
            if p == q:
                nbit += 1
        print("   %-18s vs %-18s : %5d ticks communs, identiques au BIT %5d (%.1f %%), "
              "ecart max %.6f m" % (leg, ref, len(common), nbit, 100.0 * nbit / len(common),
                                    worst / METER))

    print()
    print("== CADENCE ET JUDDER DE CAMERA (journal gk, une ligne par IMAGE DESSINEE) ==")
    print("   dt = duree reelle d'une image (mediane, robuste aux hoquets de chargement)")
    print("   s_jeu/s_reel = secondes de JEU produites par seconde REELLE. 1.000 = le temps")
    print("      de jeu suit le temps reel. Au-dessus, le jeu accelere ; en dessous, il traine.")
    print("   |d1| moy = pas de lacet moyen par image ; d2 = judder (deg/image^2)")
    print("   judder REL = med|d2| / |d1| moy : la part du pas de camera qui est un a-coup.")
    print("      C'est la SEULE colonne comparable entre deux legs, parce que |d1| depend du")
    print("      nombre de ticks qu'une image dessinee consomme (2,8 en rattrapage contre 1).")
    print("   %-18s %6s %8s %8s %7s %8s %12s %10s %10s %10s %5s" %
          ("leg", "images", "dt_med", "fps", "armed%", "k moyen", "s_jeu/s_reel",
           "|d1| moy", "med|d2|", "judderREL", "n"))
    for leg in a.legs:
        rows = parse_gft(os.path.join(a.dir, leg + ".log"))
        if len(rows) < 40:
            print("   %-18s %6d  (trop peu d'images)" % (leg, len(rows)))
            continue
        body = rows[len(rows) // 4:]  # jette le demarrage
        dts = sorted(r["dt_ms"] for r in body if r["dt_ms"] > 0)
        dtm = dts[len(dts) // 2] if dts else 0.0
        # secondes de JEU par seconde REELLE : une image armee avance de k/60 s de jeu ;
        # une image NON armee avance de 1/target-fps (time-ratio epingle a 1 par le
        # harnais de rejeu). target-fps se lit dans l'etiquette du leg.
        mfps = re.search(r"f(\d+)_", leg)
        tfps = float(mfps.group(1)) if mfps else 60.0
        gsec = sum((r["k"] / 60.0) if r["armed"] else (1.0 / tfps) for r in body)
        rsec = sum(r["dt_ms"] for r in body) / 1000.0
        rate = (gsec / rsec) if rsec > 0 else 0.0
        armed = 100.0 * sum(1 for r in body if r["armed"]) / len(body)
        km = sum(r["k"] for r in body) / len(body)
        j = judder(rows, len(rows) // 4, len(rows))
        if j is None:
            print("   %-18s %6d  (fenetre trop courte)" % (leg, len(rows)))
            continue
        sd, med, p95, am, n = j
        print("   %-18s %6d %8.2f %8.1f %7.1f %8.3f %12.3f %10.5f %10.5f %10.5f %5d" %
              (leg, len(rows), dtm, (1000.0 / dtm if dtm > 0 else 0.0), armed, km, rate,
               am, med, (med / am if am > 0 else 0.0), n))


if __name__ == "__main__":
    main()
