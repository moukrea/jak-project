#!/usr/bin/env python3
"""c86 — DECOMPOSITION DE L'EXCURSION D'APEX EN SES TROIS TERMES, SUR UNE TRACE ARCHIVEE.

Verification INDEPENDANTE du bloc `ROOM-SPEC21` de .autoport/physics_room_table.py : meme
trace, meme identite, chemin de calcul separe. Les deux doivent s'accorder.

NATURE   : trois VECTEURS en unites de B0 (sans dimension), et leurs normes.
REPERE   : le MONDE ; difference de deux points de la MEME frame (pose simulee contre pose
           d'AUTEUR du meme joint). Meme repere que `apex`/`ax`/`ay`/`az` de PHYSAPEX.
IDENTITE : e = tp + rp + dp, `rp` DERIVE (jamais emis) — l'identite EST le controle.
LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 partout a la pose d'auteur.

CE QUE §21 SATURE, MOT POUR MOT (SPEC-breast-softbody.md l.290-293) :
  « Linear and rotational displacement contributions shall combine vectorially.
    They shall not be added without saturation.
    D_combined = D_max . tanh( |D_linear + D_angular| / D_max ) »
donc la grandeur de §21 est  s = tp + rp = e - dp,  PAS la force du ressort.

Usage : python3 .autoport/c86_apex_terms.py [log]
"""
import re
import sys
import math

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    ".autoport/reports/Grecharged-secondary-motion/keira-room-x86.log"

CAPN, CAPX = 0.42, 0.50      # §22 l.301 : « normal <=42% B0, exceptional <=50% B0 »
NAMES = {0: "chestL", 1: "chestR"}


def n3(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def softmin(v, cap):
    """`phys-softmin` de jak-hd-physics.gc:909 — identite stricte sous 0.84*cap."""
    kn = 0.84 * cap
    if cap <= 0.0 or v <= kn:
        return v
    cp = cap - kn
    x = (v - kn) / cp
    return kn + cp * (x / (1.0 + x))


def parse(log):
    pat = re.compile(r"^PHYSAPEX(\w*) c=(\d+) a=(\d+) d=(\d+) (.*)$")
    rows = {}
    for line in open(log, errors="replace"):
        m = pat.match(line)
        if not m:
            continue
        key = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        r = rows.setdefault(key, {})
        for k, v in re.findall(r"(\w+)=(-?[\d.eE+]+)", m.group(5)):
            try:
                r[k] = float(v)
            except ValueError:
                pass
    return rows


def main():
    rows = parse(LOG)
    need = ("apex", "ax", "ay", "az", "tx", "ty", "tz", "dx", "dy", "dz")
    per = {}
    for (c, a, d), r in sorted(rows.items()):
        if any(k not in r for k in need):
            continue
        e = (r["ax"], r["ay"], r["az"])
        tp = (r["tx"], r["ty"], r["tz"])
        dp = (r["dx"], r["dy"], r["dz"])
        rp = tuple(e[i] - tp[i] - dp[i] for i in range(3))
        s = tuple(e[i] - dp[i] for i in range(3))
        per.setdefault(c, []).append((r["apex"], e, s, tp, rp, dp))
    if not per:
        print("aucune ligne PHYSAPEX/PHYSAPEXT/PHYSAPEXD exploitable dans %s" % LOG)
        return 1

    for c in sorted(per):
        P = per[c]
        nm = NAMES.get(c, str(c))
        print("\n=== %s  n=%d fenetres  (trace %s) ===" % (nm, len(P), LOG))
        ident = max(abs(n3(x[1]) - x[0]) for x in P)
        print("  CONTROLE 1 — identite |e| - apex publie : %.6f B0 (les 4 termes sur LA MEME frame)"
              % ident)
        print("  CONTROLE 2 — |tp| max %.4f B0 : doit rester sous 0.5000, l'asymptote algebrique de"
              % max(n3(x[3]) for x in P))
        print("               `phys-cap-e22!`, la SEULE borne du moteur qui agisse sur ce terme.")
        print("  %-12s %9s %9s %9s" % ("", "mediane", "p90", "max"))
        for lab, idx in (("|e|  apex", 1), ("|s|  §21", 2), ("|tp| transl", 3),
                         ("|rp| rotat.", 4), ("|dp| tenseur", 5)):
            v = sorted(n3(x[idx]) for x in P)
            # MEME convention de quantile que le bloc `ROOM-SPEC21` du tableau (v[n//2]), pour
            # que les deux instruments publient le MEME chiffre et non deux conventions.
            print("  %-12s %9.4f %9.4f %9.4f"
                  % (lab, v[len(v) // 2], v[min(len(v) - 1, int(0.9 * len(v)))], v[-1]))
        print("  |s| > %.2f B0 : %d/%d fenetres"
              % (CAPX, sum(1 for x in P if n3(x[2]) > CAPX), len(P)))

        pj = {"tp": [], "rp": [], "dp": []}
        for _ap, e, _s, tp, rp, dp in P:
            ne = n3(e)
            if ne < 0.01:
                continue
            u = tuple(x / ne for x in e)
            for k, v in (("tp", tp), ("rp", rp), ("dp", dp)):
                pj[k].append(100.0 * sum(v[i] * u[i] for i in range(3)) / ne)
        print("  part signee dans l'apex (PROJECTION sur e^, mediane — somme 100 %) : "
              + "  ".join("%s %+6.1f %%" % (k, sorted(pj[k])[len(pj[k]) // 2])
                            for k in ("tp", "rp", "dp")))

        cur = [n3(x[1]) for x in P]

        def report(lab, vals):
            print("    %-22s moy %.4f  max %.4f  >0.42 %3d/%d  >0.50 %3d/%d"
                  % (lab, sum(vals) / len(vals), max(vals),
                     sum(1 for v in vals if v > CAPN), len(vals),
                     sum(1 for v in vals if v > CAPX), len(vals)))

        print("  SIMULATION EXACTE (algebre de la SORTIE : la borne visee porte sur la valeur")
        print("  LIVREE et n'ecrit pas `*phys-px*`, donc sans retro-action de frame a frame) :")
        report("aujourd'hui", cur)
        for cap in (CAPX, CAPN):
            eA = [n3(tuple(softmin(n3(x[2]), cap) / max(n3(x[2]), 1e-9) * x[2][i] + x[5][i]
                           for i in range(3))) for x in P]
            eB = [softmin(v, cap) for v in cur]
            report("(A) §21 sur s, %.2f" % cap, eA)
            report("(B) sur e, %.2f" % cap, eB)
        report("cas LIMITE s=0", [n3(x[5]) for x in P])
        print("    « cas LIMITE s=0 » = translation ET rotation du joint annulees, c'est-a-dire une")
        print("    poitrine IMMOBILE : c'est le plafond de ce que toute intervention confinee au")
        print("    canal du JOINT peut rendre. Ce n'est pas une option, c'est une borne.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
