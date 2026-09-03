#!/usr/bin/env python3
"""c73_apexdecomp.py — LA DECOMPOSITION DE L'APEX, ET LA FUITE DU FILET DE §22.

    python3 .autoport/c73_apexdecomp.py <log-c73> [<log-reference-c72A>]

Repond aux predictions de `c73-predictions.txt` (md5 d197af804ea75aa856c1145e6764382e).

NATURE des grandeurs : toutes en unites de B0 (602 u), sans dimension. REPERE : le MONDE,
difference de deux points de LA MEME frame (pose simulee moins pose d'auteur du meme joint).
Les six composantes de `tp` et `dp` sont relevees AU MEME ARGMAX que `apex`, donc sur la meme
frame que lui : c'est ce qui autorise a les soustraire. LIGNE DE BASE : 0.0000 partout a la pose
d'auteur.

`rp` NE VIENT PAS DU MOTEUR : il est DERIVE, `rp = e - tp - dp`. C'est voulu — une quatrieme
mesure emise ne pourrait contredire personne, tandis qu'une derivee transforme l'identite en
controle. Voir [NOTE-338].
"""
import math
import re
import sys

B0 = 602.0


def rd(p):
    return open(p, errors='ignore').read()


def vecs(t):
    """(c, a, d) -> (e, tp, dp), chacun un triplet en B0. Cle commune aux trois emetteurs."""
    e, tp, dp = {}, {}, {}
    for m in re.finditer(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.e+]+) ax=([-\d.e+]+)'
                         r' ay=([-\d.e+]+)', t, re.M):
        e[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = [float(m.group(5)),
                                                                  float(m.group(6)), None]
    for m in re.finditer(r'^PHYSAPEX2 c=(\d+) a=(\d+) d=(\d+) az=([-\d.e+]+)', t, re.M):
        k = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if k in e:
            e[k][2] = float(m.group(4))
    for m in re.finditer(r'^PHYSAPEXT c=(\d+) a=(\d+) d=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+)'
                         r' tz=([-\d.e+]+)', t, re.M):
        tp[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = [float(m.group(i))
                                                                   for i in (4, 5, 6)]
    for m in re.finditer(r'^PHYSAPEXD c=(\d+) a=(\d+) d=(\d+) dx=([-\d.e+]+) dy=([-\d.e+]+)'
                         r' dz=([-\d.e+]+)', t, re.M):
        dp[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = [float(m.group(i))
                                                                   for i in (4, 5, 6)]
    return e, tp, dp


def nrm(v):
    return math.sqrt(sum(x * x for x in v))


def med(v):
    v = sorted(v)
    return v[len(v) // 2] if v else float('nan')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    t = rd(sys.argv[1])
    e, tp, dp = vecs(t)
    keys = sorted(k for k in e if k in tp and k in dp and e[k][2] is not None)
    out = []
    A = out.append
    A('C73 — LA DECOMPOSITION DE L\'APEX  (predictions md5 d197af804ea75aa856c1145e6764382e)')
    A('')

    # ---- P1/P2 : bit-identite et compte -------------------------------------------------------
    if len(sys.argv) > 2:
        ref = [l for l in rd(sys.argv[2]).splitlines() if l.startswith('PHYS')]
        cur = [l for l in t.splitlines() if l.startswith('PHYS')]
        old = [l for l in cur if not l.startswith(('PHYSAPEXT ', 'PHYSAPEXD '))]
        n = min(len(ref), len(old))
        diff = sum(1 for i in range(n) if ref[i] != old[i])
        first = next((i for i in range(n) if ref[i] != old[i]), None)
        A('P1  %s lignes PHYS ANTERIEURES : ref %d · courante %d · communes %d · DIFFERENTES %d'
          % ('TENUE  ' if (diff == 0 and len(ref) == len(old)) else 'REFUTEE',
             len(ref), len(old), n, diff))
        if first is not None:
            A('      premiere divergence idx %d\n      ref: %s\n      cur: %s'
              % (first, ref[first][:110], old[first][:110]))
        A('P2  %s total PHYS = %d  (engage 44130 = 43386 + 372 + 372)'
          % ('TENUE  ' if len(cur) == 44130 else 'REFUTEE', len(cur)))
    A('')

    # ---- la decomposition ----------------------------------------------------------------------
    rows = []
    for k in keys:
        E, T, D = e[k], tp[k], dp[k]
        R = [E[i] - T[i] - D[i] for i in range(3)]
        rows.append((k, nrm(E), nrm(T), nrm(D), nrm(R)))
    A('POPULATION : %d fenetres (chaine x animation x pilotage)' % len(rows))
    A('                    |e|      |tp|     |dp|     |rp|')
    A('   moyenne       %8.4f %8.4f %8.4f %8.4f  B0'
      % tuple(sum(r[i] for r in rows) / max(1, len(rows)) for i in (1, 2, 3, 4)))
    A('   mediane       %8.4f %8.4f %8.4f %8.4f  B0'
      % tuple(med([r[i] for r in rows]) for i in (1, 2, 3, 4)))
    A('   maximum       %8.4f %8.4f %8.4f %8.4f  B0'
      % tuple(max(r[i] for r in rows) for i in (1, 2, 3, 4)))
    A('')
    A('P3  %s |rp| median = %.4f B0   (engage < 0.25 : magnitude d\'une ROTATION, pas d\'un'
      % ('TENUE  ' if med([r[4] for r in rows]) < 0.25 else 'REFUTEE', med([r[4] for r in rows])))
    A('      troisieme terme dominant ni d\'un residu de calcul)')
    calm = min(rows, key=lambda r: r[1])
    A('P4  %s fenetre la plus calme (c=%d a=%d d=%d) : |e|=%.4f |tp|=%.4f |dp|=%.4f |rp|=%.4f'
      % ('TENUE  ' if max(calm[2], calm[3], calm[4]) < 0.05 else 'REFUTEE',
         calm[0][0], calm[0][1], calm[0][2], calm[1], calm[2], calm[3], calm[4]))
    A('      (engage : les trois termes < 0.05 B0 — la ligne de base sans laquelle rien n\'a'
      '  d\'echelle)')
    # LE PLAFOND ALGEBRIQUE DE `tp` EST PAR CHAINE, ET IL EST PLUS SERRE QUE 0.50 B0.
    # `tp` est une somme PONDEREE sur les maillons (poids `ax` du mesh livre), pas la deviation
    # d'un maillon. Le filet borne le maillon 0 a 0.50 B0 et le maillon 1 a 0.50 B0 de son PARENT,
    # donc en somme telescopique a 0.50 * (1 + blen1/blen0). Le plafond de la somme ponderee vaut
    # donc `w0*0.50 + w1*0.5675`, soit 0.4756 (chestL) et 0.4775 (chestR) — et non 0.50.
    # Ma prediction ecrite comparait a 0.51 : c'etait TROP LACHE, je le corrige a la hausse de
    # severite, pas a la baisse.
    CAP = {0: 0.8584 * 0.50 + 0.0818 * 0.5675, 1: 0.9549 * 0.50 + 0.0 * 0.5675}
    over = [r for r in rows if r[2] > CAP[r[0][0]] * 1.02]
    A('P5  %s |tp| max = %.4f B0 contre le plafond ALGEBRIQUE du filet de :3120-3141,'
      % ('TENUE  ' if not over else 'REFUTEE', max(r[2] for r in rows)))
    A('      pondere par les poids `ax` livres : %.4f (chestL) / %.4f (chestR).'
      % (CAP[0], CAP[1]))
    A('      %d fenetre(s) sur %d au-dessus (%.1f %%), pire depassement +%.1f %%.%s'
      % (len(over), len(rows), 100.0 * len(over) / max(1, len(rows)),
         100.0 * max((r[2] / CAP[r[0][0]] - 1.0) for r in rows),
         '' if not over else '\n      >>> LE FILET FUIT. Il ne PEUT PAS laisser'
                             ' cette valeur au-dessus du plafond a l\'instant ou il\n'
                             '      s\'applique (`ds = kn + cp*tanh(...) < kn + cp` par algebre) :'
                             ' ce qui suit le defait.'))
    A('P6  %s max |dp| = %.4f B0   (engage > 0.20 : le tenseur est un porteur reel)'
      % ('TENUE  ' if max(r[3] for r in rows) > 0.20 else 'REFUTEE', max(r[3] for r in rows)))
    ssum = [(r[2] + r[3] + r[4]) for r in rows]
    A('P7  somme des normes / |e| : mediane %.3f  (1.00 = les trois termes sont colineaires ;'
      % med([(r[2] + r[3] + r[4]) / r[1] for r in rows if r[1] > 1e-9]))
    A('      >1 = ils se compensent, donc en borner UN SEUL deplace l\'apex au lieu de le reduire)')
    A('      somme des normes : moyenne %.4f B0 · max %.4f B0'
      % (sum(ssum) / max(1, len(ssum)), max(ssum)))
    A('')

    # ---- qui domine ? --------------------------------------------------------------------------
    dom = {'tp': 0, 'dp': 0, 'rp': 0}
    for r in rows:
        dom[max((('tp', r[2]), ('dp', r[3]), ('rp', r[4])), key=lambda x: x[1])[0]] += 1
    A('QUI PORTE L\'APEX, fenetre par fenetre : tp %d · dp %d · rp %d  (sur %d)'
      % (dom['tp'], dom['dp'], dom['rp'], len(rows)))
    A('   Part de l\'apex portee par chaque terme, en moyenne des rapports |terme|/|e| :')
    for nm2, i in (('tp (translation)', 2), ('dp (tenseur)', 3), ('rp (rotation)', 4)):
        A('      %-18s %.1f %%' % (nm2, 100.0 * sum(r[i] / r[1] for r in rows if r[1] > 1e-9)
                                   / max(1, len([r for r in rows if r[1] > 1e-9]))))
    print('\n'.join(out))


main()
