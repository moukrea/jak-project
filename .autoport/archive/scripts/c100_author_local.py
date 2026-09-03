#!/usr/bin/env python3
"""DIRECTIVES v3fee554599 — cycle 100.
LE CANAL LOCAL D'AUTEUR DES DEUX JOINTS DE POITRINE. Predictions: .autoport/c100-predictions.txt
NATURE: longueur / B0 (602 u). REPERE: repere LOCAL de `chest`, convention vecteur-ligne.
POPULATION: toutes les cles (animation, frame) emises. JAMAIS un argmax.
ABSENT: si l'animation ne posait pas la poitrine, l'etendue vaudrait 0.0000 B0."""
import sys, re, math, statistics as st

B0 = 602.0
rx_m = re.compile(r'^PHYSJTW k=(\d+) j=(\d+) row=(\d+) x=([-\d.]+) y=([-\d.]+) z=([-\d.]+)')
rx_k = re.compile(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+)')
NAMES = {0:'lBoob',1:'lBooc',2:'rBoob',3:'rBooc',4:'chest',5:'main'}

def read(path):
    M, anim = {}, {}
    for line in open(path, errors='replace'):
        if line.startswith('PHYSJTW k='):
            m = rx_m.match(line)
            if m:
                M.setdefault((int(m.group(1)), int(m.group(2))), [None]*4)[int(m.group(3))] = \
                    (float(m.group(4)), float(m.group(5)), float(m.group(6)))
        elif line.startswith('PHYSJTWK'):
            m = rx_k.match(line)
            if m: anim[int(m.group(1))] = int(m.group(2))
    return M, anim

def local_of(M, k, j):
    """position de j dans le repere de `chest` (j=4), en B0. Convention vecteur-ligne."""
    C = M.get((k,4)); J = M.get((k,j))
    if not C or not J or None in C or None in J: return None
    d = [J[3][i]-C[3][i] for i in range(3)]
    return tuple(sum(d[i]*C[r][i] for i in range(3))/B0 for r in range(3))

def orthonormality(M):
    """controle: les lignes de `chest` sont-elles orthonormees ? sinon la projection est fausse."""
    worst_n, worst_o = 0.0, 0.0
    for (k,j),rows in M.items():
        if j != 4 or None in rows: continue
        for r in range(3):
            worst_n = max(worst_n, abs(math.dist((0,0,0), rows[r]) - 1.0))
        for a,b in ((0,1),(0,2),(1,2)):
            worst_o = max(worst_o, abs(sum(rows[a][i]*rows[b][i] for i in range(3))))
    return worst_n, worst_o

def report(tag, path, j):
    M, anim = read(path)
    wn, wo = orthonormality(M)
    pts = {}
    for (k,jj) in M:
        if jj != j: continue
        p = local_of(M, k, j)
        if p: pts.setdefault(anim.get(k,-1), []).append((k,p))
    allp = [p for v in pts.values() for _,p in v]
    if not allp:
        print(f"{tag}: AUCUN echantillon"); return None
    med = tuple(st.median([p[i] for p in allp]) for i in range(3))
    dev = [math.dist(p, med) for p in allp]
    print(f"\n=== {tag} — {NAMES[j]} dans le repere de `chest` ({path.split('/')[-1]}) ===")
    print(f"  controle d'orthonormalite de `chest` : |lignes|-1 <= {wn:.2e} ; produits croises <= {wo:.2e}")
    print(f"  n={len(allp)} echantillons sur {len(pts)} animations")
    print(f"  mediane locale      = ({med[0]:+.4f}, {med[1]:+.4f}, {med[2]:+.4f}) B0   |.|={math.dist((0,0,0),med):.4f}")
    print(f"  ETENDUE (max ecart a la mediane) = {max(dev):.4f} B0   p50={st.median(dev):.4f}  p90={sorted(dev)[int(.9*len(dev))]:.4f}")
    print(f"  ecart-type par axe  = ({st.pstdev([p[0] for p in allp]):.4f}, {st.pstdev([p[1] for p in allp]):.4f}, {st.pstdev([p[2] for p in allp]):.4f}) B0")
    # dispersion INTER-animation (mediane par animation) vs INTRA
    permed = {a: tuple(st.median([p[i] for _,p in v]) for i in range(3)) for a,v in pts.items()}
    inter = [math.dist(m, med) for m in permed.values()]
    intra = []
    for a,v in pts.items():
        m = permed[a]; intra += [math.dist(p, m) for _,p in v]
    print(f"  dispersion INTER-animation (mediane par anim vs mediane globale) : max={max(inter):.4f}  p50={st.median(inter):.4f} B0")
    print(f"  dispersion INTRA-animation (frame vs mediane de son anim)        : max={max(intra):.4f}  p50={st.median(intra):.4f} B0")
    worst = max(permed.items(), key=lambda kv: math.dist(kv[1], med))
    print(f"  animation la plus ecartee : a={worst[0]}  ecart={math.dist(worst[1],med):.4f} B0")
    return med, max(dev), allp

R = '.autoport/reports/Grecharged-secondary-motion/'
print("DIRECTIVES v3fee554599 — cycle 100 : LE CANAL LOCAL D'AUTEUR DES JOINTS DE POITRINE")
print("predictions md5 bea9b0fbd0d27ae5763ca5a7cefa22c0 (.autoport/c100-predictions.txt)")
L = report("AUTEUR (chestL DESARMEE)", R+'keira-room-x86.c82-LEFTOFF.log', 0)
Rr= report("AUTEUR (chestR DESARMEE)", R+'keira-room-x86.c82-RIGHTOFF.log', 2)
# temoin negatif : le meme joint dans la course ou il EST simule
print("\n--- TEMOIN : le meme joint sur une course ou il EST simule (donc PAS la pose d'auteur) ---")
Ls = report("SIMULE (chestL armee)", R+'keira-room-x86.c82-RIGHTOFF.log', 0)
Rs = report("SIMULE (chestR armee)", R+'keira-room-x86.c82-LEFTOFF.log', 2)
