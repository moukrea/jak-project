"""Measure the `grade` operator on Keira's mid-hair junction.

Two conditions, and BOTH must hold — closing the first alone is the jak-hd rule that was rejected
for detaching a coiffe from the skull:
  1. `tear` falls on rmidhair/lmidhair and does not rise anywhere else;
  2. the graded ring stays ANCHORED — the vertices it lifts must end up roughly half-held by
     `head`, not fully owned by the strand, and no vertex that was pure scalp may become
     strand-dominant.
"""
import os
import sys

os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
sys.path.insert(0, os.path.abspath('scripts/shell'))
import numpy as np
import physics_c7_reskin as RS
from retarget_hd_models import read_glb, consolidate_buffers, write_glb, gc_glb, skin_info
import physics_c6_volumes as C6

SRC = 'decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb'
CFG = '.autoport/.grade_cand.txt'
CHAINS = {'rmidhair': ['Rmidhaira', 'Rmidhairb'], 'lmidhair': ['Lmidhaira', 'Lmidhairb'],
          'lbang': ['Lbanga', 'Lbangb', 'Lbangc'], 'rbang': ['Rbanga', 'Rbangb', 'Rbangc'],
          'backhair': ['backHair1', 'backHair2'], 'earL': ['lEara', 'lEarb'],
          'earR': ['rEara', 'rEarb']}


def snapshot(js, binc):
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


def tears(names, Wd, edges):
    ji = {n: i for i, n in enumerate(names)}
    out = {}
    for cn, jl in CHAINS.items():
        cols = [ji[j] for j in jl if j in ji]
        if not cols:
            continue
        ws = Wd[:, cols].sum(1)
        own = set(int(x) for x in np.where(ws > 0.0)[0])
        out[cn] = (sum(1 for (u, v) in edges
                       if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5), ws)
    return out


js0, b0 = read_glb(SRC)
binc0 = consolidate_buffers(js0, b0)
n0, V0, Wd0, E0 = snapshot(js0, binc0)
T0 = tears(n0, Wd0, E0)

# UNE regle par CHAINE, pas par joint : `tear` se mesure sur le poids SOMME de la chaine, donc
# c'est cette somme qu'il faut graduer.  Grader joint par joint bornait la marche de `Rmidhaira`
# pendant que celle de `Rmidhaira + Rmidhairb` restait a 1.0 — mesure du 2026-08-12 : 82 -> 68.
STEP = float(os.environ.get('GRADE_STEP', '0.45'))
open(CFG, 'w').write("[model keira-hd]\n" + "".join(
    "grade %s chain=%s from=head step=%s\n" % (jl[0], ",".join(jl), STEP)
    for jl in CHAINS.values()))
cfg = RS.load_cfg(CFG)
js, bufs = read_glb(SRC)
binc = consolidate_buffers(js, bufs)
rep = RS.apply_model(js, binc, cfg['keira-hd'], verbose=False)
for ln in rep:
    print("[reskin]%s" % ln)
n1, V1, Wd1, E1 = snapshot(js, binc)
T1 = tears(n1, Wd1, E1)

print()
print("%-10s %8s %8s" % ("chain", "tear", "after"))
for cn in CHAINS:
    if cn in T0 and cn in T1:
        flag = ""
        if T1[cn][0] > T0[cn][0]:
            flag = "   <-- WORSE"
        print("%-10s %8d %8d%s" % (cn, T0[cn][0], T1[cn][0], flag))

# ---------------------------------------------------------------------------------------------
# DE QUELLE NATURE EST CE QUI RESTE ?  `_grade` rapporte une marche max de 0.500 alors que `tear`
# en compte encore : les deux ne peuvent donc pas regarder le meme jeu d'aretes.  On tranche ici,
# avec des nombres, au lieu de supposer.  Deux causes possibles et elles n'ont pas le meme remede :
#   - SEAM : les deux extremites occupent la MEME position 3D (duplicata de couture UV/normale).
#     Aucune arete ne les relie, donc aucun lissage ne peut les rapprocher — le remede est
#     l'invariant de soudure : des sommets coincidents portent des poids identiques.
#   - EDGE : une vraie arete que le lissage n'a pas vue (primitive differente, ou pas convergee).
ji1 = {n: i for i, n in enumerate(n1)}
pos = {}
for i in range(len(V1)):
    pos.setdefault((round(float(V1[i][0]), 3), round(float(V1[i][1]), 3),
                    round(float(V1[i][2]), 3)), []).append(i)
coinc = {i: g for g in pos.values() if len(g) > 1 for i in g}
print()
print("NATURE DE CE QUI RESTE (seam = duplicata coincident, edge = vraie arete) :")
for cn, jl in CHAINS.items():
    cols = [ji1[j] for j in jl if j in ji1]
    if not cols:
        continue
    ws = Wd1[:, cols].sum(1)
    own = set(int(x) for x in np.where(ws > 0.0)[0])
    torn = [(u, v) for (u, v) in E1 if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5]
    if not torn:
        print("  %-9s aucune arete dechiree" % cn)
        continue
    seam = sum(1 for (u, v) in torn
               if (round(float(V1[u][0]), 3), round(float(V1[u][1]), 3), round(float(V1[u][2]), 3))
               == (round(float(V1[v][0]), 3), round(float(V1[v][1]), 3), round(float(V1[v][2]), 3)))
    dup = sum(1 for (u, v) in torn if (u in coinc) or (v in coinc))
    print("  %-9s reste=%-4d  marche max=%.3f  extremites coincidentes=%d  touche un duplicata=%d"
          % (cn, len(torn), max(abs(ws[u] - ws[v]) for (u, v) in torn), seam, dup))

ji = {n: i for i, n in enumerate(n1)}
hd = ji['head']
print()
print("ANCHORING of the ring that was lifted (must stay roughly half-held by `head`):")
for cn, jl in CHAINS.items():
    cols = [ji[j] for j in jl]
    a = Wd0[:, cols].sum(1)
    b = Wd1[:, cols].sum(1)
    lifted = np.where(b > a + 1e-6)[0]
    if not len(lifted):
        print("  %-9s nothing lifted" % cn)
        continue
    newly_dominant = int(((a < 0.5) & (b >= 0.5)).sum())
    pure_scalp_flipped = int(((a <= 1e-9) & (b > 0.5)).sum())
    print("  %-9s lifted=%d  strand weight there: %.3f -> %.3f (max %.3f)   head kept: %.3f"
          % (cn, len(lifted), float(a[lifted].mean()), float(b[lifted].mean()),
             float(b[lifted].max()), float(Wd1[lifted, hd].mean())))
    print("            newly strand-dominant=%d   pure-scalp vertices flipped past 0.5=%d %s"
          % (newly_dominant, pure_scalp_flipped,
             "<-- DETACHMENT RISK" if pure_scalp_flipped else "(none — anchoring held)"))
