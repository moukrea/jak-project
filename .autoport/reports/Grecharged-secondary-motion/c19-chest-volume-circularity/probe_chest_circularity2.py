#!/usr/bin/env python3
"""c19 bis — (a) exclusion MAXIMALE (tout sommet portant le moindre poids de poitrine),
(b) le MAILLON tel que le moteur le presente aux volumes du corps, (c) de combien il
faudrait reduire chaque rayon pour degager le maillon.  LECTURE SEULE, stdout seulement."""
import os
import sys

import numpy as np

REPO = '/home/emeric/code/jak-project'
sys.path.insert(0, os.path.join(REPO, '.autoport'))
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G                                    # noqa: E402
from probe_mesh_vs_capsule_fidelity import sd_round_cone          # noqa: E402

U = G.UNITS


def joint_weight(geo, j):
    J, W = geo['J'], geo['W']
    w = np.zeros(len(W), dtype=float)
    for c in range(J.shape[1]):
        m = (J[:, c] == j)
        w[m] += W[m, c]
    return w


def ladder(geo, j):
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
    if len(idx) == 0:
        return None
    ibm = geo['ibms'][j]
    pts = G.to_bone_local(ibm, geo['V'][idx])
    a = G.to_bone_local(ibm, a_world[None, :])[0]
    b = G.to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    if n < 1e-6:
        return None
    u = axis / n
    rel = pts - a
    rel = rel - np.outer(rel @ u, u)
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [G.IQ_LO, G.IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return float(inner.mean())


def bind_frame(ibm):
    R = ibm[:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    Rn = R / s[:, None]
    tn = ibm[:3, 3] * U / s
    return Rn, tn


def local_to_world(Rn, tn, p):
    return Rn.T @ (np.asarray(p, dtype=float) - tn)


def main():
    geo = G.load_mesh(G.MODEL)
    names = list(geo['names'])
    idx_of = {n: i for i, n in enumerate(names)}
    P, V = geo['P'], geo['V']
    JC, JL, JR = idx_of['chest'], idx_of['lBoob'], idx_of['rBoob']
    wb = joint_weight(geo, JL) + joint_weight(geo, JR)

    four = [('chest', 'main', 671, 549), ('neck', 'chest', 249, 671),
            ('Lshoulder', 'chest', 612, 769), ('Rshoulder', 'chest', 554, 782)]

    print('=== 2bis — EXCLUSION MAXIMALE : tout sommet portant le MOINDRE poids de poitrine ===')
    print('  (version la plus GENEREUSE pour l hypothese : 184 sommets retires au lieu de 59)')
    thrC, idxC = ladder(geo, JC)
    keep0 = idxC[wb[idxC] <= 0.0]
    keep25 = idxC[wb[idxC] <= 0.25]
    print(f'  `chest` selection w>{thrC} : {len(idxC)} sommets')
    print(f'    exclusion w_poitrine>0.25 (attribution generateur) : reste {len(keep25)}')
    print(f'    exclusion w_poitrine>0.00 (TOUT contact)           : reste {len(keep0)}')
    print()
    print(f'  {"capsule":22s} {"livre":>6s} {"refit":>7s} {"excl>0.25":>10s} {"excl>0.00":>10s}')
    for jn, pn, r1, r2 in four:
        a, b = P[idx_of[jn]], P[idx_of[pn]]
        who, aa, bb, rl = (jn, a, b, r1) if jn == 'chest' else (pn, b, a, r2)
        assert who == 'chest'
        base = iq_perp_on(geo, JC, aa, bb, idxC)
        e25 = iq_perp_on(geo, JC, aa, bb, keep25)
        e00 = iq_perp_on(geo, JC, aa, bb, keep0)
        print(f'  {jn+"->"+pn:22s} {rl:6d} {round(base):7.0f} {round(e25):10.0f} '
              f'{round(e00):10.0f}')
    print()

    # ---- LE MAILLON TEL QUE LE MOTEUR LE PRESENTE --------------------------------------------
    print('=== 5 — LE MAILLON DE SEIN CONTRE LES 4 VOLUMES `chest`, POSE DE BIND ===')
    print('  Deux descriptions du maillon coexistent dans le fichier livre, cf.')
    print('  probe_rest_containment.py:196-200 : le moteur prend le COLLIDER quand le joint en')
    print('  porte un (jak-hd-physics.gc:1032-1042).')
    links = {}
    for line in open(os.path.join(REPO, 'recharged_assets/physics_chains.txt')):
        t = line.split()
        if t[:1] == ['collider'] and t[1] in ('lBoob', 'rBoob'):
            r = int(t[2].split('=')[1])
            off = np.array([float(x) for x in t[3].split('=')[1].split(',')])
            links[t[1]] = (r, off)
    radii = {'lBoob': 656.0, 'rBoob': 660.0}
    for nm, ji in (('lBoob', JL), ('rBoob', JR)):
        r_col, off = links[nm]
        Rn, tn = bind_frame(geo['ibms'][ji])
        c_col = local_to_world(Rn, tn, off)
        print(f'  --- {nm} ---')
        print(f'    A: joint {P[ji].round(1)}  + rayon de lien {radii[nm]:.0f}')
        print(f'    B: collider centre {c_col.round(1)} (a '
              f'{np.linalg.norm(c_col-P[ji]):.1f} u du joint) + rayon {r_col}')
        for jn, pn, r1, r2 in four:
            a, b = P[idx_of[jn]], P[idx_of[pn]]
            sdA = float(sd_round_cone(P[ji][None, :], a, b, float(r1), float(r2))[0])
            sdB = float(sd_round_cone(c_col[None, :], a, b, float(r1), float(r2))[0])
            jeuA = sdA - radii[nm]
            jeuB = sdB - r_col
            print(f'    {jn+"->"+pn:20s} jeu_A={jeuA:+9.1f} u ({jeuA/U:+.4f} m)   '
                  f'jeu_B={jeuB:+9.1f} u ({jeuB/U:+.4f} m)')
    print()
    print('  De combien faudrait-il reduire le rayon du bout `chest` pour que jeu_B = 0 ?')
    for nm, ji in (('lBoob', JL), ('rBoob', JR)):
        r_col, off = links[nm]
        Rn, tn = bind_frame(geo['ibms'][ji])
        c_col = local_to_world(Rn, tn, off)
        for jn, pn, r1, r2 in four:
            a, b = P[idx_of[jn]], P[idx_of[pn]]
            end_is_a = (jn == 'chest')
            lo, hi = 0.0, float(r1 if end_is_a else r2)
            base = float(sd_round_cone(c_col[None, :], a, b, float(r1), float(r2))[0]) - r_col
            if base >= 0:
                continue
            for _ in range(80):
                mid = 0.5 * (lo + hi)
                rr1 = mid if end_is_a else float(r1)
                rr2 = float(r2) if end_is_a else mid
                v = float(sd_round_cone(c_col[None, :], a, b, rr1, rr2)[0]) - r_col
                if v < 0:
                    hi = mid
                else:
                    lo = mid
            cur = float(r1 if end_is_a else r2)
            print(f'    {nm} vs {jn}->{pn:12s} : rayon {cur:.0f} -> {0.5*(lo+hi):.0f} '
                  f'(reduction {cur-0.5*(lo+hi):.0f} u = {100.0*(cur-0.5*(lo+hi))/cur:.1f} %) ; '
                  f'exclusion de la chair de chaine n en rend que '
                  f'{ {671:17,769:31,782:30}.get(int(cur),0) } u')
    print()


if __name__ == '__main__':
    main()
