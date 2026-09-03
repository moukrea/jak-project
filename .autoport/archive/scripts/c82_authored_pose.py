#!/usr/bin/env python3
"""
DIRECTIVES v3fee554599 — cycle 82.

LA POSE D'AUTEUR DES JOINTS DE POITRINE, LUE SUR UNE COURSE OU RIEN NE LES ECRIT.
Predictions ecrites AVANT : .autoport/c82-predictions.txt (md5 1a3231a4ba714f33fabf8184efe1868c)

Ce fichier ne porte AUCUN seuil de gate et ne rend AUCUN verdict de conformite a la spec : il
publie des grandeurs et les confronte aux deux signatures ecrites d'avance.

NATURE     : des LONGUEURS (positions de joint), rapportees a B0 = 602 u ; 4096 u = 1 m.
REPERE     : le repere LOCAL de `chest` (rig idx 3), lignes orthonormees de sa 4x4 ECRITE,
             convention vecteur-ligne (la meme que .autoport/c81_apex_static.py). `chest` n'est
             simule par rien : c'est ce qui rend les courses comparables, et c'est verifie.
POPULATION : les cles `k` de la sous-fenetre SANS PILOTAGE (d=5) presentes dans les deux courses.
             JAMAIS un argmax.
ABSENT     : si l'animation ne deplacait pas le joint hors du modele, |A_loc - B_loc| = 0.0000 B0.

usage: c82_authored_pose.py <log-ARME> <log-chestR-DESARMEE> [<log-chestL-DESARMEE>]
"""
import sys, re, math, json, struct, statistics as st

B0, U = 602.0, 4096.0
NAMES = {0: 'lBoob', 1: 'lBooc', 2: 'rBoob', 3: 'rBooc', 4: 'chest', 5: 'main'}
rx_m = re.compile(r'^PHYSJTW k=(\d+) j=(\d+) row=(\d+) x=([-\d.]+) y=([-\d.]+) z=([-\d.]+)')
rx_k = re.compile(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+)')

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

def loc(mm, p):
    d = [p[c] - mm[3][c] for c in range(3)]
    return tuple(sum(d[c]*mm[r][c] for c in range(3)) for r in range(3))
def nrm(v): return math.sqrt(sum(c*c for c in v))
def sub(a, b): return tuple(a[i]-b[i] for i in range(3))
def mean(vs): return tuple(sum(v[i] for v in vs)/len(vs) for i in range(3))

def bind_locals(glb='out/jak1/fr3/skin/keira-hd-donor-injected.glb'):
    d = open(glb, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20+jl]); off = 20+jl
    blen, _ = struct.unpack('<I4s', d[off:off+8]); bn = d[off+8:off+8+blen]
    sk = j['skins'][0]
    nm = [j['nodes'][n].get('name', '?') for n in sk['joints']]
    a = j['accessors'][sk['inverseBindMatrices']]; bv = j['bufferViews'][a['bufferView']]
    base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    def inv44(m):
        A = [[m[0], m[4], m[8]], [m[1], m[5], m[9]], [m[2], m[6], m[10]]]; t = [m[12], m[13], m[14]]
        det = (A[0][0]*(A[1][1]*A[2][2]-A[1][2]*A[2][1]) - A[0][1]*(A[1][0]*A[2][2]-A[1][2]*A[2][0])
               + A[0][2]*(A[1][0]*A[2][1]-A[1][1]*A[2][0]))
        I = [[(A[1][1]*A[2][2]-A[1][2]*A[2][1])/det, (A[0][2]*A[2][1]-A[0][1]*A[2][2])/det, (A[0][1]*A[1][2]-A[0][2]*A[1][1])/det],
             [(A[1][2]*A[2][0]-A[1][0]*A[2][2])/det, (A[0][0]*A[2][2]-A[0][2]*A[2][0])/det, (A[0][2]*A[1][0]-A[0][0]*A[1][2])/det],
             [(A[1][0]*A[2][1]-A[1][1]*A[2][0])/det, (A[0][1]*A[2][0]-A[0][0]*A[2][1])/det, (A[0][0]*A[1][1]-A[0][1]*A[1][0])/det]]
        return I, [-(I[r][0]*t[0]+I[r][1]*t[1]+I[r][2]*t[2]) for r in range(3)]
    BW = {n: inv44(struct.unpack_from('<16f', bn, base+64*i)) for i, n in enumerate(nm)}
    Rc, tc = BW['chest']; out = {}
    for n in ('lBoob', 'lBooc', 'rBoob', 'rBooc'):
        R, t = BW[n]; dv = [t[c]-tc[c] for c in range(3)]
        out[n] = tuple(sum(Rc[c][r]*dv[c] for c in range(3))*U for r in range(3))
    return out

print("DIRECTIVES v3fee554599")
ARM = sys.argv[1]
LEGS = []                                  # (tag, chemin, joints desarmes, joints restes armes)
if len(sys.argv) > 2: LEGS.append(('chestR DESARMEE', sys.argv[2], (2, 3), (0, 1)))
if len(sys.argv) > 3: LEGS.append(('chestL DESARMEE', sys.argv[3], (0, 1), (2, 3)))
Ma, Aa = read(ARM)
BL = bind_locals()
print(f"ARMEE : {ARM}   cles={len(set(k for k, _ in Ma))}")
print("\nBIND du mesh LIVRE, repere chest-local (inverseBindMatrices, x4096) :")
for n in ('lBoob', 'lBooc', 'rBoob', 'rBooc'):
    v = BL[n]
    print(f"   {n:6s} x={v[0]:9.3f} y={v[1]:9.3f} z={v[2]:9.3f}  |v|={nrm(v):9.3f} u = {nrm(v)/B0:.4f} B0")

for tag, path, JOFF, JON in LEGS:
    print("\n" + "="*96)
    print(f"== {tag}   {path}")
    Md, Ad = read(path)
    KS = sorted(set(k for k, _ in Ma) & set(k for k, _ in Md))
    print(f"   cles COMMUNES = {len(KS)}   (population declaree 1147)")
    if len(KS) < 1100: print("   !! POPULATION SOUS 1100 — je le dis au lieu de l'arrondir.")

    # ---- CONTROLE NEGATIF : chest et main ne sont simules par rien -> identiques
    worst, ndiff, ntot = 0.0, 0, 0
    for k in KS:
        for jj in (4, 5):
            A, D = Ma.get((k, jj)), Md.get((k, jj))
            if not A or not D or None in A or None in D: continue
            for r in range(4):
                for c in range(3):
                    ntot += 1; dd = abs(A[r][c]-D[r][c])
                    if dd > 0: ndiff += 1
                    worst = max(worst, dd)
    print(f"\n   CONTROLE NEGATIF (P1) `chest`+`main` : {ntot} flottants, {ndiff} differents, "
          f"ecart max {worst:.6f} u  -> {'TIRE A ZERO' if ndiff == 0 else 'ECHEC'}")
    if ndiff:
        print("   !! LES DEUX COURSES NE SONT PAS COMPARABLES. Aucun chiffre de cette jambe ne vaut.")
        continue

    # ---- la chaine restee ARMEE : predite DIFFERENTE (P2), publiee, jamais presentee en surprise
    for jj in JON:
        v = [nrm(sub(loc(Ma[(k, 4)], Ma[(k, jj)][3]), loc(Md[(k, 4)], Md[(k, jj)][3])))/B0
             for k in KS if Ma.get((k, jj)) and Md.get((k, jj))]
        if v:
            print(f"   (P2) {NAMES[jj]:6s} RESTE ARME : deplace de {st.median(v):.4f} B0 (med) "
                  f"/ {max(v):.4f} (max) par l'ablation de l'autre chaine")

    # ---- les grandeurs, sur le cote DESARME
    print(f"\n   {'joint':6s} {'|A-B| auteur vs bind':>24s} {'|S-B| simule vs bind':>24s} {'|S-A| simule vs auteur':>26s}")
    print(f"   {'':6s} {'med / max   (B0)':>24s} {'med / max   (B0)':>24s} {'med / max   (B0)':>26s}")
    DATA = {}
    for jj in JOFF:
        rows = []
        for k in KS:
            A, D, C = Ma.get((k, jj)), Md.get((k, jj)), Md.get((k, 4))
            if not (A and D and C) or None in A or None in D: continue
            rows.append((k, loc(C, A[3]), loc(C, D[3])))        # (k, S_loc, A_loc)
        DATA[jj] = rows
        B = BL[NAMES[jj]]
        ab = [nrm(sub(a, B))/B0 for _, s, a in rows]
        sb = [nrm(sub(s, B))/B0 for _, s, a in rows]
        sa = [nrm(sub(s, a))/B0 for _, s, a in rows]
        print(f"   {NAMES[jj]:6s} {st.median(ab):10.4f} /{st.median(ab) and max(ab):10.4f}"
              f" {st.median(sb):11.4f} /{max(sb):10.4f} {st.median(sa):12.4f} /{max(sa):10.4f}")

    print(f"\n   CONTROLE POSITIF (P3) : mediane |S-A| >= 0.02 B0 exigee sur le cote DESARME")
    for jj in JOFF:
        m = st.median([nrm(sub(s, a))/B0 for _, s, a in DATA[jj]])
        print(f"      {NAMES[jj]:6s} {m:.4f} B0 -> {'TIRE' if m >= 0.02 else 'ECHEC (ablation sans effet)'}")

    print("\n   LES TROIS POINTS, EN MOYENNE, DANS LE MEME REPERE (u) — pour voir OU chacun se tient")
    for jj in JOFF:
        B = BL[NAMES[jj]]
        sm = mean([s for _, s, a in DATA[jj]]); am = mean([a for _, s, a in DATA[jj]])
        print(f"      {NAMES[jj]:6s} BIND   x={B[0]:9.2f} y={B[1]:9.2f} z={B[2]:9.2f}  |.|={nrm(B):8.2f}")
        print(f"      {'':6s} AUTEUR x={am[0]:9.2f} y={am[1]:9.2f} z={am[2]:9.2f}  |.|={nrm(am):8.2f}")
        print(f"      {'':6s} SIMULE x={sm[0]:9.2f} y={sm[1]:9.2f} z={sm[2]:9.2f}  |.|={nrm(sm):8.2f}")

    print("\n   LE DISCRIMINANT — A_loc VARIE-T-IL D'UNE ANIMATION A L'AUTRE ?")
    print("      d = |moyenne(A_loc) - B_loc| ; s_int = ecart-type INTER-animations ;")
    print("      s_intra = moyenne des ecarts-types INTRA-animation.  HYP-R si s_int/d <= 0.10,")
    print("      HYP-A si >= 0.25, NON CONCLUANT entre les deux.")
    for jj in JOFF:
        B = BL[NAMES[jj]]
        per = {}
        for k, s, a in DATA[jj]: per.setdefault(Ad.get(k, -1), []).append(a)
        ams = {x: mean(v) for x, v in per.items() if v}
        if len(ams) < 2: print(f"      {NAMES[jj]}: < 2 animations, non evaluable"); continue
        gm = mean(list(ams.values())); d = nrm(sub(gm, B))/B0
        s_int = math.sqrt(sum(sum((v[i]-gm[i])**2 for i in range(3)) for v in ams.values())/len(ams))/B0
        intra = []
        for x, v in per.items():
            if len(v) < 2: continue
            m = mean(v)
            intra.append(math.sqrt(sum(sum((y[i]-m[i])**2 for i in range(3)) for y in v)/len(v)))
        s_intra = (sum(intra)/len(intra))/B0 if intra else float('nan')
        r = s_int/d if d > 0 else float('inf')
        verd = ('HYP-R constante de retarget' if r <= 0.10 else
                'HYP-A intention d auteur' if r >= 0.25 else 'NON CONCLUANT')
        print(f"      {NAMES[jj]:6s} anims={len(ams):3d}  d={d:.4f} B0  s_int={s_int:.4f}  "
              f"s_intra={s_intra:.4f}  s_int/d={r:.3f}  -> {verd}")
        row = sorted((x, st.median([nrm(sub(y, B))/B0 for y in v])) for x, v in per.items())
        print(f"      {NAMES[jj]} |A-B| par animation : " + " ".join(f"{x}:{m:.3f}" for x, m in row))
