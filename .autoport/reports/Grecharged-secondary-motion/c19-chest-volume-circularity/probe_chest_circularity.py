#!/usr/bin/env python3
"""c19 — LE VOLUME `chest` EST-IL GONFLE PAR LA POITRINE QU'IL EXPULSE ?

LECTURE SEULE. N'ECRIT RIEN d'autre que sur stdout. N'appelle NI generate() NI main()
du generateur : seules ses fonctions de mesure sont importees.

Quatre sections, cf. la demande du manager de phase (cycle 19).
"""
import os
import sys

import numpy as np

REPO = '/home/emeric/code/jak-project'
sys.path.insert(0, os.path.join(REPO, '.autoport'))
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G                                   # noqa: E402
from probe_mesh_vs_capsule_fidelity import sd_round_cone          # noqa: E402

np.set_printoptions(suppress=True)
U = G.UNITS


def influence_mask(geo, j, thr):
    """meme predicat que G.influence, rendu en masque booleen."""
    J, W = geo['J'], geo['W']
    sel = np.zeros(len(W), dtype=bool)
    for c in range(J.shape[1]):
        sel |= (J[:, c] == j) & (W[:, c] > thr)
    return sel


def joint_weight(geo, j):
    """poids total porte par le joint j sur CHAQUE sommet (0 si absent)."""
    J, W = geo['J'], geo['W']
    w = np.zeros(len(W), dtype=float)
    for c in range(J.shape[1]):
        m = (J[:, c] == j)
        w[m] += W[m, c]
    return w


def ladder(geo, j):
    """L'ECHELLE FIT_STEPS EXACTE du generateur (fit_radius -> iq_perp_radius -> influence)."""
    for thr in G.FIT_STEPS:
        n, _w, idx = G.influence(geo, j, thr)
        if n >= G.FIT_MIN_VERTS:
            return thr, idx
    for thr in reversed(G.FIT_STEPS):
        n, _w, idx = G.influence(geo, j, thr)
        if n > 0:
            return thr, idx
    return None, np.array([], dtype=int)


def iq_perp_on(geo, j, a_world, b_world, idx):
    """G.iq_perp_radius, MAIS sur un echantillon de sommets impose. Zero autre difference :
    meme espace bind, meme composante perpendiculaire, meme moyenne inter-quartile."""
    if len(idx) == 0:
        return None, 0
    ibm = geo['ibms'][j]
    pts = G.to_bone_local(ibm, geo['V'][idx])
    a = G.to_bone_local(ibm, a_world[None, :])[0]
    b = G.to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    if n < 1e-6:
        return None, len(idx)
    u = axis / n
    rel = pts - a
    rel = rel - np.outer(rel @ u, u)
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [G.IQ_LO, G.IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return float(inner.mean()), len(idx)


def main():
    geo = G.load_mesh(G.MODEL)
    names = list(geo['names'])
    idx_of = {n: i for i, n in enumerate(names)}
    P, V = geo['P'], geo['V']
    print(f'mesh {geo["src"]}  joints={len(names)}  verts={len(V)}')
    print()

    JCHEST = idx_of['chest']
    JL, JR = idx_of['lBoob'], idx_of['rBoob']

    # ---- l'attribution de la chair a une chaine, TELLE QUE LE GENERATEUR LA FAIT --------------
    # blob_centre_radius(chain_idx=None, cas LIVRE a 1 maillon) -> ladder sur influence()
    thrL, idxL = ladder(geo, JL)
    thrR, idxR = ladder(geo, JR)
    chain_owned = np.zeros(len(V), dtype=bool)
    chain_owned[idxL] = True
    chain_owned[idxR] = True
    print('=== ATTRIBUTION DE LA CHAIR AUX CHAINES (echelle FIT_STEPS du generateur) ===')
    print(f'  chestL/lBoob : seuil w>{thrL}  {len(idxL)} sommets')
    print(f'  chestR/rBoob : seuil w>{thrR}  {len(idxR)} sommets')
    print(f'  union chaines de physique : {int(chain_owned.sum())} sommets '
          f'sur {len(V)} ({100.0*chain_owned.mean():.2f} %)')
    print()

    # ================= SECTION 1 : LA SELECTION `chest` DE fit_radius ==========================
    print('=== SECTION 1 — SELECTION DE SOMMETS DE fit_radius POUR LE JOINT `chest` ===')
    thrC, idxC = ladder(geo, JCHEST)
    print(f'  seuil retenu par l echelle : w>{thrC}   n={len(idxC)} sommets')
    inter = np.intersect1d(idxC, np.flatnonzero(chain_owned))
    print(f'  dont possedes par chestL/chestR (meme seuil que le generateur, w>{thrL}) : '
          f'{len(inter)}  = {100.0*len(inter)/len(idxC):.2f} %')
    interL = np.intersect1d(idxC, idxL)
    interR = np.intersect1d(idxC, idxR)
    print(f'    detail : chestL {len(interL)}/{len(idxL)}   chestR {len(interR)}/{len(idxR)}')
    print()
    wl, wr = joint_weight(geo, JL), joint_weight(geo, JR)
    wc = joint_weight(geo, JCHEST)
    wb = wl + wr
    print('  Repartition du poids de POITRINE sur les sommets selectionnes pour `chest` :')
    for t in (0.0, 0.05, 0.10, 0.25, 0.44, 0.50):
        k = int((wb[idxC] > t).sum())
        print(f'    w(lBoob)+w(rBoob) > {t:.2f} : {k:5d} sommets  = {100.0*k/len(idxC):6.2f} %')
    print()
    sel = idxC[wb[idxC] > 0.0]
    if len(sel):
        print(f'  sur ces {len(sel)} sommets de `chest` qui portent AUSSI de la poitrine :')
        print(f'    w(chest)  mediane {np.median(wc[sel]):.4f}   '
              f'w(poitrine) mediane {np.median(wb[sel]):.4f}')
    print()
    print('  Contre-mesure : la chair de poitrine, vue depuis la poitrine')
    boob_any = np.flatnonzero(wb > 0.0)
    print(f'    sommets portant un poids NON NUL de lBoob ou rBoob : {len(boob_any)}')
    print(f'    dont selectionnes par `chest` a w>{thrC} : '
          f'{len(np.intersect1d(boob_any, idxC))} '
          f'({100.0*len(np.intersect1d(boob_any, idxC))/max(1,len(boob_any)):.2f} %)')
    print(f'    dont selectionnes par la chaine (w>{thrL}) : {int(chain_owned.sum())}')
    print(f'    w(chest) mediane sur la chair de chaine : '
          f'{np.median(wc[chain_owned]):.4f}   '
          f'w(chaine) mediane : {np.median(wb[chain_owned]):.4f}')
    print()

    # ================= SECTION 2 : RAYON RECALCULE SANS LA CHAIR DE CHAINE ======================
    print('=== SECTION 2 — RAYON AVANT / APRES EXCLUSION DE LA CHAIR DE CHAINE ===')
    print('  (meme fonction iq_perp_radius, meme statistique inter-quartile, meme echelle de')
    print('   seuils ; SEULE la selection change : on retire les sommets attribues a chestL/chestR)')
    print()
    caps = []
    for line in open(os.path.join(REPO, 'recharged_assets/physics_chains.txt')):
        if line.startswith('capsule '):
            f = line.split()
            caps.append((f[1], f[2],
                         int(f[3].split('=')[1]), int(f[4].split('=')[1])))
    print(f'  {len(caps)} capsules lues dans le fichier livre')
    print()
    hdr = (f'  {"capsule":26s} {"bout":12s} {"seuil":6s} {"n":>5s} {"n-excl":>7s} '
           f'{"livre":>6s} {"refit":>6s} {"apres":>6s} {"delta":>7s}')
    print(hdr)
    print('  ' + '-' * (len(hdr) - 2))
    rows = []
    for jn, pn, r1, r2 in caps:
        j, p = idx_of[jn], idx_of[pn]
        a, b = P[j], P[p]
        for who, ji, aa, bb, rlivre in ((jn, j, a, b, r1), (pn, p, b, a, r2)):
            thr, idx = ladder(geo, ji)
            r_before, _ = iq_perp_on(geo, ji, aa, bb, idx)
            keep = idx[~chain_owned[idx]]
            r_after, _ = iq_perp_on(geo, ji, aa, bb, keep)
            rb_i = None if r_before is None else int(round(r_before))
            ra_i = None if r_after is None else int(round(r_after))
            d = '' if (ra_i is None or rb_i is None) else f'{ra_i-rlivre:+d}'
            rows.append((f'{jn}->{pn}', who, thr, len(idx), len(idx) - len(keep),
                         rlivre, rb_i, ra_i, d))
            print(f'  {jn+"->"+pn:26s} {who:12s} w>{thr:<4} {len(idx):5d} '
                  f'{len(idx)-len(keep):7d} {rlivre:6d} '
                  f'{("-" if rb_i is None else rb_i):>6} {("-" if ra_i is None else ra_i):>6} '
                  f'{d:>7s}')
    moved = [r for r in rows if r[7] is not None and r[6] is not None and r[7] != r[6]]
    print()
    print(f'  BOUTS DEPLACES PAR LA REGLE : {len(moved)} / {len(rows)}')
    for r in moved:
        print(f'    {r[0]:26s} {r[1]:12s} {r[6]} -> {r[7]}  ({r[4]} sommets retires)')
    print()

    # ================= SECTION 3 : LA GEOMETRIE BRUTE ==========================================
    print('=== SECTION 3 — GEOMETRIE BRUTE, EN UNITES DE RIG (4096 u = 1 m) ===')
    pc = P[JCHEST]
    print(f'  P[chest]  = {pc.round(2)}')
    for nm, ji in (('lBoob', JL), ('rBoob', JR)):
        d = float(np.linalg.norm(P[ji] - pc))
        print(f'  P[{nm}]  = {P[ji].round(2)}   |chest->{nm}| = {d:8.2f} u = {d/U:.4f} m')
    print()
    # apex / pointe : le centroide et le p95 de la chair que la chaine possede, en MONDE bind
    for nm, ji, idx in (('lBoob', JL, idxL), ('rBoob', JR, idxR)):
        pts = V[idx]
        cen = pts.mean(axis=0)
        dj = np.linalg.norm(pts - P[ji], axis=1)
        far = pts[int(np.argmax(dj))]
        p95 = pts[int(np.argsort(dj)[int(0.95 * (len(dj) - 1))])]
        print(f'  {nm} : chair de chaine {len(idx)}v')
        print(f'    centroide monde      {cen.round(1)}  a {np.linalg.norm(cen-P[ji]):7.1f} u '
              f'du joint, {np.linalg.norm(cen-pc):7.1f} u de chest')
        print(f'    sommet le plus loin  {far.round(1)}  a {dj.max():7.1f} u du joint, '
              f'{np.linalg.norm(far-pc):7.1f} u de chest')
        print(f'    sommet p95           {p95.round(1)}  a '
              f'{np.linalg.norm(p95-P[ji]):7.1f} u du joint, '
              f'{np.linalg.norm(p95-pc):7.1f} u de chest')
    print()
    print('  PROFONDEUR DANS LES SPHERES `chest` (rayon - distance a chest ; >0 = DEDANS) :')
    probes = [('joint lBoob', P[JL]), ('joint rBoob', P[JR])]
    for nm, ji, idx in (('lBoob', JL, idxL), ('rBoob', JR, idxR)):
        pts = V[idx]
        dj = np.linalg.norm(pts - P[ji], axis=1)
        probes.append((f'centroide chair {nm}', pts.mean(axis=0)))
        probes.append((f'pointe (max) {nm}', pts[int(np.argmax(dj))]))
    # lBooc / rBooc du cycle 18, recopies de recharged_assets/keira-hd-inject-joints.txt @d7003fd42f
    for nm, xyz in (('lBooc (cycle 18)', (0.118709, 2.013364, 0.107055)),
                    ('rBooc (cycle 18)', (-0.119944, 2.016473, 0.107559))):
        probes.append((nm, np.array(xyz) * U))
    for R in (671, 769, 782):
        print(f'    --- sphere chest r={R} ---')
        for nm, pt in probes:
            d = float(np.linalg.norm(np.asarray(pt, dtype=float) - pc))
            print(f'      {nm:24s} d={d:8.1f} u  profondeur={R-d:+8.1f} u '
                  f'({(R-d)/U:+.4f} m)')
    print()

    # ================= SECTION 4 : LA CHAIR DE POITRINE HORS DES 4 VOLUMES ======================
    print('=== SECTION 4 — COMBIEN DE CHAIR EST DEDANS / DEHORS (sd_round_cone = le solide moteur) ===')
    four = [('chest', 'main', 671, 549), ('neck', 'chest', 249, 671),
            ('Lshoulder', 'chest', 612, 769), ('Rshoulder', 'chest', 554, 782)]
    sets = {
        f'chair chestL (chaine, w>{thrL})': idxL,
        f'chair chestR (chaine, w>{thrR})': idxR,
        f'chair `chest` (fit_radius, w>{thrC})': idxC,
    }
    for label, idx in sets.items():
        pts = V[idx]
        print(f'  --- {label} : {len(idx)} sommets ---')
        inside_any = np.zeros(len(idx), dtype=bool)
        for jn, pn, r1, r2 in four:
            a, b = P[idx_of[jn]], P[idx_of[pn]]
            sd = sd_round_cone(pts, a, b, float(r1), float(r2))
            ins = sd < 0
            inside_any |= ins
            print(f'    {jn}->{pn:6s} r={r1:4d}/{r2:4d} : DEDANS {int(ins.sum()):4d} '
                  f'({100.0*ins.mean():6.2f} %)  profondeur max '
                  f'{-sd.min():8.1f} u ({-sd.min()/U:+.4f} m)')
        print(f'    UNION DES 4      : DEDANS {int(inside_any.sum()):4d} '
              f'({100.0*inside_any.mean():6.2f} %)   DEHORS '
              f'{int((~inside_any).sum()):4d} ({100.0*(~inside_any).mean():6.2f} %)')
        print()
    # la mesure `obstacle_volume_coverage_not_mean` : chest->main contient-il SA PROPRE geometrie ?
    print('  CHAQUE VOLUME CONTIENT-IL SA PROPRE GEOMETRIE ? (sommets du joint du bout, echelle FIT_STEPS)')
    for jn, pn, r1, r2 in four:
        a, b = P[idx_of[jn]], P[idx_of[pn]]
        for who, rl in ((jn, r1), (pn, r2)):
            thr, idx = ladder(geo, idx_of[who])
            sd = sd_round_cone(V[idx], a, b, float(r1), float(r2))
            print(f'    {jn}->{pn:6s} bout {who:10s} r={rl:4d} : '
                  f'{len(idx):4d}v  DEHORS {int((sd>=0).sum()):4d} ({100.0*(sd>=0).mean():6.2f} %)')
    print()


if __name__ == '__main__':
    main()
