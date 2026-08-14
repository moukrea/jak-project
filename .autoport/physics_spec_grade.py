#!/usr/bin/env python3
"""physics_spec_grade.py — note la POITRINE section par section contre SPEC-breast-softbody.md.

Pourquoi ce script existe. L'owner, 2026-08-14 07:30 : « Fais la spec de ses seins a 100 % comme
specifie » — et la directive qui en decoule exige que le rapport dise, POUR CHAQUE SECTION
APPLICABLE, *implementee / mesuree / ecart*. Jusqu'ici chaque section etait recalculee a la main
dans un cycle different, avec un seuil retape a chaque fois. Un chiffre qu'on retape est un chiffre
qu'on finit par arrondir : celui-ci se relit d'une commande, sur la trace de la course.

CE QU'IL LIT, ET DANS QUEL REPERE (les trois questions de SPEC-keira-physique 7) :

  SPEC 22 / 38 — EXCURSION D'APEX.
      NATURE  : un DEPLACEMENT, pas une variance. `PHYSGRADS a0/a1` publie l'angle entre la
                direction courante du maillon et celle de la pose du modele, aux DEUX etages du
                solveur (a0 = apres integration, a1 = apres les contraintes).
      REPERE  : celui de l'ATTACHE du maillon — c'est la deviation propre, pas celle heritee du
                torse.
      CONVERSION : `D/B0 = 2 sin(theta/2)` exactement, parce que les deux directions sont unitaires
                et partent de la meme attache. Donc 0.42 B0 <-> 24.24 deg et 0.50 B0 <-> 28.96 deg.
                Aucun seuil invente ici : ce sont `NormalMaxApexDisplacement` et
                `HardMaxApexDisplacement` de son preset 38, convertis.
      SANS LE DEFAUT : 0 deg (le maillon est sur la pose du modele).

  SPEC 9 — ETAT DEBOUT NEUTRE. `PHYSIDLE dev=` : ecart a la pose du modele au repos. Sa 9 exige
      `Apex Displacement = 0.00 B0` et « the original authored standing shape shall be restored
      EXACTLY ». Toute valeur > 0 est un ecart, et il est publie tel quel.

  SPEC 32 — INDEPENDANCE GAUCHE/DROITE. Lue sur les PARAMETRES LIVRES, pas sur une intention :
      `stiffness` et `damping` de chestL vs chestR dans recharged_assets/physics_chains.txt. Sa
      bande : masse +-2-4 %, raideur +-3-5 %, amortissement +-3-5 %.

  SPEC 6 — B0. `PHYSBONE len=` : la longueur d'os MESUREE sur le rig, jamais une constante.

Les frequences (24), l'amortissement (25) et le rebond (26) ne sont PAS recalcules ici : c'est
`.autoport/physics_ringdown.py` qui les tient, sur la grandeur signee `PHYSRING3`, et dupliquer sa
lecture serait se donner deux chiffres a defendre au lieu d'un.

Usage: physics_spec_grade.py [log] [--chains 0,1]
"""
import math
import re
import sys

LOG = ".autoport/reports/Grecharged-secondary-motion/keira-room-x86.log"
CHAINS_FILE = "recharged_assets/physics_chains.txt"

# B0 au sens de sa §6 — longueur racine->apex de la CHAIR, mesuree sur le maillage livre par
# `.autoport/probe_breast_shape.py --glb out/jak1/fr3/skin/keira-hd-lod0.glb` (0.1470 m x 4096).
# Elle est identique sur les deux seins (le maillage est miroir), d'ou une seule valeur.
B0_MESH_U = 602.1


def deg_for(bfrac):
    """L'angle qui vaut `bfrac` B0 d'excursion. D/B0 = 2 sin(theta/2), exactement."""
    return 2.0 * math.degrees(math.asin(bfrac / 2.0))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    log = args[0] if args else LOG
    sel = None
    for a in sys.argv[1:]:
        if a.startswith("--chains"):
            sel = {int(x) for x in a.split("=", 1)[1].split(",")}

    blob = open(log, errors="ignore").read()

    # --- noms de chaine, tels que le MOTEUR les a resolus -------------------------------------
    j0 = dict(re.findall(r"^PHYSCHAIN c=(\d+) links=\d+ fam=\d+ hang=\S+ j0=(\S+)", blob, re.M))
    names = [n for _, n in sorted(j0.items(), key=lambda kv: int(kv[0]))]
    bone = {}
    for c, l, ln in re.findall(r"^PHYSBONE c=(\d+) l=(\d+) len=([-\d.eE+]+)", blob, re.M):
        bone[(int(c), int(l))] = float(ln)

    NORMAL, HARD = deg_for(0.42), deg_for(0.50)
    print("SPEC-BREAST — NOTATION SECTION PAR SECTION   (trace : %s)" % log)
    print("  chaines resolues par le moteur : %s"
          % ", ".join("c=%s %s" % (k, v) for k, v in sorted(j0.items(), key=lambda kv: int(kv[0]))))
    print("  SPEC 6  B0 tel que LE MOTEUR le prend (longueur d'os ancre->joint) : %s"
          % ", ".join("c=%d l=%d len=%.2f" % (c, l, v) for (c, l), v in sorted(bone.items())))
    # --------------------------------------------------------------------------------------
    # ET LE B0 QUE SA §6 DEFINIT, QUI N'EST PAS LE MEME — mesure du 2026-08-14.
    # §6 : « B0 neutral characteristic root-to-apex length […] the game implementation shall
    # derive normalized dimensions directly from the character mesh », reference humaine
    # 115-125 mm. La longueur d'os `chest->lBoob` vaut 977 u = 238 mm : c'est la distance du
    # thorax a un JOINT qui se trouve DERRIERE la chair (elle commence 34 mm apres lui et finit
    # 181 mm apres lui). La longueur racine->apex de la chair, mesuree sur le maillage livre par
    # `.autoport/probe_breast_shape.py`, vaut 602 u = 147 mm.
    # Le rapport 1.62 ne se devine pas : il rend la borne de §22 1.62x TROP LACHE, donc une
    # excursion « conforme » a 0.48 B0 vaut en realite 0.78 B0. Les deux colonnes sont publiees
    # cote a cote pour que personne n'ait a le recalculer, et l'ancienne reste la premiere pour
    # que la serie des cycles precedents reste comparable.
    # --------------------------------------------------------------------------------------
    print("  SPEC 6  B0 tel que sa §6 le DEFINIT (racine->apex, mesure sur le maillage) : %.0f u"
          % B0_MESH_U)
    print("  SPEC 22/38 plafonds convertis : 0.42 B0 = %.2f deg (normal) · 0.50 B0 = %.2f deg (dur)"
          % (NORMAL, HARD))
    print()

    # --- SPEC 22 / 38 : excursion d'apex, aux deux etages --------------------------------------
    per = {}
    for c, a, d, l, a0, a1 in re.findall(
            r"^PHYSGRADS c=(\d+) a=(\d+) d=(\d+) l=(\d+) a0=([-\d.eE+]+) a1=([-\d.eE+]+)",
            blob, re.M):
        c = int(c)
        if sel is not None and c not in sel:
            continue
        v0, v1 = abs(float(a0)), abs(float(a1))
        k = per.setdefault(c, dict(n=0, m0=0.0, m1=0.0, o0=0, o1=0, w0=None, w1=None))
        k["n"] += 1
        if v0 > k["m0"]:
            k["m0"], k["w0"] = v0, (a, d)
        if v1 > k["m1"]:
            k["m1"], k["w1"] = v1, (a, d)
        k["o0"] += v0 > HARD
        k["o1"] += v1 > HARD

    print("SPEC 22 / 38 — EXCURSION D'APEX (plafond dur HardMaxApexDisplacement = 0.50 B0)")
    print("  %-8s %-8s %8s %8s %10s %10s %8s %10s"
          % ("c", "chaine", "cellules", "a0 max", "B0 os", "B0 §6", "a1 max", "a0>0.50"))
    worst6 = 0.0
    for c in sorted(per):
        k = per[c]
        nm = names[c] if c < len(names) else "?"
        b_os = 2 * math.sin(math.radians(k["m0"]) / 2)
        # meme excursion, exprimee dans le B0 que sa §6 definit : la deviation angulaire est
        # convertie en corde par la longueur d'os REELLE du maillon, puis divisee par B0_MESH_U.
        blen = bone.get((c, 0), 0.0)
        b_s6 = (b_os * blen / B0_MESH_U) if blen > 0 else float('nan')
        worst6 = max(worst6, b_s6)
        print("  %-8d %-8s %8d %7.3f° %10.3f %10.3f %7.3f° %10d"
              % (c, nm, k["n"], k["m0"], b_os, b_s6, k["m1"], k["o0"] + k["o1"]))
    tot = sum(k["o0"] + k["o1"] for k in per.values())
    print("  VERDICT SPEC 22/38 contre le B0 DU MOTEUR : %d depassement(s) sur %d cellule(s) x 2"
          % (tot, sum(k["n"] for k in per.values())))
    print("  VERDICT SPEC 22/38 contre le B0 DE SA §6   : pire excursion %.3f B0 pour un plafond"
          " dur de 0.50 — %s" % (worst6, "TENU" if worst6 <= 0.50 else
                                 "DEPASSE de %.2fx" % (worst6 / 0.50)))
    print()

    # --- SPEC 9 : la pose debout revient-elle EXACTEMENT ? -------------------------------------
    print("SPEC 9 — ETAT DEBOUT NEUTRE (« restored EXACTLY », Apex Displacement = 0.00 B0)")
    seen = set()
    for c, dev, hang, amp, fam in re.findall(
            r"^PHYSIDLE c=(\d+) dev=([-\d.eE+]+) hang=([-\d.eE+]+) amp=([-\d.eE+]+) fam=(\d+)",
            blob, re.M):
        c = int(c)
        if (sel is not None and c not in sel) or c in seen:
            continue
        seen.add(c)
        nm = names[c] if c < len(names) else "?"
        b0 = bone.get((c, 0), 0.0)
        print("  c=%d %-8s dev=%.4f u  (%.4f B0)   cible 0.0000 — ecart = la valeur elle-meme"
              % (c, nm, float(dev), float(dev) / b0 if b0 else float("nan")))
    print()

    # --- SPEC 32 : independance gauche/droite, sur les PARAMETRES LIVRES -----------------------
    print("SPEC 32 — INDEPENDANCE G/D (bandes : masse +-2-4 %, raideur +-3-5 %, amortissement +-3-5 %)")
    par = {}
    for ln in open(CHAINS_FILE, errors="ignore"):
        if ln.startswith("chain "):
            t = ln.split()
            par[t[1]] = {k: v for k, v in (x.split("=", 1) for x in t[2:] if "=" in x)}
    if "chestL" in par and "chestR" in par:
        for key, lo, hi in (("mass", 2.0, 4.0), ("stiffness", 3.0, 5.0), ("damping", 3.0, 5.0)):
            a, b = float(par["chestL"].get(key, 0)), float(par["chestR"].get(key, 0))
            if a == 0 and b == 0:
                continue
            ec = 100.0 * abs(b - a) / max(abs(a), abs(b)) if max(abs(a), abs(b)) else 0.0
            verdict = "DANS LA BANDE" if lo <= ec <= hi else ("SOUS LA BANDE" if ec < lo else "AU-DESSUS")
            print("  %-10s L=%-9s R=%-9s ecart=%5.2f %%   bande %.0f-%.0f %%   %s"
                  % (key, par["chestL"].get(key), par["chestR"].get(key), ec, lo, hi, verdict))
    else:
        print("  chestL/chestR absents du fichier livre — rien a comparer")
    return 0


if __name__ == "__main__":
    sys.exit(main())
