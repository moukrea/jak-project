"""OU sont les 6 aretes dechirees du pan, et pourquoi `grade` ne les voit pas ?

`grade` a ramene la marche max de 0.900 a 0.450 sur 4 sommets, et `tear` n'a pas bouge (6 -> 6).
Les deux sont vrais seulement si les aretes comptees ne sont pas celles que `grade` a touchees.
On ne devine pas : on les liste, avec leurs poids et leur voisinage.

NATURE : un COMPTE et des POIDS (sans dimension). REPERE : pose de bind, sans objet pour un poids.
BASE   : une arete saine a |dw| <= 0.5 ; le rip brut en avait ZERO sur cette chaine.
"""
import os
import sys

os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
sys.path.insert(0, os.path.abspath('scripts/shell'))
import numpy as np
import physics_c6_volumes as C6
from retarget_hd_models import read_glb, consolidate_buffers, skin_info

SRC = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
js, bufs = read_glb(SRC)
binc = consolidate_buffers(js, bufs)
names, _, _ = skin_info(js, binc)
V, J, W, F = C6._gather_model_vertices(js, binc)
ji = {n: i for i, n in enumerate(names)}
Wd = np.zeros((len(V), len(names)), dtype=np.float64)
for k in range(W.shape[1]):
    np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])

adj = {}
edges = set()
for t in F:
    a, b, c = int(t[0]), int(t[1]), int(t[2])
    for u, v in ((a, b), (b, c), (a, c)):
        edges.add((u, v) if u < v else (v, u))
        adj.setdefault(u, set()).add(v)
        adj.setdefault(v, set()).add(u)

for cn, jn_, donors in (('pantflapL', 'LpantFlap', ('Lknee', 'Lthigh')),
                        ('pantflapR', 'RpantFlap', ('Rknee', 'Rthigh'))):
    col = ji[jn_]
    ws = Wd[:, col]
    own = set(int(x) for x in np.nonzero(ws > 0.0)[0])
    torn = [(u, v) for (u, v) in edges
            if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5]
    print("=== %s : %d aretes dechirees, %d sommets touches par la chaine ==="
          % (cn, len(torn), len(own)))
    print("   %-8s %-8s | %-7s %-7s | %-6s | %s"
          % ("v_bas", "v_haut", "w_bas", "w_haut", "|dw|", "ou va le poids du sommet BAS"))
    for (u, v) in sorted(torn, key=lambda e: -abs(ws[e[0]] - ws[e[1]])):
        lo, hi = (u, v) if ws[u] < ws[v] else (v, u)
        dst = sorted(((names[c], float(Wd[lo][c])) for c in np.nonzero(Wd[lo] > 0)[0]),
                     key=lambda x: -x[1])[:3]
        print("   %-8d %-8d | %-7.3f %-7.3f | %-6.3f | %s"
              % (lo, hi, ws[lo], ws[hi], abs(ws[hi] - ws[lo]),
                 ' · '.join('%s %.2f' % d for d in dst)))
    # LE POINT QUI DECIDE : le sommet BAS porte-t-il du poids des DONNEURS ? `grade` prend le poids
    # aux donneurs declares. Si le sommet bas n'en a pas, la regle n'a rien a lui prendre et le
    # laisse tel quel — ce serait la raison exacte pour laquelle la marche persiste.
    dcols = [ji[d] for d in donors if d in ji]
    los = {(u if ws[u] < ws[v] else v) for (u, v) in torn}
    nodon = [i for i in los if Wd[i][dcols].sum() <= 1e-9]
    print("   sommets BAS sans aucun poids sur %s : %d / %d"
          % (','.join(donors), len(nodon), len(los)))
    if nodon:
        alt = {}
        for i in nodon:
            for c in np.nonzero(Wd[i] > 0)[0]:
                alt[names[c]] = alt.get(names[c], 0.0) + float(Wd[i][c])
        print("   -> leur poids est ailleurs : %s"
              % ' · '.join('%s %.2f' % kv for kv in sorted(alt.items(), key=lambda x: -x[1])[:4]))
    print()
