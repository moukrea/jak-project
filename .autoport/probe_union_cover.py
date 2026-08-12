#!/usr/bin/env python3
"""probe_union_cover.py — LA FIDELITE DES OBSTACLES, le chiffre que les DIRECTIVES reclament.

DIRECTIVES, « COLLIDERS DERIVES DU MESH » : « Ce qu'il faut mesurer avant de trancher : 1.
Fidelite : distance max d'un sommet du mesh a l'EXTERIEUR du volume. C'est le chiffre qui dit si
la forme est mieux epousee. »

Ce script le calcule pour un `physics_chains.txt` donne, sur le mesh skinne de Keira a sa pose
BIND. Il ne modifie rien. Il sert a comparer deux jeux de volumes (avant / apres) avec la MEME
regle, pour que la comparaison ait un sens.

CE QU'IL MESURE, exactement : pour CHAQUE sommet du mesh, la distance a l'exterieur de l'UNION de
tous les volumes declares (capsules et spheres). Un sommet hors de sa propre capsule mais dans
celle du voisin n'est PAS un defaut — seule l'union compte, et c'est bien l'union que le moteur
oppose aux chaines.

NATURE / REPERE / LECTURE QUAND LE DEFAUT EST ABSENT (SPEC 7) :
  * NATURE  : une DISTANCE (metres) et une FRACTION de surface. Le defaut decrit par l'owner est
              « ca passe au travers » : de la geometrie qui sort de son volume. Ni une amplitude,
              ni une frequence.
  * REPERE  : la pose BIND du mesh skinne, en unites de jeu (4096 u = 1 m), monde bind. Aucune
              position simulee n'y entre : on mesure la FORME des obstacles, pas leur mouvement.
              C'est donc une propriete du FICHIER DE DONNEES, reproductible sans faire tourner le
              jeu.
  * LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 m dehors et 0 % de sommets dehors.

RESERVE DECLAREE : la pose bind n'est pas toutes les poses. Un volume qui couvre a la pose bind
peut laisser sortir de la geometrie sur une pose extreme, parce qu'une capsule ne se deforme pas
comme la peau. Ce chiffre est donc une borne INFERIEURE du depassement reel en jeu — il ne
remplace pas `meshpen`, il dit si l'obstacle a la bonne FORME au depart.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402

UNITS = 4096.0


def read_volumes(path):
    """(capsules, spheres) tels que le moteur les lit : `capsule <j> <j2> radius= radius2=` et
    `collider <j> radius= offset=x,y,z`."""
    caps, sphs = [], []
    for raw in open(path, errors='ignore'):
        p = raw.split()
        if not p or p[0].startswith('#'):
            continue
        if p[0] == 'capsule' and len(p) >= 5:
            caps.append((p[1], p[2], float(p[3].split('=')[1]), float(p[4].split('=')[1])))
        elif p[0] == 'collider' and len(p) >= 3:
            r = float(p[2].split('=')[1])
            off = (0.0, 0.0, 0.0)
            for kv in p[3:]:
                if kv.startswith('offset='):
                    off = tuple(float(x) for x in kv.split('=')[1].split(','))
            sphs.append((p[1], r, np.array(off, dtype=float)))
    return caps, sphs


def outside(V, caps, sphs, P, ibms, idx_of):
    """distance a l'exterieur de l'union, par sommet (0 = dedans)."""
    best = np.full(len(V), np.inf)
    for jn, pn, r1, r2 in caps:
        j, p = idx_of.get(jn), idx_of.get(pn)
        if j is None or p is None:
            continue
        a, b = P[j], P[p]
        ab = b - a
        n2 = float(ab @ ab)
        if n2 < 1e-9:
            continue
        t = np.clip(((V - a) @ ab) / n2, 0.0, 1.0)
        proj = a[None, :] + t[:, None] * ab[None, :]
        d = np.linalg.norm(V - proj, axis=1) - (r1 + t * (r2 - r1))
        best = np.minimum(best, d)
    for jn, r, off in sphs:
        j = idx_of.get(jn)
        if j is None:
            continue
        # `offset` est exprime dans l'espace BIND du joint (phys-col-centre: vector-matrix*! par la
        # transformation du bone). A la pose bind, la transformation du bone est l'inverse de l'IBM.
        M = np.linalg.inv(ibms[j])
        c = (M[:3, :3] @ (off / UNITS) + M[:3, 3]) * UNITS
        best = np.minimum(best, np.linalg.norm(V - c[None, :], axis=1) - r)
    return np.maximum(best, 0.0)


def main():
    paths = sys.argv[1:] or [os.path.join(REPO, 'recharged_assets/physics_chains.txt')]
    names, parent, _d = G.load_rig(os.path.join(REPO, 'recharged_assets/hd_anim/keira-hd-k2e.json'))
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    V, P, ibms = geo['V'], geo['P'], geo['ibms']

    print("== FIDELITE DES OBSTACLES : depassement de l'UNION des volumes, pose bind ==")
    print(f"   {len(V)} sommets du mesh de Keira. 0 % / 0.0000 m = la cible.")
    print(f"   {'fichier':<44}{'dehors':>9}{'p95':>9}{'max':>9}{'moy>0':>9}")
    for path in paths:
        caps, sphs = read_volumes(path)
        d = outside(V, caps, sphs, P, ibms, idx_of)
        out = d > 0.0
        frac = float(out.mean())
        p95 = float(np.percentile(d, 95)) / UNITS
        mx = float(d.max()) / UNITS
        mean_pos = float(d[out].mean()) / UNITS if out.any() else 0.0
        label = os.path.basename(path)
        print(f"   {label:<44}{100 * frac:>8.1f}%{p95:>9.4f}{mx:>9.4f}{mean_pos:>9.4f}"
              f"   ({len(caps)} capsules + {len(sphs)} spheres)")


if __name__ == '__main__':
    main()


def by_joint(paths):
    """OU reste-t-il de la geometrie dehors ? Repartition par joint DOMINANT du sommet (le joint
    qui le pilote le plus) : c'est la partition naturelle du mesh, sans seuil et sans double
    comptage."""
    names, parent, _d = G.load_rig(os.path.join(REPO, 'recharged_assets/hd_anim/keira-hd-k2e.json'))
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    V, P, ibms, J, W = geo['V'], geo['P'], geo['ibms'], geo['J'], geo['W']
    dom = J[np.arange(len(J)), np.argmax(W, axis=1)]
    for path in paths:
        caps, sphs = read_volumes(path)
        d = outside(V, caps, sphs, P, ibms, idx_of)
        print(f"\n   -- {os.path.basename(path)} : pires joints (par sommet dominant) --")
        print(f"      {'joint':<16}{'nv':>6}{'dehors':>9}{'max_m':>9}{'moy>0_m':>9}")
        rows = []
        for j in np.unique(dom):
            m = dom == j
            dm = d[m]
            o = dm > 0
            if not o.any():
                continue
            rows.append((float(dm.max()) / UNITS, names[j], int(m.sum()),
                         float(o.mean()), float(dm[o].mean()) / UNITS))
        for mx, nm, nv, frac, mp in sorted(rows, reverse=True)[:14]:
            print(f"      {nm:<16}{nv:>6}{100 * frac:>8.0f}%{mx:>9.4f}{mp:>9.4f}")
