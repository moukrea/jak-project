#!/usr/bin/env python3
# c147_predict.py — LA PREVISION, CALCULEE SUR LA TRACE ARCHIVEE, AVANT TOUTE COURSE.
#
# NATURE : longueur / B0 (602 u), centroide de masse du decile distal. REPERE : monde, contre la
# pose d'auteur de la MEME frame. Ce que ce script transforme, ce sont les valeurs LIVREES par la
# course du cycle 145 (`keira-room-table.20260828-063645.txt`), c'est-a-dire la course SANS le
# plafond d'apex — donc l'ENTREE de l'operateur, pas sa sortie.
#
# POURQUOI TRANSFORMER UN MAXIMUM EST LEGITIME ICI : l'operateur est STRICTEMENT CROISSANT, donc
# max(f(x)) = f(max(x)) sur une meme fenetre. Ce qui reste une approximation, et qui est declare :
# la borne deplace les volumes de collision via `phys-snapshot-sim!`, donc la TRAJECTOIRE de la
# frame suivante. Les chiffres ci-dessous sont donc une PREVISION, jamais l'algebre de la course.
import re, sys

AKN, ACP = 0.4199, 0.0799          # PHYSPSETD, identiques sur les deux chaines
DM = AKN + ACP                     # 0.4998 B0 = le « exceptional <=50% B0 » que SPEC 22 l.301 ECRIT

def pade(x):                       # LA MEME tanh de Pade que le moteur, au bit pres
    return 1.0 if x >= 3.0 else (x * (27.0 + x*x)) / (27.0 + 9.0*x*x)

def new_op(sd):                    # SPEC 21 l.293 AU MOT : D_max . tanh(|D| / D_max)
    if sd <= 1e-4: return sd
    return DM * pade(sd / DM)

def old_op(sd):                    # l'operateur du cycle 146 : genou AKN, echelle de compression ACP
    if sd <= AKN: return sd
    return AKN + ACP * pade((sd - AKN) / ACP)

src = ".autoport/reports/Grecharged-secondary-motion/keira-room-table.20260828-063645.txt"
rx = re.compile(r'^ROOM-APEX-REGIME: (chest[LR])\s+r=\s*(\d+) (\S+)\s+apex=([\d.]+) B0(?:\s+\[([\d.]+)-([\d.]+)\])?')
rows = []
for line in open(src, encoding='utf-8', errors='replace'):
    m = rx.match(line.strip())
    if m: rows.append(m.groups())

def verdict(v, lo, hi):
    if lo is None: return "(pas de bande)"
    lo, hi = float(lo), float(hi)
    if v < lo:  return "SOUS      (x%.2f)" % (v/lo)
    if v > hi:  return "AU-DESSUS (x%.2f)" % (v/hi)
    return "DANS"

print("%-7s %-3s %-14s %8s %8s %8s   %-18s -> %-18s" %
      ("chaine","r","regime","c145","c146","c147","verdict c146","verdict c147 PREVU"))
chg = {"gagne": [], "perdu": []}
for ch, r, name, apex, lo, hi in rows:
    a = float(apex)
    o, n = old_op(a), new_op(a)
    vo, vn = verdict(o, lo, hi), verdict(n, lo, hi)
    print("%-7s %-3s %-14s %8.4f %8.4f %8.4f   %-18s -> %-18s%s" %
          (ch, r, name, a, o, n, vo, vn, "   <<<" if vo != vn else ""))
    if lo:
        if vo != "DANS" and vn == "DANS": chg["gagne"].append((ch, r, name))
        if vo == "DANS" and vn != "DANS": chg["perdu"].append((ch, r, name))
print()
print("cellules GAGNEES (hors bande -> DANS) :", chg["gagne"])
print("cellules PERDUES (DANS -> hors bande) :", chg["perdu"])
print()
for ch, typ, mx in (("chestL", 0.6685, 0.8881), ("chestR", 0.6891, 0.9666)):
    print("%s  pic typique %.4f -> c146 %.4f (x%.2f de 0.42) -> c147 %.4f (x%.2f)   |   max de course %.4f -> c146 %.4f -> c147 %.4f"
          % (ch, typ, old_op(typ), old_op(typ)/0.42, new_op(typ), new_op(typ)/0.42, mx, old_op(mx), new_op(mx)))
print()
print("ETALEMENT DE LA REPONSE (p50 -> max), la grandeur que la regle 7 exige non nulle :")
for ch, p50, mx in (("chestL", 0.6759, 0.8881), ("chestR", 0.6891, 0.9666)):
    print("   %s : c146 %.4f -> %.4f  (etalement %.2f %%)   |   c147 %.4f -> %.4f  (etalement %.2f %%)"
          % (ch, old_op(p50), old_op(mx), 100.0*(old_op(mx)/old_op(p50)-1.0),
                 new_op(p50), new_op(mx), 100.0*(new_op(mx)/new_op(p50)-1.0)))
