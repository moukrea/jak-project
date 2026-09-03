#!/usr/bin/env python3
"""
CYCLE 116 — BLOC D : le controle positif de la sommation compensee (Kahan), lu AU POINT DE PARCAGE.

POURQUOI CE SCRIPT EXISTE, ET C'EST UNE CORRECTION D'INSTRUMENT.
`PHYSSTGQ`, `PHYSRESTQ` et `PHYSBALQ` sont emis a la DERNIERE frame de la fenetre PH-AXC, et les
cycles 114c, 115 et 116 (blocs A a C) ont tous appele cette frame « le point de parcage ». Elle ne
l'est pas : la fenetre porte DEUX impulsions, la montee vers le plateau prend 60 a 75 frames, et la
seconde impulsion tombe a f=164-194 pour une fenetre qui s'arrete a f=230. Sur 4 cellules sur 6 la
fenetre se termine 4 a 38 frames AVANT que le plateau soit atteint : la derniere frame est un point
de la RAMPE DESCENDANTE, pas un point de repos.

Le VRAI point de parcage est le plateau entre les deux impulsions (f ~ 100-160), et il se reconnait
a un critere objectif, pas a un gout : `pe` y est CONSTANT au dernier chiffre imprime pendant plus
de 20 frames consecutives, et `dint` y est nul. Ce script le lit la.

NATURE / REPERE / ABSENT (les trois questions de la SPEC §7) :
  `pe`   LONGUEUR rapportee a B0 (602 u), repere MONDE, maillon `rlk`, INSTANTANEE.
         Absent du defaut = 0 : la chaine est exactement sur la cible du ressort.
  `dint` LONGUEUR en unites de jeu, repere MONDE : ce que les sous-pas ont deplace le joint avant
         toute contrainte. Absent du defaut = une valeur non nulle a chaque frame ou une vitesse
         est commandee ; 0 alors qu'une force est produite = l'integration n'ecrit pas.
  Plancher de bruit DECLARE, mesure au bloc C : le pas du flottant 32 bits a la position monde de
  l'attache — 0,0625 u sur X et Z (binade 2^19), 0,015625 u sur Y (binade 2^17).

USAGE : python3 .autoport/c116_blockD_plateau.py <course-DESARMEE> <course-ARMEE>
"""
import re, sys, statistics as st

RB = re.compile(r'PHYSBALQ c=(\d+) ax=(\d+) f=(\d+) pe=([-0-9.]+) fn=([-0-9.]+) dint=([-0-9.]+)')
RA = re.compile(r'PHYSRINGA c=(\d+) f=(\d+) l=(\d+) v=([-0-9.]+) ap=([-0-9.]+) lat=([-0-9.]+)')
RR = re.compile(r'PHYSRESTQ c=(\d+) ax=(\d+) rgap=([-0-9.]+) perr=([-0-9.]+)')
B0_U = 602.0                      # SPEC 6, en unites de jeu
U_PER_M = 4096.0
QX = QZ = 0.0625                  # pas du flottant a la binade 2^19  (bloc C, mesure)
QY = 0.015625                     # pas du flottant a la binade 2^17  (bloc C, mesure)
QNORM = (QX**2 + QY**2 + QZ**2) ** 0.5   # norme d'un pas complet sur les trois axes

def parse(path):
    balq, ringa, restq = {}, {}, {}
    for line in open(path, errors='ignore'):
        if 'PHYSBALQ' in line:
            m = RB.search(line)
            if m: balq.setdefault((int(m.group(1)), int(m.group(2))), []).append(
                (int(m.group(3)), float(m.group(4)), float(m.group(6))))
        elif 'PHYSRINGA' in line:
            m = RA.search(line)
            if m: ringa.setdefault((int(m.group(1)), int(m.group(3))), []).append(
                (int(m.group(2)), float(m.group(4)), float(m.group(5)), float(m.group(6))))
        elif 'PHYSRESTQ' in line:
            m = RR.search(line)
            if m: restq[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))
    for d in (balq, ringa):
        for k in d: d[k].sort()
    return balq, ringa, restq

def plateau_window(series, minlen=20, ceil=0.01):
    """Premiere fenetre >= minlen frames ou `pe` est CONSTANT au dernier chiffre imprime."""
    for i in range(len(series) - minlen):
        vals = [x[1] for x in series[i:i + minlen]]
        if len(set(vals)) == 1 and vals[0] < ceil:
            j = i
            while j < len(series) and series[j][1] == vals[0]:
                j += 1
            return series[i][0], series[j - 1][0]
    return None, None

def main(dis, arm):
    bd, rd, qd = parse(dis)
    ba, ra, qa = parse(arm)
    W = 96
    print("=" * W)
    print("BLOC D — CONTROLE POSITIF DE LA SOMMATION COMPENSEE, LU AU PLATEAU")
    print("  DESARME =", dis)
    print("  ARME    =", arm)
    print("  Les deux binaires ne different QUE par le bloc Kahan de `jak-hd-physics.gc`.")
    print("=" * W)

    print("\n-- 0. OU EST LE POINT DE PARCAGE (course DESARMEE : `pe` constant au dernier chiffre) --")
    for k in sorted(bd):
        a, b = plateau_window(bd[k])
        last = bd[k][-1]
        print(f"   c={k[0]} ax={k[1]} : plateau f={a}..{b}   fin de fenetre f={last[0]}"
              f" (pe={last[1]:.7f}, dint={last[2]:.7f})")
    print("   => la DERNIERE frame n'est pas le plateau : `dint` y est encore non nul et `pe` y bouge.")

    print("\n-- D1/D2. `pe` AU PLATEAU (f=100..160), et `dint` qui le produit --")
    print(f"   {'c/ax':9s} | {'DES p50':>11s} {'DES dint=0':>11s} | {'ARM p50':>11s} {'ARM dint=0':>11s} | {'rapport':>8s}")
    rats = []
    for k in sorted(ba):
        dv = [pe for f, pe, di in bd[k] if 100 <= f <= 160]
        av = [pe for f, pe, di in ba[k] if 100 <= f <= 160]
        dz = sum(1 for f, pe, di in bd[k] if 100 <= f <= 160 and di == 0.0)
        az = sum(1 for f, pe, di in ba[k] if 100 <= f <= 160 and di == 0.0)
        md, ma = st.median(dv), st.median(av)
        r = ma / md if md else float('nan')
        rats.append(r)
        print(f"   c={k[0]} ax={k[1]}  | {md:11.7f} {dz:5d}/{len(dv):<5d} | {ma:11.7f} {az:5d}/{len(av):<5d} | {r:8.3f}")
    print(f"   => rapport ARME/DESARME : min {min(rats):.3f}  med {st.median(rats):.3f}  max {max(rats):.3f}")

    print("\n-- LE RESIDU EN PAS DE FLOTTANT (le plancher de bruit du bloc C, declare a cote du chiffre) --")
    print(f"   un pas complet sur les trois axes vaut {QNORM:.4f} u = {QNORM/B0_U:.7f} B0"
          f" = {QNORM/U_PER_M*1000:.4f} mm")
    for k in sorted(ba):
        md = st.median([pe for f, pe, di in bd[k] if 100 <= f <= 160])
        ma = st.median([pe for f, pe, di in ba[k] if 100 <= f <= 160])
        print(f"   c={k[0]} ax={k[1]} : {md*B0_U/QNORM:6.2f} pas -> {ma*B0_U/QNORM:6.2f} pas"
              f"   ({md*B0_U/U_PER_M*1000:.4f} mm -> {ma*B0_U/U_PER_M*1000:.4f} mm)")

    print("\n-- D3. `sigma30` : ecart-type des 30 dernieres frames de `PHYSRINGA` --")
    def sig(d):
        o = {}
        for k, v in d.items():
            for i, nm in ((1, 'v'), (2, 'ap'), (3, 'lat')):
                o[(k[0], k[1], nm)] = st.pstdev([x[i] for x in v[-30:]])
        return o
    sd, sa = sig(rd), sig(ra)
    print(f"   series NON NULLES : DESARME {sum(1 for v in sd.values() if v):2d}/{len(sd)}"
          f"   ARME {sum(1 for v in sa.values() if v):2d}/{len(sa)}")
    for k in sorted(sd):
        print(f"   c={k[0]} l={k[1]} {k[2]:4s} : {sd[k]:.9f} -> {sa[k]:.9f}")

    print("\n-- `rgap` (cible du ressort <-> pose d'auteur) : NE DOIT PAS BOUGER, ce cycle n'y touche pas --")
    for k in sorted(qd):
        print(f"   c={k[0]} ax={k[1]} : {qd[k][0]:.7f} -> {qa[k][0]:.7f}"
              + ("   IDENTIQUE" if qd[k][0] == qa[k][0] else "   <<< DIFFERENT"))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
