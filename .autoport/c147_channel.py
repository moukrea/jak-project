#!/usr/bin/env python3
# c147_channel.py — LE DEFICIT ET L'EXCES NE VIVENT PAS DANS LE MEME CANAL DE PILOTAGE.
#
# `ROOM-REGIME-STIM` publie, pour chaque regime, LEQUEL des deux termes du pilotage de §3
# (`a_drive = (g_local - g_ref) - a_torso + a_angular`) est arme : `acmd` (acceleration LINEAIRE
# du torse, u/f^2) ou `alp` (acceleration ANGULAIRE, rad/f^2). Les deux ne sont jamais armes
# ensemble. On croise cette colonne avec le verdict de bande de `ROOM-APEX-REGIME`.
# NATURE : un COMPTE de cellules par (canal, verdict). REPERE : celui de ROOM-APEX-REGIME.
# LECTURE HORS DEFAUT : le regime r=0 ne recoit aucun pilotage (acmd=0, alp=0) et n'a pas de bande.
import re, io, sys, collections

tbl = sys.argv[1] if len(sys.argv) > 1 else \
      ".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"
t = io.open(tbl, encoding="utf-8", errors="replace").read()

chan = {}
for m in re.finditer(r'^ROOM-REGIME-STIM: r=\s*(\d+) (\S+)\s+(\S+)\s+acmd=\s*([\d.]+) alp=\s*([\d.]+)', t, re.M):
    r, name, sec, ac, al = int(m.group(1)), m.group(2), m.group(3), float(m.group(4)), float(m.group(5))
    chan[r] = ("LINEAIRE" if ac > 0 and al == 0 else
               "ANGULAIRE" if al > 0 and ac == 0 else
               "AUCUN" if ac == 0 and al == 0 else "MIXTE", name, sec)

rows = re.findall(r'^ROOM-APEX-REGIME: (chest[LR])\s+r=\s*(\d+) (\S+)\s+apex=([\d.]+) B0\s+\[([\d.]+)-([\d.]+)\]\s+->\s+(\S+)', t, re.M)
tally = collections.Counter()
print("%-7s %-3s %-14s %-10s %-6s %8s  %-12s %s" % ("chaine","r","regime","canal","sec","apex","bande","verdict"))
for ch, r, name, apex, lo, hi, verd in rows:
    r = int(r); c = chan.get(r, ("?", name, "?"))
    tally[(c[0], verd)] += 1
    print("%-7s %-3s %-14s %-10s %-6s %8s  [%s-%s]  %s" % (ch, r, name, c[0], c[2], apex, lo, hi, verd))
print()
print("COMPTE PAR CANAL DE PILOTAGE ET PAR VERDICT :")
for cn in ("LINEAIRE", "ANGULAIRE", "MIXTE", "AUCUN", "?"):
    sub = {v: n for (c, v), n in tally.items() if c == cn}
    if sub:
        print("   %-10s  %s   (total %d)" % (cn, "  ".join("%s=%d" % kv for kv in sorted(sub.items())), sum(sub.values())))
