"""Are the torn vertices STRAND geometry mis-weighted, or SCALP geometry correctly weighted?

The two readings demand opposite fixes, so guessing is not allowed:

  A) they are strand geometry that the artist left on `head` -> the skinning is wrong, and the fix
     is a weight repair (which `transfer`/`grow` provably cannot do: grow inserts at wt=1e-6 and the
     profile maps that to ~1e-5);
  B) they are the SCALP at the hair/skull junction -> the skinning is RIGHT (SPEC 2 wants the root
     welded to the skull) and the broken geometry the owner sees is the strand swinging away from a
     junction that must stay closed -> the fix is on the physics side (root/bend), not the weights.

Discriminator: a junction is a CONTIGUOUS BORDER. Scalp vertices at a junction are adjacent to
strand vertices on one side and to head-only vertices on the other, and they sit at the strand's
attachment end. Mis-weighted strand vertices are surrounded by strand vertices and sit along it.
"""
import os
import sys
import json

os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
import numpy as np
from physics_c6_volumes import load_geometry as lg

g = lg('keira-hd')
V, jn, W, J, F, P = g['V'], g['names'], g['W'], g['J'], g['F'], g['P']
ji = {n: i for i, n in enumerate(jn)}
Wd = np.zeros((len(V), len(jn)), dtype=np.float64)
for k in range(W.shape[1]):
    np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])

adj = {}
for t in F:
    a, b, c = int(t[0]), int(t[1]), int(t[2])
    for u, v in ((a, b), (b, c), (a, c)):
        adj.setdefault(u, set()).add(v)
        adj.setdefault(v, set()).add(u)

for cn, jl in (('rmidhair', ['Rmidhaira', 'Rmidhairb']), ('lmidhair', ['Lmidhaira', 'Lmidhairb'])):
    cols = [ji[j] for j in jl]
    ws = Wd[:, cols].sum(1)
    own = set(int(x) for x in np.where(ws > 0.0)[0])
    torn = [(u, v) for (u, v) in
            {(min(u, v), max(u, v)) for u in adj for v in adj[u]}
            if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5]
    low = sorted({(u if ws[u] < ws[v] else v) for (u, v) in torn})

    # strand extent from the two joint bind positions
    a, b = P[ji[jl[0]]], P[ji[jl[-1]]]
    ax = b - a
    L = float(np.linalg.norm(ax))
    u_ax = ax / L
    head = P[ji['head']]

    print("=== %s : %d torn edges, %d low-side vertices, strand %.0fu ===" % (cn, len(torn), len(low), L))
    n_strand_nb = n_headonly_nb = 0
    frac_strand_nb = []
    for vi in low:
        nb = adj.get(vi, set())
        s = sum(1 for x in nb if ws[x] > 0.5)
        h = sum(1 for x in nb if ws[x] <= 1e-9)
        n_strand_nb += s
        n_headonly_nb += h
        frac_strand_nb.append(s / max(len(nb), 1))
    fr = np.array(frac_strand_nb)
    dpar = np.array([float(np.dot(V[i] - a, u_ax)) for i in low])
    dperp = np.array([float(np.linalg.norm((V[i] - a) - np.dot(V[i] - a, u_ax) * u_ax)) for i in low])
    dhead = np.array([float(np.linalg.norm(V[i] - head)) for i in low])
    dstrandline = dperp

    print("  neighbours of the low-side vertices: %d strand-owned, %d head-only" % (n_strand_nb, n_headonly_nb))
    print("  fraction of each one's neighbours that are strand-owned: "
          "min=%.2f med=%.2f max=%.2f   (a junction border sits well below 1.0)"
          % (fr.min(), np.median(fr), fr.max()))
    print("  along strand axis : min=%.0f%% med=%.0f%% max=%.0f%% of %.0fu"
          % (100 * dpar.min() / L, 100 * np.median(dpar) / L, 100 * dpar.max() / L, L))
    print("  perpendicular distance to the strand axis: med=%.0fu max=%.0fu" % (np.median(dstrandline), dstrandline.max()))
    print("  distance to the `head` joint: med=%.0fu   (strand joints are at %.0fu and %.0fu)"
          % (np.median(dhead), np.linalg.norm(a - head), np.linalg.norm(b - head)))
    # contiguity: how many of the low-side vertices are adjacent to another low-side vertex
    lowset = set(low)
    contig = sum(1 for vi in low if any(x in lowset for x in adj.get(vi, ())))
    print("  contiguous with another low-side vertex: %d/%d  (a border is contiguous)" % (contig, len(low)))
