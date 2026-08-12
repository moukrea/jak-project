#!/usr/bin/env python3
"""probe_knee_flap_burial.py — LA POSE DE MODELE DES LANGUETTES DE GENOU EST-ELLE DANS LA JAMBE ?

Question posee par le manager de phase (defaut owner `knee-tabs`, deux signalements) et par le
commit dbdb4ca5da, qui affirme « les languettes de genou ne peuvent PAS sortir de la capsule de
cuisse : il leur manque 8 mm ». Un commentaire n'est pas une preuve : ce script recalcule le
predicat DU MOTEUR sur les donnees LIVREES, en pose BIND.

CE QUI EST REPRODUIT, ligne a ligne :
  * le centre du volume de lien   = position du joint + offset tourne par la matrice de l'os
                                    (jak-hd-physics.gc:1641 `phys-link-off!`)
  * le solide                     = enveloppe convexe des deux spheres du volume, minimisee sur
                                    [0,1] (jak-hd-physics.gc:1170 `phys-collide-depth`)
  * `buried`                      = floor0 >= 2 * rl, cf. jak-hd-physics.gc:2276
                                    (le lien est ENTIEREMENT dans le volume a sa pose de modele)

NATURE  : une DISTANCE signee (profondeur), en unites de jeu et en mm. Pas un compte.
REPERE  : monde, pose BIND du rig HD (4096 u = 1 m). C'est le seul repere que les assets donnent
          hors execution ; le compteur `buried` de la course, lui, est mesure sur la pose ANIMEE
          frame par frame et c'est LUI qui fait foi (SPEC 7).
LECTURE QUAND LE DEFAUT EST ABSENT : depth <= 0 (la sphere du lien est entierement dehors) et
          `buried=NON`. Une marge positive `clearance` est ce qui reste avant que le lien touche.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)

import physics_keira_gen2 as G  # noqa: E402

RIG = os.path.join(REPO, 'recharged_assets/hd_anim/keira-hd-k2e.json')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')
U = 4096.0


def bone_rot(ibm):
    """rotation MONDE de l'os en pose bind, echelle retiree (meme normalisation que
    physics_keira_gen2.to_bone_local)."""
    R = ibm[:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    Rn = R / s[:, None]          # monde -> local
    return Rn                    # world_row = local_row @ Rn


def cone_depth(p, ca, cb, ra, rb, rl):
    """jak-hd-physics.gc:1170 `phys-collide-depth`, transcrite : (r(t*) + rl) - |p - C(t*)|,
    t* minimisant f(t) = |p - C(t)| - r(t) sur [0,1]."""
    a = cb - ca
    dd = float(a @ a)
    dr = rb - ra
    if dd < 1e-6:
        return (max(ra, rb) + rl) - float(np.linalg.norm(p - ca))
    a2 = dd - dr * dr
    if a2 <= 1e-6:
        c, r = (ca, ra) if ra >= rb else (cb, rb)
        return (r + rl) - float(np.linalg.norm(p - c))
    rel = p - ca
    L = np.sqrt(dd)
    u = a / L
    x = float(rel @ u)
    y = float(np.linalg.norm(rel - x * u))
    t = (x + dr * y / np.sqrt(a2)) / L
    t = min(1.0, max(0.0, t))
    c = ca + t * a
    r = ra + t * dr
    return (r + rl) - float(np.linalg.norm(p - c))


def main():
    names, parent, _d = G.load_rig(RIG)
    geo = G.load_mesh(G.MODEL)
    P, ibms = geo['P'], geo['ibms']
    idx = {n: i for i, n in enumerate(names)}

    caps, sph = [], {}
    for raw in open(CHAINS, errors='ignore'):
        p = raw.split()
        if len(p) >= 5 and p[0] == 'capsule':
            caps.append((p[1], p[2],
                         float(p[3].split('=')[1]), float(p[4].split('=')[1])))
        if len(p) >= 3 and p[0] == 'collider':
            r = float(p[2].split('=')[1])
            off = np.zeros(3)
            for tok in p[3:]:
                if tok.startswith('offset='):
                    off = np.array([float(v) for v in tok.split('=')[1].split(',')])
            sph[p[1]] = (r, off)

    print("== LE CENTRE DU VOLUME DE LIEN, EN POSE BIND ==")
    centres = {}
    for jn in ('lKneeFlap', 'rKneeFlap'):
        j = idx[jn]
        r, off = sph[jn]
        w = off @ bone_rot(ibms[j])
        c = P[j] + w
        centres[jn] = (c, r)
        pa = P[parent[j]]
        print(f"   {jn:11} joint={P[j].round(1)} os={np.linalg.norm(P[j]-pa):7.1f} u "
              f"({np.linalg.norm(P[j]-pa)/U:.4f} m)  rayon_lien={r:.0f} u")
        print(f"   {'':11} offset_local={off}  ->  monde={w.round(1)} |{np.linalg.norm(w):.1f}| u")
        print(f"   {'':11} centre_volume={c.round(1)}")

    print()
    print("== LE PREDICAT `buried` DU MOTEUR, RECALCULE (floor0 >= 2*rl) ==")
    print(f"   {'lien':11}{'volume':<20}{'ra':>6}{'rb':>6}{'dist_axe':>10}"
          f"{'depth':>9}{'depth_mm':>10}{'buried':>8}{'marge_mm':>10}")
    for jn, vols in (('lKneeFlap', ('Lknee Lthigh', 'Lankle Lknee', 'Lthigh hips')),
                     ('rKneeFlap', ('Rknee Rthigh', 'Rankle Rknee', 'Rthigh hips'))):
        c, rl = centres[jn]
        for v in vols:
            a, b = v.split()
            m = [x for x in caps if x[0] == a and x[1] == b]
            if not m:
                continue
            _a, _b, ra, rb = m[0]
            ca, cb = P[idx[a]], P[idx[b]]
            d = cone_depth(c, ca, cb, ra, rb, rl)
            # distance geometrique au solide (sans le rayon du lien)
            dsolid = cone_depth(c, ca, cb, ra, rb, 0.0)
            print(f"   {jn:11}{a+'->'+b:<20}{ra:>6.0f}{rb:>6.0f}{-dsolid+0:>10.1f}"
                  f"{d:>9.1f}{1000*d/U:>10.2f}{'OUI' if d >= 2*rl else 'non':>8}"
                  f"{-1000*d/U:>10.2f}")
    print()
    print("   depth  = (r(t*) + rl) - |c - C(t*)|, en unites de jeu. > 0 : la sphere du lien")
    print("            mord dans le solide. >= 2*rl (= %d u) : elle y est ENTIEREMENT."
          % int(2 * centres['lKneeFlap'][1]))
    print("   marge  = -depth en mm : ce qui reste avant contact quand depth < 0.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
