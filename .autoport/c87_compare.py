#!/usr/bin/env python3
"""c87 — LECTURE DE LA PAIRE APPARIEE DE LA BORNE DE SPEC 21/22 SUR LE POINT DE CHAIR.

Trois traces, deux attributions SEPAREES :
  c81  = l'arbre d'avant le cycle 87 (`phys-apex-scale` present, aucune borne sur la chair)
  B    = `phys-apex-scale` RETIRE, borne neuve DESARMEE   -> B contre c81 = le prix du RETRAIT
  A    = `phys-apex-scale` RETIRE, borne neuve ARMEE      -> A contre B  = ce que l'AJOUT rend

NATURE / REPERE : voir le bloc `ROOM-SPEC21` du tableau — toutes les grandeurs lues ici sont
celles que la salle publie deja, en unites de B0 (602 u), repere MONDE, contre la pose d'auteur
de la MEME frame.

Usage : python3 .autoport/c87_compare.py
"""
import re
import sys
import math

OUT = ".autoport/reports/Grecharged-secondary-motion"
LEGS = [("c81", OUT + "/keira-room-x86.c81-armed.log"),
        ("B  ", OUT + "/keira-room-x86.c87-B.log"),
        ("A  ", OUT + "/keira-room-x86.c87-A.log")]
NAMES = {0: "chestL", 1: "chestR"}


def n3(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def load(path):
    try:
        txt = open(path, errors="replace").read()
    except OSError:
        return None
    rows = {}
    for m in re.finditer(r"^PHYSAPEX(\w*) c=(\d+) a=(\d+) d=(\d+) (.*)$", txt, re.M):
        r = rows.setdefault((int(m.group(2)), int(m.group(3)), int(m.group(4))), {})
        for k, v in re.findall(r"(\w+)=(-?[\d.eE+]+)", m.group(5)):
            try:
                r[k] = float(v)
            except ValueError:
                pass
    tip = {}
    e21 = re.findall(r"^PHYSE21 tag=(\S+) n=([-\d.e+]+) cut_b0=([-\d.e+]+)", txt, re.M)
    e22 = re.findall(r"^PHYSE22 tag=(\S+) n=([-\d.e+]+) cut_b0=([-\d.e+]+)", txt, re.M)
    idle = re.findall(r"^PHYSIDLE\b.*?dev=([-\d.e+]+)", txt, re.M)
    return dict(txt=txt, rows=rows, tip=tip, e21=e21, e22=e22, idle=idle)


def stat(vals):
    v = sorted(vals)
    return (sum(v) / len(v), v[len(v) // 2], v[-1])


def main():
    data = [(nm, load(p)) for nm, p in LEGS]
    for nm, d in data:
        if d is None:
            print("ABSENT : %s" % nm)
    print("== COMPTEURS DE LA BORNE (PHYSE21) — le controle NEGATIF se lit ici ==")
    print("   desarmee la borne DOIT rendre n=0 et cut_b0=0 exactement.")
    for nm, d in data:
        if not d:
            continue
        tot_n = sum(float(x[1]) for x in d["e21"])
        tot_c = sum(float(x[2]) for x in d["e21"])
        tot22 = sum(float(x[1]) for x in d["e22"])
        print("   %s : PHYSE21 n=%.0f cut_b0=%.4f  (tags=%d)  ·  PHYSE22 n=%.0f"
              % (nm, tot_n, tot_c, len(d["e21"]), tot22))

    print("\n== SPEC 22 : L'APEX LIVRE, PAR CHAINE ==")
    for c in (0, 1):
        print("  %s" % NAMES[c])
        for nm, d in data:
            if not d:
                continue
            v = [d["rows"][k]["apex"] for k in d["rows"]
                 if k[0] == c and "apex" in d["rows"][k]]
            if not v:
                continue
            mo, me, mx = stat(v)
            print("    %s  moy %.4f  med %.4f  max %.4f   >0.42 %3d/%d  >0.50 %3d/%d"
                  % (nm, mo, me, mx,
                     sum(1 for x in v if x > 0.42), len(v),
                     sum(1 for x in v if x > 0.50), len(v)))

    print("\n== LES TROIS TERMES : ce que la borne devait deplacer, et ce qu'elle n'a pas touche ==")
    for c in (0, 1):
        print("  %s" % NAMES[c])
        for nm, d in data:
            if not d:
                continue
            P = [d["rows"][k] for k in d["rows"]
                 if k[0] == c and all(q in d["rows"][k] for q in ("ax", "tx", "dx"))]
            if not P:
                continue
            def med(f):
                v = sorted(f(r) for r in P)
                return v[len(v) // 2]
            e = lambda r: (r["ax"], r["ay"], r["az"])
            tp = lambda r: (r["tx"], r["ty"], r["tz"])
            dp = lambda r: (r["dx"], r["dy"], r["dz"])
            s = lambda r: tuple(e(r)[i] - dp(r)[i] for i in range(3))
            print("    %s  |e| %.4f  |s| %.4f  |tp| %.4f  |dp| %.4f   (medianes)"
                  % (nm, med(lambda r: n3(e(r))), med(lambda r: n3(s(r))),
                     med(lambda r: n3(tp(r))), med(lambda r: n3(dp(r)))))

    print("\n== LE PRIX : `tipvar` par pilotage, lu sur les TABLEAUX (une ligne par drive) ==")
    print("   un effondrement UNIFORME serait du muselage et le geste se retirerait.")
    tabs = [("c81", OUT + "/keira-room-table.c81-armed.txt"),
            ("B  ", OUT + "/keira-room-table.c87-B.txt"),
            ("A  ", OUT + "/keira-room-table.c87-A.txt")]
    got = {}
    for nm, p in tabs:
        try:
            t = open(p, errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r"^drive=(\w+)\s+windows=(\d+)\s+tipvar_max=([-\d.e+]+)"
                             r"\s+tipvar_min=([-\d.e+]+)", t, re.M):
            got.setdefault(m.group(1), {})[nm] = (float(m.group(3)), float(m.group(4)))
    if not got:
        print("   AUCUN tableau lisible — le prix n'est PAS mesure, et rien n'est conclu dessus.")
    for drv in got:
        line = "   %-10s" % drv
        base = got[drv].get("B  ", (None, None))[0]
        for nm in ("c81", "B  ", "A  "):
            if nm in got[drv]:
                mx, mn = got[drv][nm]
                rel = ("x%.3f" % (mx / base)) if base else "  --  "
                line += "  %s max %.4f %s min %.4f" % (nm, mx, rel, mn)
        print(line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
