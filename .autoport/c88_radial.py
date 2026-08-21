#!/usr/bin/env python3
"""c88 — LA PART RADIALE DE L'EXCURSION D'APEX (NOTE-472).

Le cycle 87 a explique l'echec de la borne-par-rotation par « la correction demandee est
RADIALE, une rotation est TANGENTIELLE ». **Cette explication n'etait pas mesuree.** Ce lecteur
la met a l'epreuve sur la trace : `rad` (projection ponderee de l'excursion sur le levier de
chair de chaque maillon, meme argmax que `apex`) contre `apex` lui-meme.

  |rad| / apex proche de 1  -> l'excursion est surtout RADIALE, une rotation ne peut pas la
                               retirer : l'explication du cycle 87 TIENT.
  |rad| / apex proche de 0  -> l'excursion est surtout TANGENTIELLE : l'explication est FAUSSE
                               et c'est le rapport qui doit le dire.

NATURE / REPERE : voir phys-room.gc, bloc PHYSAPEXR. Usage : python3 .autoport/c88_radial.py [log]
"""
import math
import re
import sys

OUT = ".autoport/reports/Grecharged-secondary-motion"
NAMES = {0: "chestL", 1: "chestR"}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else OUT + "/keira-room-x86.log"
    txt = open(path, errors="replace").read()
    apex, rad = {}, {}
    for m in re.finditer(r"^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.eE+]+)", txt, re.M):
        apex[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = float(m.group(4))
    for m in re.finditer(r"^PHYSAPEXR c=(\d+) a=(\d+) d=(\d+) rad=([-\d.eE+]+)", txt, re.M):
        rad[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = float(m.group(4))
    if not rad:
        print("AUCUNE ligne PHYSAPEXR dans %s — l'instrument n'est pas dans cette trace." % path)
        return 1
    print("== PART RADIALE DE L'EXCURSION D'APEX — %d fenetres lues ==" % len(rad))
    print("   `rad` est une projection : |rad| <= apex par construction. Un |rad|/apex proche de 1")
    print("   veut dire qu'une ROTATION autour du joint ne peut pas retirer cette excursion.")
    for c in sorted(NAMES):
        keys = [k for k in rad if k[0] == c and k in apex and apex[k] > 1e-6]
        if not keys:
            continue
        fr = sorted(abs(rad[k]) / apex[k] for k in keys)
        neg = sum(1 for k in keys if rad[k] < 0)
        viol = sum(1 for k in keys if abs(rad[k]) > apex[k] + 1e-6)
        med = fr[len(fr) // 2]
        print("  %-7s n=%-4d |rad|/apex : min %.4f  med %.4f  p90 %.4f  max %.4f"
              % (NAMES[c], len(fr), fr[0], med, fr[int(0.9 * (len(fr) - 1))], fr[-1]))
        rr = sorted(rad[k] for k in keys)
        aa = sorted(apex[k] for k in keys)
        print("          rad median %+.4f B0   apex median %.4f B0   signe<0 : %d/%d"
              % (rr[len(rr) // 2], aa[len(aa) // 2], neg, len(keys)))
        # CONTROLE D'INTEGRITE : une projection ne peut pas depasser la norme. S'il le fait, ce
        # n'est pas un resultat, c'est un instrument faux, et il se declare comme tel.
        print("          controle |rad| <= apex : %s"
              % ("OK" if viol == 0 else "VIOLE sur %d fenetres — INSTRUMENT FAUX" % viol))
    return 0


if __name__ == "__main__":
    sys.exit(main())
