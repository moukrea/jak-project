#!/usr/bin/env python3
"""
DIRECTIVES v3fee554599 — cycle 84.  SECTION NOMMEE : SPEC 22 (excursion d'apex), SPEC 21 (la
saturation qui la borne).  Zero build, zero course neuve, zero ligne de moteur.

CE QUE LE CYCLE 83 A PUBLIE D'AVANCE, ET QUE CE FICHIER EXECUTE (commit 9f5417a03a) :
  « le producteur est nul quand la pose ne change pas ET ne croit pas avec l'ampleur du
    changement [...] Test : ablation par terme, meme mesure des deux cotes. »
L'ablation par INTERVENTION demandait une course par terme. La trace archivee porte deja la
decomposition exacte au meme argmax (PHYSAPEXT/PHYSAPEXD) et le septuplet d'etages du solveur
(PHYSSTGW) : la meme question se pose donc sans course, et sur une population, pas sur un extremum.

L'IDENTITE QUI PORTE TOUT (jak-hd-physics.gc [NOTE-338], phys-room.gc:1583-1608) :
  e = (p_sim - p_auth) + R_auth.(rot - I).lc + R_auth.rot.(T - I).lc
       \\___ tp ___/      \\______ rp ______/    \\_______ dp _______/
`tp` et `dp` sont EMIS ; `rp` se DERIVE (rp = e - tp - dp). Les six valeurs sont relevees AU MEME
ARGMAX que `apex`, donc sur LA MEME FRAME. |e| == apex EST le controle de lecture de ce fichier :
s'il ne tient pas, rien de ce qui suit ne vaut et le script sort en echec.

NATURE     : trois VECTEURS en unites de B0 (602 u, sa §6) ; des ANGLES en degres ; des LONGUEURS
             rapportees a B0 pour les etages.
REPERE     : le MONDE, difference de deux points de la MEME frame (pose simulee ecrite, pose
             d'auteur du meme joint). `ang` est RELATIF A L'ATTACHE (l'ancre pour l=0, le parent
             SIMULE pour l=1) — une deviation propre, non additive le long de la chaine.
POPULATION : 186 fenetres par chaine = 31 animations x 6 pilotages, 90 frames chacune.
             `PHYSSTGW` est la version A PORTEE DE FENETRE du septuplet (`PHYSSTG` est un maximum
             courant de PHASE, defaut connu et documente phys-room.gc:1778-1790 — non utilise ici).
ENTREE     : `acc` de PHYSACC (`phys-tip-stim`), le stimulus REELLEMENT recu par la fenetre.
ABSENT     : a la pose d'auteur les trois termes, les deux angles et les sept etages valent 0.0000.
"""
import re, math, sys, statistics as st

L = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.c81-armed.log'
B0 = 602.0
BLEN = {0: (1040.4951, 140.4159), 1: (1039.0349, 144.2314)}   # PHYSBONE de la trace

rx = {
 'AP' : re.compile(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.]+) ax=([-\d.]+) ay=([-\d.]+)'),
 'AP2': re.compile(r'^PHYSAPEX2 c=(\d+) a=(\d+) d=(\d+) az=([-\d.]+)'),
 'T'  : re.compile(r'^PHYSAPEXT c=(\d+) a=(\d+) d=(\d+) tx=([-\d.]+) ty=([-\d.]+) tz=([-\d.]+)'),
 'D'  : re.compile(r'^PHYSAPEXD c=(\d+) a=(\d+) d=(\d+) dx=([-\d.]+) dy=([-\d.]+) dz=([-\d.]+)'),
 'ACC': re.compile(r'^PHYSACC c=(\d+) a=(\d+) d=(\d+) acc=([-\d.]+)'),
}
rxg = re.compile(r'^PHYSGRAD c=(\d+) a=(\d+) d=(\d+) l=(\d+) amp=([-\d.]+) ang=([-\d.]+)')
rxw = re.compile(r'^PHYSSTGW c=(\d+) a=(\d+) d=(\d+) st=(\d+) jt=([-\d.]+)')
rxr = re.compile(r'^PHYSREBASE c=(\d+) a=(\d+) d=(\d+) fired=([-\d.]+) amax=([-\d.]+)')

W, G, SW, RB = {}, {}, {}, {}
for line in open(L, errors='replace'):
    if line.startswith('PHYSGRAD c='):
        m = rxg.match(line)
        if m: G[(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))] = float(m.group(6))
    elif line.startswith('PHYSSTGW c='):
        m = rxw.match(line)
        if m: SW[(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))] = float(m.group(5))
    elif line.startswith('PHYSREBASE c='):
        m = rxr.match(line)
        if m: RB[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = (float(m.group(4)), float(m.group(5)))
    elif line.startswith('PHYSA'):
        for k, r in rx.items():
            m = r.match(line)
            if not m: continue
            key = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
            w = W.setdefault(key, {}); g = [float(x) for x in m.groups()[3:]]
            if   k == 'AP' : w['apex'], w['ax'], w['ay'] = g
            elif k == 'AP2': w['az'] = g[0]
            elif k == 'T'  : w['tp'] = tuple(g)
            elif k == 'D'  : w['dp'] = tuple(g)
            elif k == 'ACC': w['acc'] = g[0]
            break

def nrm(v): return math.sqrt(sum(c*c for c in v))
def sub(a, b): return tuple(x-y for x, y in zip(a, b))
def dot(a, b): return sum(x*y for x, y in zip(a, b))
def pear(x, y):
    n = len(x)
    if n < 3: return float('nan')
    mx, my = sum(x)/n, sum(y)/n
    sx = math.sqrt(sum((v-mx)**2 for v in x)); sy = math.sqrt(sum((v-my)**2 for v in y))
    return sum((x[i]-mx)*(y[i]-my) for i in range(n))/(sx*sy) if sx > 0 and sy > 0 else float('nan')
def spear(x, y):
    def rk(v):
        s = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0]*len(v)
        for p, i in enumerate(s): r[i] = float(p)
        return r
    return pear(rk(x), rk(y))
def q(v, p): s = sorted(v); return s[int(p*(len(s)-1))]

print(f"trace : {L}")
print(f"fenetres PHYSAPEX {len(W)} (attendu 372)  ·  PHYSGRAD {len(G)} (744)  ·  PHYSSTGW {len(SW)} (2604)")

bad = worst = 0
for k, w in W.items():
    if not all(t in w for t in ('apex','ax','ay','az','tp','dp')): bad += 1; continue
    worst = max(worst, abs(nrm((w['ax'], w['ay'], w['az'])) - w['apex']))
print(f"CONTROLE DE LECTURE  |e| vs apex : ecart max {worst:.3e} B0 · fenetres incompletes {bad}")
print(f"CONTROLE ALGEBRIQUE GRATUIT (phys-room.gc:1770) : l'etage 1 est <= 0.50 B0 PAR ALGEBRE")
for c in (0, 1):
    v = [SW[k] for k in SW if k[0] == c and k[3] == 1]
    print(f"   {'chestL' if c==0 else 'chestR'} : max etage 1 = {max(v):.4f} B0 -> "
          f"{'TIENT' if max(v) <= 0.5001 else 'ECHOUE — instrument faux'}")
if worst > 1e-3 or bad:
    print("FAIL: l'identite ne tient pas."); sys.exit(2)

# =================================================================================================
# 1. LES TROIS TERMES DE L'APEX, ET LEQUEL EST PLAT
for c in (0, 1):
    nm = 'chestL' if c == 0 else 'chestR'
    ks = sorted(k for k in W if k[0] == c)
    E  = [(W[k]['ax'], W[k]['ay'], W[k]['az']) for k in ks]
    TP = [W[k]['tp'] for k in ks]; DP = [W[k]['dp'] for k in ks]
    RP = [sub(sub(E[i], TP[i]), DP[i]) for i in range(len(ks))]
    AC = [W[k]['acc'] for k in ks]
    lo = sorted(range(len(ks)), key=lambda i: AC[i])[:len(ks)//4]
    hi = sorted(range(len(ks)), key=lambda i: AC[i])[-(len(ks)//4):]
    print("\n" + "=" * 100)
    print(f"== 1. LES TROIS TERMES DE L'APEX — {nm}, {len(ks)} fenetres")
    print(f"   entree acc  min {min(AC):.4f}  med {st.median(AC):.4f}  max {max(AC):.4f} u  (x{max(AC)/min(AC):.0f})")
    print(f"   {'terme':>5} {'|.| med':>9} {'|.| max':>9} {'CV':>6} {'proj/|e|':>9} {'Pearson':>8} {'Spearman':>9} {'haut/bas':>9} {'x6 pilot':>9}")
    for lab, V in (('tp', TP), ('rp', RP), ('dp', DP), ('e', E)):
        mags = [nrm(v) for v in V]
        proj = [100.0*dot(V[i], E[i])/(nrm(E[i])**2) if nrm(E[i]) > 0 else 0.0 for i in range(len(ks))]
        rats = []
        for a in range(31):
            vv = []
            for d in range(6):
                kk = (c, a, d)
                if kk not in W: continue
                ee = (W[kk]['ax'], W[kk]['ay'], W[kk]['az'])
                vv.append(nrm({'tp': W[kk]['tp'], 'dp': W[kk]['dp'],
                               'rp': sub(sub(ee, W[kk]['tp']), W[kk]['dp']), 'e': ee}[lab]))
            if len(vv) == 6 and min(vv) > 0: rats.append(max(vv)/min(vv))
        mlo = st.median(mags[i] for i in lo); mhi = st.median(mags[i] for i in hi)
        print(f"   {lab:>5} {st.median(mags):9.4f} {max(mags):9.4f} {st.pstdev(mags)/st.mean(mags):6.3f} "
              f"{st.median(proj):8.1f}% {pear(AC, mags):+8.3f} {spear(AC, mags):+9.3f} {mhi/mlo:9.3f} {st.median(rats):9.2f}")
    rats = []
    for a in range(31):
        vv = [W[(c, a, d)]['acc'] for d in range(6) if (c, a, d) in W]
        if len(vv) == 6 and min(vv) > 0: rats.append(max(vv)/min(vv))
    print(f"   pour reference, l'ENTREE varie de x{st.median(rats):.2f} sur les memes 6 pilotages.")

# =================================================================================================
# 2. LE PLAFOND ANGULAIRE, ET SA FORME CLOSE
print("\n" + "=" * 100)
print("== 2. LA DEVIATION ANGULAIRE PROPRE (degres, max de fenetre) ET LE PLAFOND DE §22 EN ANGLE")
print("   Le filet de §22 (jak-hd-physics.gc:3138-3180) borne |p - t| a  0.50 * B0 * rl,  avec")
print("   rl = blen(l)/blen(0). Le maillon tourne autour de son attache a longueur de MODELE, donc")
print("   la corde 2*blen(l)*sin(t/2) = 0.50*B0*rl  =>  t = 2*asin(0.25*B0/blen(0)) : LE MEME ANGLE")
print("   POUR TOUS LES MAILLONS, independant de l. C'est une prediction close, pas un ajustement.")
for c in (0, 1):
    nm = 'chestL' if c == 0 else 'chestR'
    pred = 2.0*math.degrees(math.asin(0.25*B0/BLEN[c][0]))
    print(f"\n   {nm}  blen = {BLEN[c][0]:.4f} / {BLEN[c][1]:.4f} u   ->   plafond predit {pred:.3f} deg")
    for l in (0, 1):
        ks = sorted(k for k in G if k[0] == c and k[3] == l)
        A  = [G[k] for k in ks]; AC = [W[(k[0], k[1], k[2])]['acc'] for k in ks]
        rats = []
        for a in range(31):
            vv = [G[(c, a, d, l)] for d in range(6) if (c, a, d, l) in G]
            if len(vv) == 6 and min(vv) > 0: rats.append(max(vv)/min(vv))
        print(f"     l={l}  med {st.median(A):7.3f}  p05 {q(A,.05):7.3f}  max {max(A):7.3f} deg"
              f"   ecart du max au plafond predit {100*(max(A)-pred)/pred:+6.2f} %"
              f"   CV {st.pstdev(A)/st.mean(A):5.3f}  Pearson/acc {pear(AC,A):+6.3f}  x6 pilot {st.median(rats):5.2f}")

# =================================================================================================
# 3. LES SEPT ETAGES : OU LA REPONSE MEURT
print("\n" + "=" * 100)
print("== 3. LES SEPT ETAGES DU JOINT RACINE DANS LA MEME FRAME (B0, portee FENETRE)")
print("   0 avant le filet · 1 apres le filet · 2 apres la 1re LONGUEUR · 3 apres la 1re COLLISION")
print("   4 apres les 8 iterations · 5 avant la peau · 6 apres la peau = LA VALEUR LIVREE")
for c in (0, 1):
    nm = 'chestL' if c == 0 else 'chestR'
    ks = sorted({(k[0], k[1], k[2]) for k in SW if k[0] == c})
    print(f"\n   == {nm}   {len(ks)} fenetres")
    print(f"      {'etage':>5} {'med':>8} {'p05':>8} {'p95':>8} {'max':>8} {'CV':>6} {'Pear/acc':>9} {'x6 pilot':>9}")
    for s in range(7):
        V = [SW[(k[0], k[1], k[2], s)] for k in ks]
        AC = [W[k]['acc'] for k in ks]
        rats = []
        for a in range(31):
            vv = [SW[(c, a, d, s)] for d in range(6) if (c, a, d, s) in SW]
            if len(vv) == 6 and min(vv) > 0: rats.append(max(vv)/min(vv))
        print(f"      {s:5d} {st.median(V):8.4f} {q(V,.05):8.4f} {q(V,.95):8.4f} {max(V):8.4f} "
              f"{st.pstdev(V)/st.mean(V):6.3f} {pear(AC,V):+9.3f} {st.median(rats):9.2f}")
    s0 = [SW[(k[0], k[1], k[2], 0)] for k in ks]; s6 = [SW[(k[0], k[1], k[2], 6)] for k in ks]
    n = len(ks)
    below = sum(1 for v in s0 if v <= 0.42); soft = sum(1 for v in s0 if 0.42 < v <= 0.66)
    hard  = sum(1 for v in s0 if v > 0.66)
    print(f"      REGIME DU FILET sur la demande brute (etage 0). La Pade de :3167-3169 rend")
    print(f"      EXACTEMENT 1.0 des xr >= 3, soit dd > kn + 3*cp = 0.66 B0 : au-dela, ecretage DUR.")
    print(f"         sous le genou  (<= 0.42 B0, filet inerte)  {below:3d}/{n}  ({100*below/n:5.1f} %)")
    print(f"         bande DOUCE    (0.42 - 0.66 B0)            {soft:3d}/{n}  ({100*soft/n:5.1f} %)")
    print(f"         ECRETAGE DUR   (> 0.66 B0)                 {hard:3d}/{n}  ({100*hard/n:5.1f} %)")
    print(f"      ce que le filet retire : med {st.median(a-b for a,b in zip(s0,s6)):.4f} B0  max {max(a-b for a,b in zip(s0,s6)):.4f} B0")

# =================================================================================================
# 4. GARDE DE VACUITE
print("\n" + "=" * 100)
print("== 4. GARDE DE VACUITE — la demande brute est-elle un artefact de FRONTIERE DE FENETRE ?")
print("   Une salle qui change d'animation et de pilotage toutes les 90 frames peut fabriquer un")
print("   pic de demande sur la discontinuite seule (x74 mesure au cycle 52). Les deux temoins que")
print("   la trace porte deja : `fired` (frames ou le rebase de §37 a agi) et `amax` (plus grand")
print("   deplacement de l'ANCRE entre deux frames de la fenetre).")
for c in (0, 1):
    ks = sorted(k for k in RB if k[0] == c)
    s0 = [SW[(k[0], k[1], k[2], 0)] for k in ks]
    fi = [RB[k][0] for k in ks]; am = [RB[k][1] for k in ks]
    print(f"   {'chestL' if c==0 else 'chestR'} : fenetres avec fired>0 : {sum(1 for v in fi if v>0)}/{len(ks)}"
          f"   ·  Pearson  etage0 vs amax {pear(am,s0):+.3f}   etage0 vs fired {pear(fi,s0):+.3f}")
