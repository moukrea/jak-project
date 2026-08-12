"""Sweep `grow=` on the mid-hair transfer.

A plain rescale was INERT (+0.001 ownership, tear 82->81) because the vertices that tear are
100 % `head` — zero weight on the strand joint, therefore outside the patch the rescale acts on.
`grow=U` is the key made for that case: it first extends the patch to vertices within U units.

Two things must be true at once, and the second is the one that kills a naive fix:
  tear must FALL  (PRIORITE 1 closing)
  the SCALP must not follow the strand. The recipe records a rejected jak-hd rule that closed a
  number by lifting scalp vertices and detaching the coiffe from the skull. So we count vertices
  that FLIP from head-owned to strand-owned and report WHERE they are along the strand: flipping
  mid-strand vertices is the cure, flipping vertices at/behind the root is the disease.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.abspath('.autoport'))
sys.path.insert(0, os.path.abspath('scripts/shell'))
import numpy as np
import physics_c7_reskin as RS
from retarget_hd_models import read_glb, consolidate_buffers, write_glb, gc_glb, skin_info
import physics_c6_volumes as C6

SRC = 'decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb'
CHAINS = {'rmidhair': ['Rmidhaira', 'Rmidhairb'], 'lmidhair': ['Lmidhaira', 'Lmidhairb']}
OTHER = {'lbang': ['Lbanga', 'Lbangb', 'Lbangc'], 'rbang': ['Rbanga', 'Rbangb', 'Rbangc'],
         'backhair': ['backHair1', 'backHair2']}


def dense(js, binc):
    names, _, _ = skin_info(js, binc)
    V, J, W, F = C6._gather_model_vertices(js, binc)
    Wd = np.zeros((len(V), len(names)), dtype=np.float64)
    for k in range(W.shape[1]):
        np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])
    edges = set()
    for t in F:
        a, b, c = int(t[0]), int(t[1]), int(t[2])
        for u, v in ((a, b), (b, c), (a, c)):
            edges.add((u, v) if u < v else (v, u))
    return names, V, Wd, edges


def tear_of(names, V, Wd, edges, jl):
    ji = {n: i for i, n in enumerate(names)}
    cols = [ji[j] for j in jl if j in ji]
    ws = Wd[:, cols].sum(1)
    own = set(int(x) for x in np.where(ws > 0.0)[0])
    t = sum(1 for (u, v) in edges if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5)
    return t, ws, float(ws[list(own)].mean())


js0, b0 = read_glb(SRC)
binc0 = consolidate_buffers(js0, b0)
names0, V0, Wd0, edges0 = dense(js0, binc0)
ji0 = {n: i for i, n in enumerate(names0)}

base = {}
for cn, jl in list(CHAINS.items()) + list(OTHER.items()):
    base[cn] = tear_of(names0, V0, Wd0, edges0, jl)
print("BASELINE  " + "  ".join("%s tear=%d cov=%.4f" % (c, base[c][0], base[c][2])
                               for c in ('rmidhair', 'lmidhair', 'lbang', 'rbang', 'backhair')))

# strand axis for reporting flip positions (anchor = most-weighted vertex of the root joint)
axes = {}
for cn, jl in CHAINS.items():
    a = V0[int(np.argmax(Wd0[:, ji0[jl[0]]]))]
    tip = V0[int(np.argmax(Wd0[:, ji0[jl[-1]]]))]
    ax = tip - a
    L = float(np.linalg.norm(ax)) or 1.0
    axes[cn] = (a, ax / L, L)

for grow in (0, 25, 50, 100, 200):
    cfg_path = os.path.join(HERE, 'cand_grow.txt')
    open(cfg_path, 'w').write(
        "[model keira-hd]\n"
        "transfer Rmidhaira from=head cap=0.85 shape=0.85 grow=%d\n"
        "transfer Lmidhaira from=head cap=0.85 shape=0.85 grow=%d\n" % (grow, grow))
    cfg = RS.load_cfg(cfg_path)
    js, bufs = read_glb(SRC)
    binc = consolidate_buffers(js, bufs)
    rep = RS.apply_model(js, binc, cfg['keira-hd'], verbose=False)
    names, V, Wd, edges = dense(js, binc)
    inert = [r for r in rep if r.strip().startswith('!!')]
    line = ["grow=%-4d" % grow]
    for cn in ('rmidhair', 'lmidhair', 'lbang', 'rbang', 'backhair'):
        jl = dict(list(CHAINS.items()) + list(OTHER.items()))[cn]
        t, ws, cov = tear_of(names, V, Wd, edges, jl)
        line.append("%s %d->%d" % (cn, base[cn][0], t))
    print("  ".join(line) + ("   INERT-GUARD:%d" % len(inert) if inert else ""))
    # where did ownership flip?
    for cn, jl in CHAINS.items():
        ji = {n: i for i, n in enumerate(names)}
        cols = [ji[j] for j in jl]
        ws_a = Wd[:, cols].sum(1)
        ws_b = base[cn][1]
        flipped = np.where((ws_b < 0.5) & (ws_a >= 0.5))[0]
        if len(flipped):
            a, u, L = axes[cn]
            t = np.array([float(np.dot(V[i] - a, u)) for i in flipped])
            print("        %-9s flipped=%-4d  along strand: min=%.0f%% med=%.0f%% max=%.0f%% of %.0fu"
                  % (cn, len(flipped), 100 * t.min() / L, 100 * np.median(t) / L, 100 * t.max() / L, L))
        else:
            print("        %-9s flipped=0" % cn)
