#!/usr/bin/env python3
# c147_verdict.py — LA CONFRONTATION : la course du cycle 147 contre celle du cycle 146,
# ligne de verdict par ligne de verdict, sur les seules grandeurs que les predictions engagent.
# Aucun jugement ici : on imprime les DEUX valeurs cote a cote et on laisse le rapport trancher.
import re, sys, io

NEW = ".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"
OLD = sys.argv[1] if len(sys.argv) > 1 else ".autoport/reports/Grecharged-secondary-motion/keira-room-table.20260828-074510.txt"

def load(p):
    return io.open(p, encoding="utf-8", errors="replace").read().splitlines()

def grab(lines, pat):
    rx = re.compile(pat)
    return [l.rstrip() for l in lines if rx.search(l)]

o, n = load(OLD), load(NEW)
print("OLD =", OLD)
print("NEW =", NEW)

BLOCKS = [
    ("P1/P2/P3/P4  ROOM-APEX (le plafond, l'etalement, la clause normale)",
     r"^ROOM-APEX: chain=|VERDICT .22 «|distribution des maxima|part des FENETRES au-dessus"),
    ("P0/P11  les compteurs de la borne",
     r"PHYSE22A|VERDICT .22 l\.301|VERDICT .21 : la borne"),
    ("P3 bis  ROOM-SPEC21 : la decomposition e = s + dp",
     r"^ROOM-SPEC21: chain=|\|e\|  apex|\|s\|  .21|\|dp\| tenseur|\|tp\| transl|\|rp\| rotation"),
    ("P5/P6/P9  ROOM-APEX-REGIME : les 30 cellules",
     r"^ROOM-APEX-REGIME:"),
    ("P7  SPEC 24/25/26 : les lignes etoilees d'AXFIT (mode propre)",
     r"^ROOM-AXFIT:\*"),
    ("P8  SPEC 12 : l'enveloppe de la cellule porteuse",
     r"^ROOM-ORICOM-MASS: chest"),
    ("P10  ROOM-IDLE",
     r"^ROOM-IDLE:"),
    ("gate COLLIDE : la penetration, qui doit rester declaree",
     r"^ROOM-SKINPEN-DETAIL:|^ROOM-MEDIAL-PEN:|meshpen"),
    ("SPEC 10 : la clause porteuse (migration du COM sortant)",
     r"^ROOM-SPEC10:"),
    ("DISCRIMINANT / la garde de non-platitude de la mesure",
     r"^ROOM-DRIVES:|DISCRIMINANT"),
]

for title, pat in BLOCKS:
    print("\n" + "=" * 100)
    print("== " + title)
    print("=" * 100)
    ol, nl = grab(o, pat), grab(n, pat)
    if len(ol) == len(nl):
        for a, b in zip(ol, nl):
            mark = "   " if a == b else ">> "
            print(mark + "c146 " + a[:170])
            if a != b:
                print(">> c147 " + b[:170])
    else:
        print("-- nombre de lignes different (%d -> %d), on imprime les deux blocs --" % (len(ol), len(nl)))
        for a in ol[:60]: print("  c146 " + a[:170])
        print("  ----")
        for b in nl[:60]: print("  c147 " + b[:170])
