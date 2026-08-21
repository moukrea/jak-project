#!/usr/bin/env python3
"""
DIRECTIVES v3fee554599 — cycle 83.

L'EXCURSION D'APEX EST-ELLE UNE REPONSE A L'ENTREE QUE L'ANCRE IMPOSE ?
Mesure sur la trace ARCHIVEE. Zero build, zero course.

L'ENTREE, ET C'EST LA OU LE CYCLE 80c S'ETAIT TROMPE. Le torse ne se decrit pas par la
translation de son centre : la poitrine est au bout d'un bras de levier de 1042 u, et une
ROTATION du torse y produit une acceleration que la translation du centre ne voit pas.
On transporte donc le point d'attache de BIND (mesure sur les inverseBindMatrices du glb livre,
constant dans le repere de `chest`) par la 4x4 ECRITE de `chest` a chaque frame, puis on prend la
seconde difference finie. AUCUNE physique n'entre dans cette grandeur : `chest` n'est simule par
rien (verifie au cycle 82 : 27 528 flottants identiques entre course armee et course ablatee).

NATURE     : une ACCELERATION, seconde difference finie de la position MONDE, en u/f^2.
             1 g = 11.162 u/f^2 ; 4096 u = 1 m ; B0 = 602 u.
REPERE     : le MONDE, frame ecrite. La sortie (`apex`) est en B0, repere monde, contre la pose
             d'auteur de la meme frame — et le cycle 82 a etabli que cette pose EST le modele
             livre a 0,6-1,3 mm pres.
POPULATION : 31 animations. Une entree et une sortie par animation, appariees par `a`.
             La sortie est prise dans la sous-fenetre SANS PILOTAGE (d=5) : c'est la que 85 % de
             l'excursion vit deja (cycle 80), donc la que la question se pose.
ABSENT     : une chaine qui ne repondrait pas a son ancre rendrait une correlation nulle et une
             sortie plate ; une chaine qui y repond rendrait une correlation positive forte.
"""
import re, math, statistics as st, sys

L = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.c81-armed.log'
G, B0, U = 11.162, 602.0, 4096.0
BIND = {0: (379.904, -957.859, -155.239), 2: (-379.908, -957.859, -155.239)}

rx_m = re.compile(r'^PHYSJTW k=(\d+) j=(\d+) row=(\d+) x=([-\d.]+) y=([-\d.]+) z=([-\d.]+)')
rx_k = re.compile(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+)')
rx_ap = re.compile(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.]+)')
M, AN, AP = {}, {}, {}
for line in open(L, errors='replace'):
    if line.startswith('PHYSJTW k='):
        m = rx_m.match(line)
        if m: M.setdefault((int(m.group(1)), int(m.group(2))), [None]*4)[int(m.group(3))] = \
              (float(m.group(4)), float(m.group(5)), float(m.group(6)))
    elif line.startswith('PHYSJTWK'):
        m = rx_k.match(line)
        if m: AN[int(m.group(1))] = int(m.group(2))
    elif line.startswith('PHYSAPEX c='):
        m = rx_ap.match(line)
        if m: AP[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = float(m.group(4))

def world(mm, loc):
    return tuple(mm[3][c] + sum(loc[r]*mm[r][c] for r in range(3)) for c in range(3))
def pearson(x, y):
    n = len(x); mx, my = sum(x)/n, sum(y)/n
    sx = math.sqrt(sum((v-mx)**2 for v in x)); sy = math.sqrt(sum((v-my)**2 for v in y))
    return sum((x[i]-mx)*(y[i]-my) for i in range(n))/(sx*sy) if sx and sy else float('nan')
def spearman(x, y):
    def rk(v):
        s = sorted(range(len(v)), key=lambda i: v[i]); r = [0]*len(v)
        for p, i in enumerate(s): r[i] = p
        return r
    return pearson(rk(x), rk(y))

print("DIRECTIVES v3fee554599")
print(f"trace : {L}")
KS = sorted(set(k for k, _ in M))
BY = {}
for k in KS: BY.setdefault(AN.get(k, -1), []).append(k)
for a in BY: BY[a].sort()
print(f"animations = {len(BY)}   frames d=5 = {len(KS)}")

for jj, chain, ci in ((0, 'chestL', 0), (2, 'chestR', 1)):
    X, Y, NAMES = [], [], []
    for a in sorted(BY):
        ks = [k for k in BY[a] if M.get((k, 4)) and None not in M[(k, 4)]]
        if len(ks) < 3: continue
        P = [world(M[(k, 4)], BIND[jj]) for k in ks]
        acc = [math.sqrt(sum((P[i+1][c] - 2*P[i][c] + P[i-1][c])**2 for c in range(3)))
               for i in range(1, len(P)-1)]
        y = AP.get((ci, a, 5))
        if y is None or not acc: continue
        X.append(max(acc)/G); Y.append(y); NAMES.append(a)
    print(f"\n== {chain} : {len(X)} animations appariees")
    print(f"   ENTREE  |a| au point d'attache de bind, MAX de la fenetre : "
          f"min={min(X):.3f} g  med={st.median(X):.3f} g  max={max(X):.3f} g  -> etendue x{max(X)/max(min(X),1e-9):.0f}")
    print(f"   SORTIE  apex (d=5) : min={min(Y):.4f}  med={st.median(Y):.4f}  max={max(Y):.4f} B0"
          f"  -> etendue x{max(Y)/max(min(Y),1e-9):.2f}")
    print(f"   CORRELATION  Pearson={pearson(X, Y):+.3f}   Spearman={spearman(X, Y):+.3f}")
    lo = sorted(zip(X, Y, NAMES))[:5]; hi = sorted(zip(X, Y, NAMES))[-5:]
    print(f"   les 5 entrees les PLUS FAIBLES : " + " ".join(f"a{n}({x:.2f}g->{y:.3f})" for x, y, n in lo))
    print(f"   les 5 entrees les PLUS FORTES  : " + " ".join(f"a{n}({x:.2f}g->{y:.3f})" for x, y, n in hi))
    q = sorted(zip(X, Y)); h = len(q)//2
    print(f"   apex median des {h} entrees basses = {st.median([y for _, y in q[:h]]):.4f} B0 ; "
          f"des {len(q)-h} hautes = {st.median([y for _, y in q[h:]]):.4f} B0")
