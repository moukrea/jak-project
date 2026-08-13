"""Ou se trouve la geometrie que la chaine NE tient PAS -- a la racine, ou a la POINTE ?

L'owner, sept fois : « les pointes sont ancrees au meme titre que les racines, et c'est ce qu'il y
a entre les deux qui bouge ». Le cycle precedent a conclu que le degrade est IMPOSSIBLE par le
solveur sur une chaine a deux joints, et que le degre de liberte manquant est un OS.

Cette sonde teste une explication CONCURRENTE, et beaucoup moins chere : le degrade que l'owner
regarde n'est pas celui des JOINTS, c'est celui des SOMMETS. Un sommet de pointe pese a 26 % sur
`head` ne bouge qu'a 74 % de ce que le joint lui dit -- meme si le joint, lui, bouge parfaitement.
Si la propriete de la chaine BAISSE vers la pointe, l'inversion visible est un defaut de PEAU et
aucun os ne la corrigera.

NATURE : une fraction de propriete (poids de peau, sans dimension). Pas une amplitude, pas une
         variance. Le defaut decrit est une FORME le long de la meche, donc on publie un PROFIL,
         jamais un scalaire -- c'est la faute de la 7e passe, encodee.
REPERE : abscisse le long de l'axe racine->pointe de la meche, dans la POSE DE BIND, normalisee
         (0 = joint de racine, 1 = joint de pointe ; >1 = geometrie au-dela du dernier joint).
         Surtout pas le repere monde : on mesure une appartenance, pas un deplacement.
BASE   : ce que la sonde lit quand le defaut est ABSENT. `lbang`/`rbang` sont la reference SAINE
         mesuree dans le meme fichier (cov 0.9874 / 0.9788) -- si leur profil est plat pres de 1.0
         et que celui de `backhair`/`lmidhair`/`rmidhair` plonge vers la pointe, la comparaison est
         interne et ne depend d'aucun seuil invente.
"""
import os
import sys

os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
import numpy as np
from physics_c6_volumes import load_geometry as lg

CHAINS = [
    ('lbang',    ['Lbanga', 'Lbangb', 'Lbangc']),      # reference SAINE (cov 0.9874)
    ('rbang',    ['Rbanga', 'Rbangb', 'Rbangc']),      # reference SAINE (cov 0.9788)
    ('backhair', ['backHair1', 'backHair2']),
    ('lmidhair', ['Lmidhaira', 'Lmidhairb']),
    ('rmidhair', ['Rmidhaira', 'Rmidhairb']),
    ('earL',     ['lEara', 'lEarb']),
    ('earR',     ['rEara', 'rEarb']),
]

g = lg('keira-hd')
V, jn, W, J, P = g['V'], g['names'], g['W'], g['J'], g['P']
ji = {n: i for i, n in enumerate(jn)}
Wd = np.zeros((len(V), len(jn)), dtype=np.float64)
for k in range(W.shape[1]):
    np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])

BINS = [(-9.9, 0.0), (0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.0), (1.0, 1.5), (1.5, 99.0)]
LBL = ["<racine", "0-25%", "25-50%", "50-75%", "75-100%", "100-150%", ">150%"]

print("PROFIL DE PROPRIETE LE LONG DE LA MECHE — poids moyen porte par la CHAINE, par tranche")
print("d'abscisse racine->pointe. Une meche saine tient sa geometrie de plus en plus fort vers la")
print("pointe (la racine, elle, DOIT rester au crane : SPEC 2).")
print()
print("  %-9s %-8s %s" % ("chaine", "n", "  ".join("%-9s" % l for l in LBL)))

rows = {}
for cn, jl in CHAINS:
    cols = [ji[j] for j in jl if j in ji]
    if len(cols) != len(jl):
        print("  %-9s JOINTS ABSENTS DU RIG: %s" % (cn, [j for j in jl if j not in ji]))
        continue
    ws = Wd[:, cols].sum(1)
    sel = np.nonzero(ws > 1e-9)[0]
    a, b = P[cols[0]], P[cols[-1]]
    ax = b - a
    L = float(np.linalg.norm(ax)) or 1.0
    u = ax / L
    t = ((V[sel] - a) @ u) / L

    cells, counts = [], []
    for lo, hi in BINS:
        m = (t >= lo) & (t < hi)
        cells.append(float(ws[sel][m].mean()) if m.any() else float('nan'))
        counts.append(int(m.sum()))
    rows[cn] = (cells, counts, L, len(sel))
    print("  %-9s %-8d %s" % (cn, len(sel),
                              "  ".join(("%-9.3f" % c) if c == c else "%-9s" % "-" for c in cells)))
    print("  %-9s %-8s %s" % ("", "(n par tranche)",
                              "  ".join("%-9d" % c for c in counts)))

print()
print("LECTURE — la question a laquelle ce tableau repond, et une seule :")
print("  le poids porte par la chaine MONTE-t-il ou DESCEND-il vers la pointe ?")
for cn, _ in CHAINS:
    if cn not in rows:
        continue
    cells, counts, L, n = rows[cn]
    body = [(c, k, LBL[i]) for i, (c, k) in enumerate(zip(cells, counts)) if c == c and k >= 3 and BINS[i][0] >= 0.0]
    if len(body) < 2:
        print("  %-9s pas assez de tranches peuplees pour conclure" % cn)
        continue
    first, last = body[0], body[-1]
    d = last[0] - first[0]
    verdict = "MONTE vers la pointe (sain)" if d > 0.02 else (
        "DESCEND vers la pointe (DEFAUT)" if d < -0.02 else "plat")
    print("  %-9s %s %.3f -> %s %.3f   ecart %+0.3f   %s"
          % (cn, first[2], first[0], last[2], last[0], d, verdict))
