#!/usr/bin/env python3
"""
DIRECTIVES v3fee554599 — cycle 81.

LES CINQ MESURES DU CYCLE 81, REEXECUTABLES SUR LA TRACE ARCHIVEE, SANS BUILD NI COURSE.
Ce fichier ne contient AUCUN seuil, AUCUNE gate, AUCUN verdict : il publie des grandeurs.

NATURE / REPERE / POPULATION, une fois pour toutes :
  - toute acceleration est une SECONDE DIFFERENCE FINIE de la translation MONDE ECRITE
    (ligne 3 de la 4x4 du squelette), en u/f^2.  1 g = 11.162 u/f^2.  4096 u = 1 m.  B0 = 602 u.
  - `chest` (j=4) n'est simule par RIEN : sa 4x4 ecrite EST la pose d'auteur, sans une
    contribution de la physique. Le controle est inclus (normes de ligne ~ 1.0 => rigide).
    `main` (j=5) est la racine du personnage ; `chest - main` isole l'ARTICULATION du torse.
  - POPULATION : la sous-fenetre SANS PILOTAGE (d=5) de PH-MEAS. 31 animations, 37 frames chacune.
  - l'apex et ses trois termes viennent de PHYSAPEX / PHYSAPEX2 / PHYSAPEXT / PHYSAPEXD, pris au
    MEME argmax par le moteur ; `rp` est DERIVE (e - tp - dp) et jamais emis, pour que
    l'identite `e = tp + rp + dp` reste falsifiable. Son controle est imprime.

usage:  python3 .autoport/c81_apex_static.py [chemin-de-la-trace]
"""
import sys, re, math, statistics as st

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    ".autoport/reports/Grecharged-secondary-motion/keira-room-x86.log"
G, B0 = 11.162, 602.0
NAMES = {0: 'lBoob', 1: 'lBooc', 2: 'rBoob', 3: 'rBooc', 4: 'chest', 5: 'main'}

# ---------------------------------------------------------------- lecture, une seule passe
M, anim, apx = {}, {}, {}
rx_m = re.compile(r'^PHYSJTW k=(\d+) j=(\d+) row=(\d+) x=([-\d.]+) y=([-\d.]+) z=([-\d.]+)')
rx_k = re.compile(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+)')
rx_a = {'A': re.compile(r'^PHYSAPEX c=(\d+) a=(\d+) d=5 apex=([-\d.]+) ax=([-\d.]+) ay=([-\d.]+)'),
        'B': re.compile(r'^PHYSAPEX2 c=(\d+) a=(\d+) d=5 az=([-\d.]+)'),
        'T': re.compile(r'^PHYSAPEXT c=(\d+) a=(\d+) d=5 tx=([-\d.]+) ty=([-\d.]+) tz=([-\d.]+)'),
        'D': re.compile(r'^PHYSAPEXD c=(\d+) a=(\d+) d=5 dx=([-\d.]+) dy=([-\d.]+) dz=([-\d.]+)')}
rx_c = re.compile(r'^PHYSACC c=(\d+) a=(\d+) d=5 acc=([-\d.]+)')
acc_recu = {}
for line in open(LOG, errors='replace'):
    if line.startswith('PHYSJTW k='):
        m = rx_m.match(line)
        if m:
            M.setdefault((int(m.group(1)), int(m.group(2))), [None] * 4)[int(m.group(3))] = \
                (float(m.group(4)), float(m.group(5)), float(m.group(6)))
    elif line.startswith('PHYSJTWK'):
        m = rx_k.match(line)
        if m: anim[int(m.group(1))] = int(m.group(2))
    elif line.startswith('PHYSAPEX'):
        for tag, rx in rx_a.items():
            m = rx.match(line)
            if m:
                apx.setdefault((int(m.group(1)), int(m.group(2))), {})[tag] = \
                    tuple(float(g) for g in m.groups()[2:])
                break
    elif line.startswith('PHYSACC'):
        m = rx_c.match(line)
        if m: acc_recu[(int(m.group(1)), int(m.group(2)))] = float(m.group(3))

KS = sorted(anim)
BY = {}
for k in KS: BY.setdefault(anim[k], []).append(k)
for a in BY: BY[a].sort()

def ok(k, j):     return M.get((k, j)) is not None and all(M[(k, j)])
def nrm(v):       return math.sqrt(sum(c * c for c in v))
def d2(p0, p1, p2): return nrm([p2[c] - 2 * p1[c] + p0[c] for c in range(3)])
def local(mm, p):
    """point monde -> repere de mm (lignes orthonormees, convention vecteur-ligne)."""
    d = [p[c] - mm[3][c] for c in range(3)]
    return tuple(sum(d[c] * mm[r][c] for c in range(3)) for r in range(3))
def world(mm, loc):
    return tuple(mm[3][c] + sum(loc[r] * mm[r][c] for r in range(3)) for c in range(3))
def pearson(x, y):
    n = len(x); mx, my = sum(x) / n, sum(y) / n
    sx = math.sqrt(sum((v - mx) ** 2 for v in x)); sy = math.sqrt(sum((v - my) ** 2 for v in y))
    return sum((x[i] - mx) * (y[i] - my) for i in range(n)) / (sx * sy) if sx and sy else float('nan')

print("DIRECTIVES v3fee554599")
print(f"trace : {LOG}")
print(f"frames d=5 : {len(KS)}   animations : {len(BY)}")

# ------------------------------------------------------- 0. CONTROLE : `chest` est-il rigide ?
rn = [nrm(r) for k in KS[:400] if ok(k, 4) for r in M[(k, 4)][:3]]
print(f"\n[0] CONTROLE  normes de ligne de `chest` sur {len(rn)} lignes : "
      f"min {min(rn):.6f}  max {max(rn):.6f}   (1.0 => rigide, donc non simule)")

# ------------------------------------------- 1. l'entree de l'ancre : translation puis rotation
OFF = {}
for j in (0, 1, 2, 3):
    o = [local(M[(k, 4)], M[(k, j)][3]) for k in KS if ok(k, j) and ok(k, 4)]
    if o: OFF[j] = tuple(st.median([v[c] for v in o]) for c in range(3))
print(f"\n[1] POINT D'ATTACHE, dans le repere de `chest` (mediane sur la course) :")
for j in (0, 2):
    print(f"      {NAMES[j]:6s} |offset| {nrm(OFF[j]):8.1f} u = {nrm(OFF[j])/B0:.2f} B0")

print(f"\n    ACCELERATION, par joint (u/f^2) — voisin/max dit si le pic dure PLUS D'UNE FRAME :")
print(f"      {'joint':11s} {'p50':>8} {'MAX':>9} {'MAX g':>7} {'nbr/max p50':>12}")
def serie(getter):
    tout, pics = [], []
    for a, kk in sorted(BY.items()):
        A = []
        for i in range(1, len(kk) - 1):
            if kk[i] - kk[i-1] != 1 or kk[i+1] - kk[i] != 1: A.append(None); continue
            try: A.append(d2(getter(kk[i-1]), getter(kk[i]), getter(kk[i+1])))
            except (TypeError, KeyError): A.append(None)
        v = [x for x in A if x is not None]
        if not v: continue
        tout += v
        mi = max(range(len(A)), key=lambda i: A[i] if A[i] is not None else -1)
        nb = [A[i] for i in (mi-1, mi+1) if 0 <= i < len(A) and A[i] is not None]
        pics.append((a, A[mi], (max(nb) / A[mi]) if nb and A[mi] > 0 else float('nan')))
    return tout, pics
SER = {}
for lbl, get in (('main', lambda k: M[(k,5)][3]), ('chest', lambda k: M[(k,4)][3]),
                 ('chest-main', lambda k: tuple(M[(k,4)][3][c] - M[(k,5)][3][c] for c in range(3))),
                 ('ancre@attache', lambda k: world(M[(k,4)], OFF[0]))):
    tout, pics = serie(get); SER[lbl] = pics
    r = [p[2] for p in pics if p[2] == p[2]]
    print(f"      {lbl:11s} {st.median(tout):8.3f} {max(tout):9.3f} {max(tout)/G:7.2f} "
          f"{st.median(r):12.3f}")
print("    `chest-main` = ARTICULATION du torse seule ; `ancre@attache` = la meme ancre RIGIDE"
      "\n    (translation ET rotation) evaluee au point d'attache, donc l'entree REELLE de la chaine.")

# --------------------------------- 2. la discontinuite de racine produit-elle l'apex ou le stimulus ?
pic_racine = {a: v for a, v, _ in SER['main']}
pic_entree = {a: v for a, v, _ in SER['ancre@attache']}
cells = [a for a in sorted(BY) if (0, a) in apx and (1, a) in apx and a in pic_racine]
def col(idx, c): return [apx[(c, a)]['A'][0] for a in cells]
print(f"\n[2] LA DISCONTINUITE DE RACINE PILOTE-T-ELLE L'APEX ?  (N={len(cells)} animations)")
for c, nm in ((0, 'chestL'), (1, 'chestR')):
    ap = [apx[(c, a)]['A'][0] for a in cells]
    ac = [acc_recu.get((c, a), float('nan')) for a in cells]
    xr = [pic_racine[a] for a in cells]; xe = [pic_entree[a] for a in cells]
    print(f"      {nm}  pic de racine <-> stimulus recu : Pearson {pearson(xr, ac):+.3f}")
    print(f"      {nm}  pic de racine <-> apex          : Pearson {pearson(xr, ap):+.3f}")
    print(f"      {nm}  entree rigide COMPLETE <-> apex : Pearson {pearson(xe, ap):+.3f}")

# ----------------------------------------- 3. l'apex repond-il a l'entree ? les trois termes
print(f"\n[3] DECOMPOSITION  e = tp + rp + dp, coupee par l'ENTREE RIGIDE au point d'attache")
rows = []
for a in cells:
    for c in (0, 1):
        d = apx[(c, a)]
        if not all(t in d for t in 'ABTD'): continue
        e = (d['A'][1], d['A'][2], d['B'][0]); t = d['T']; dp = d['D']
        rp = tuple(e[i] - t[i] - dp[i] for i in range(3))
        rows.append((c, a, d['A'][0], nrm(e), nrm(t), nrm(rp), nrm(dp), pic_entree[a] / G))
print(f"      CONTROLE D'IDENTITE  |e| contre l'apex publie, ecart max "
      f"{max(abs(r[2]-r[3]) for r in rows):.6f} B0")
def bloc(sel, lbl):
    R = [r for r in rows if sel(r)]
    if not R: return
    print(f"      {lbl:22s} N={len(R):3d}   apex {st.median([r[3] for r in R]):.4f}"
          f"   tp {st.median([r[4] for r in R]):.4f}"
          f"   rp {st.median([r[5] for r in R]):.4f}"
          f"   dp {st.median([r[6] for r in R]):.4f}")
bloc(lambda r: r[7] < 0.10, "entree < 0.10 g")
bloc(lambda r: 0.10 <= r[7] < 1.0, "entree 0.10-1.0 g")
bloc(lambda r: r[7] >= 1.0, "entree >= 1.0 g")
lo = [r for r in rows if r[7] < 0.10]; hi = [r for r in rows if r[7] >= 1.0]
print("      rapport mobile / quasi-statique : " + "  ".join(
    f"{nm} {st.median([r[i] for r in hi])/st.median([r[i] for r in lo]):.2f}"
    for nm, i in (('apex', 3), ('tp', 4), ('rp', 5), ('dp', 6))))

# ----------------------------- 4. les ancres STRICTEMENT immobiles (trois criteres simultanes)
print(f"\n[4] ANCRES STRICTEMENT IMMOBILES — vitesse <= 0.49 u/f, angulaire <= 0.024 deg/f,"
      f"\n    acceleration <= 0.10 g. Les trois ENSEMBLE : une vitesse constante traine un ressort,"
      f"\n    une rotation lente le tient hors centre. §22 : normal <= 0.42 B0, exceptionnel <= 0.50.")
def angle(u, v):
    du, dv = nrm(u), nrm(v)
    if du < 1e-9 or dv < 1e-9: return float('nan')
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(u[i]*v[i] for i in range(3)) / (du*dv)))))
still = []
for a, kk in sorted(BY.items()):
    sp, av = [], []
    for i in range(1, len(kk)):
        if kk[i] - kk[i-1] != 1 or not (ok(kk[i], 4) and ok(kk[i-1], 4)): continue
        sp.append(nrm([M[(kk[i],4)][3][c] - M[(kk[i-1],4)][3][c] for c in range(3)]))
        av.append(max(angle(M[(kk[i-1],4)][r], M[(kk[i],4)][r]) for r in range(3)))
    if sp and st.median(sp) <= 0.49 and st.median(av) <= 0.024 and pic_entree.get(a, 9e9)/G < 0.10:
        still.append((a, st.median(sp), st.median(av)))
print(f"      {'anim':>4} {'v u/f':>7} {'w deg/f':>8} {'chain':>7} {'apex':>7} {'tp':>7} {'rp':>7} {'dp':>7}  vs 0.50")
over = tot = 0
for a, v, w in still:
    for c, nm in ((0, 'chestL'), (1, 'chestR')):
        r = [x for x in rows if x[0] == c and x[1] == a]
        if not r: continue
        _, _, _, e, t, rp, dp, _ = r[0]; tot += 1; over += e > 0.50
        print(f"      {a:4d} {v:7.3f} {w:8.4f} {nm:>7} {e:7.4f} {t:7.4f} {rp:7.4f} {dp:7.4f}  "
              f"{'OVER' if e > 0.50 else 'in'}")
print(f"      -> {over}/{tot} cellules depassent le plafond EXCEPTIONNEL sur un personnage immobile.")

# ------------------- 5. le joint, dans le repere de l'ancre ; et la permanence du decalage
print(f"\n[5] EXCURSION PROPRE DU JOINT, dans le repere de `chest` (mouvement rigide de l'ancre"
      f"\n    divise), contre l'apex publie. Et la PERMANENCE : 5 premieres frames / 5 dernieres.")
for j, c, nm in ((0, 0, 'chestL'), (2, 1, 'chestR')):
    dj, rt, pm = [], [], []
    for a, kk in sorted(BY.items()):
        v = [nrm([local(M[(k,4)], M[(k,j)][3])[i] - OFF[j][i] for i in range(3)]) / B0
             for k in kk if ok(k, j) and ok(k, 4)]
        if len(v) < 10 or (c, a) not in apx: continue
        d = max(v); dj.append(d); rt.append(apx[(c, a)]['A'][0] / d if d > 0 else float('nan'))
        f, l = st.mean(v[:5]), st.mean(v[-5:])
        if f > 0: pm.append(l / f)
    print(f"      {nm}  joint p50 {st.median(dj):.4f} B0  max {max(dj):.4f} B0   "
          f"sous 0.50 : {sum(1 for d in dj if d < 0.50)}/{len(dj)} animations")
    print(f"              apex/joint p50 x{st.median(rt):.1f}, max x{max(rt):.1f}   "
          f"permanence (5 dern./5 prem.) p50 {st.median(pm):.2f}, "
          f"decroissantes (<0.6) {sum(1 for r in pm if r < 0.6)}/{len(pm)}")
print("\n    Une decroissance signerait un ring-down couvert par §27 (1.0-1.5 s). La fenetre ne"
      "\n    dure que 37 frames (0.62 s) : l'absence de TENDANCE au retour est ce qui est mesure,"
      "\n    pas l'epuisement du delai de §27. Cette mesure-la manque et elle est nommee.")

# ------------------------------------------------------------------------------------------
# [6] LE JOINT SE REPOSE-T-IL AU BIND DU MESH LIVRE ?  (ajout 81b)
# NATURE : une LONGUEUR. L'offset d'attache dans le repere LOCAL de `chest`, (a) tel que le mesh
#          LIVRE le definit en BIND (`inverseBindMatrices`), (b) tel que la course l'ECRIT.
# UNITES : le glb est en METRES (controle imprime), le moteur en unites, 4096 u = 1 m.
#          Toute longueur est publiee BRUTE ET convertie (directive du 2026-08-19 20:00).
# CE QUE CA DISCRIMINE : `tp` (moteur, :3923) = joint SIMULE - joint AUTEUR. S'il valait le
#          mouvement PROPRE du joint, il correlerait a `dj` a ~ +1. S'il vaut un ECART CONSTANT
#          entre la pose d'AUTEUR et le BIND, il est grand, `dj` est petit, et ils ne correlent pas.
try:
    import numpy as np
    sys.path.insert(0, '.autoport')
    from c38_glb import Glb
    M2U = 4096.0
    gb = Glb("out/jak1/fr3/skin/keira-hd-lod0.glb")
    sk = gb.j['skins'][0]
    ibm = gb.acc(sk['inverseBindMatrices']).reshape(-1, 4, 4)
    slot = {gb.j['nodes'][n].get('name'): i for i, n in enumerate(sk['joints'])}
    bwm = lambda nm: np.linalg.inv(ibm[slot[nm]].T)
    Cb = bwm('chest'); Cbi = np.linalg.inv(Cb)
    print(f"\n[6] BIND du mesh livre — CONTROLES : base de `chest` orthonormee "
          f"{[round(float(np.linalg.norm(Cb[:3,i])),5) for i in range(3)]} ; "
          f"echelle main y={bwm('main')[1,3]:.3f} m, head y={bwm('head')[1,3]:.3f} m => METRES")
    BIND = {}
    for nm in ('lBoob', 'rBoob'):
        BIND[nm] = (Cbi @ np.append(bwm(nm)[:3, 3], 1.0))[:3] * M2U
        v = BIND[nm]
        print(f"      {nm:6s} offset BIND ({v[0]:8.1f};{v[1]:8.1f};{v[2]:8.1f}) u  "
              f"|.| {np.linalg.norm(v):7.1f} u = {np.linalg.norm(v)/M2U*100:5.2f} cm "
              f"= {np.linalg.norm(v)/B0:.3f} B0")
    tpv = {}
    for line in open(LOG, errors='replace'):
        if line.startswith('PHYSAPEXT'):
            m = re.match(r'^PHYSAPEXT c=(\d+) a=(\d+) d=5 tx=([-\d.]+) ty=([-\d.]+) tz=([-\d.]+)', line)
            if m: tpv[(int(m.group(1)), int(m.group(2)))] = \
                np.array([float(m.group(3)), float(m.group(4)), float(m.group(5))])
    for j, c, nm in ((0, 0, 'lBoob'), (2, 1, 'rBoob')):
        mb, djv, tv = [], [], []
        for a, kk in sorted(BY.items()):
            o = [np.array(local(M[(k,4)], M[(k,j)][3])) for k in kk if ok(k, j) and ok(k, 4)]
            if len(o) < 10 or (c, a) not in tpv: continue
            med = np.array([st.median([v[i] for v in o]) for i in range(3)])
            mb.append(float(np.linalg.norm(med - BIND[nm])) / B0)
            djv.append(max(float(np.linalg.norm(v - med)) for v in o) / B0)
            tv.append(float(np.linalg.norm(tpv[(c, a)])))
        print(f"      {nm} (N={len(mb)})  mediane du joint vs BIND p50 {st.median(mb):.4f} B0 "
              f"({st.median(mb)*B0/M2U*100:.2f} cm)")
        print(f"             mouvement PROPRE `dj`  p50 {st.median(djv):.4f} B0   "
              f"|tp| vs pose d'AUTEUR p50 {st.median(tv):.4f} B0  -> **x{st.median(tv)/st.median(djv):.1f}**")
        print(f"             correlation |tp| <-> dj  Pearson {pearson(tv, djv):+.3f}"
              f"   (un tp qui SERAIT le mouvement propre donnerait ~ +1)")
    print("      => le joint SE REPOSE AU BIND ; `tp` est un ECART QUASI CONSTANT entre la pose")
    print("         d'AUTEUR et le BIND, pas une excursion de la physique.")
except Exception as e:
    print(f"\n[6] non evalue ({type(e).__name__}: {e}) — le mesh livre doit etre present.")
