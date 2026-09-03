#!/usr/bin/env python3
"""probe_c29_chain_axis.py — QUELLE PART D'UNE POUSSEE DE SEPARATION LA CONTRAINTE DE LONGUEUR
CONFISQUE-T-ELLE ? Geometrie pure, en degres, sans aucune course.

POURQUOI (cycle 29). SPEC 33 exige que les surfaces mediales se repoussent AVANT interpenetration ;
la course livre 487.82 u de residu (chestL) apres 8x3 balayages + 4 iterations de finition. Le
cycle 28 a etabli que ce n'est PAS un defaut de convergence et a laisse le mecanisme sans nom.

L'HYPOTHESE QUE CETTE SONDE TESTE, et elle est falsifiable en une mesure : un joint contraint par
`phys-length-chain` vit sur la SPHERE de son attache, donc toute poussee est ramenee a sa seule
composante TANGENTIELLE ; sa composante RADIALE est rendue a zero a chaque iteration, quel qu'en
soit le nombre. Si la direction dans laquelle il faut ecarter les deux seins etait RADIALE, le
solveur serait structurellement impuissant et le residu serait explique.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  : un ANGLE en degres entre deux DIRECTIONS, et la fraction `cos^2` qui s'en deduit.
            Pas une amplitude, pas une variance, pas une distance.
  REPERE  : le monde, en pose de BIND. Attention a la provenance : le mesh LIVRE
            (`keira-hd-lod0.glb`) porte tous ses joints A L'ORIGINE (transformations d'identite,
            verifie par cette sonde) — il ne porte QUE les poids. La pose de bind vit dans
            `keira-hd-donor-injected.glb`, et c'est la repartition exacte que declare l'en-tete de
            `physics_chains.txt`. Mesurer les positions sur le mesh livre rendrait des zeros.
  ABSENT  : une separation purement TANGENTIELLE donne 90 deg et 0 % de confiscation — la
            contrainte de longueur ne retire alors rien a la poussee.

CONTROLE INTERNE : les ecarts de surface au repos que la sonde recalcule doivent reproduire ceux
qui sont deja au dossier (521.0 / 450.5 / 378.3 u). S'ils divergent, la reconstruction geometrique
est fausse et tout le reste est a jeter — la sonde le dit et sort en erreur.

USAGE : python3 .autoport/probe_c29_chain_axis.py
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G          # noqa: E402

BIND = 'out/jak1/fr3/skin/keira-hd-donor-injected.glb'
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
U = 4096.0                                     # unites de jeu par metre
REF_GAPS = {('lBoob', 'rBoob'): 521.0,         # controle interne, deja au dossier
            ('lBooc', 'rBoob'): 450.5,
            ('lBooc', 'rBooc'): 378.3}


def node_world(path):
    js, _bufs = G.read_glb(path)
    nodes = js.get('nodes', [])
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get('children', []):
            parent[c] = i

    def local(nd):
        if 'matrix' in nd:
            return np.array(nd['matrix'], dtype=float).reshape(4, 4).T
        M = np.eye(4)
        s = nd.get('scale', [1, 1, 1])
        x, y, z, w = nd.get('rotation', [0, 0, 0, 1])
        M[:3, :3] = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]],
            dtype=float) @ np.diag(s)
        M[:3, 3] = nd.get('translation', [0, 0, 0])
        return M

    cache = {}

    def world(i):
        if i not in cache:
            M = local(nodes[i])
            p = parent.get(i)
            cache[i] = (world(p) @ M) if p is not None else M
        return cache[i]

    return {nd.get('name', ''): i for i, nd in enumerate(nodes)}, world


def read_volumes(path):
    """(joint -> (rayon, offset dans l'espace de bind du joint)), lu dans le fichier LIVRE."""
    out = {}
    for raw in open(path, errors='ignore'):
        tok = raw.strip().split()
        if len(tok) >= 3 and tok[0] == 'collider':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            if 'radius' in kv and 'offset' in kv:
                out[tok[1]] = (float(kv['radius']),
                               np.array([float(v) for v in kv['offset'].split(',')]))
    return out


def unit(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else v * 0.0


def ang(a, b):
    return np.degrees(np.arccos(max(-1.0, min(1.0, float(np.dot(unit(a), unit(b)))))))


def main():
    names, world = node_world(BIND)
    joints = ['chest', 'lBoob', 'lBooc', 'rBoob', 'rBooc']
    miss = [j for j in joints if j not in names]
    if miss:
        raise SystemExit('joints absents de %s : %s' % (BIND, ' '.join(miss)))
    P = {j: world(names[j])[:3, 3] * U for j in joints}

    # PROVENANCE, PUBLIEE PLUTOT QUE SUPPOSEE : le mesh livre ne porte aucune pose.
    snames, sworld = node_world(SHIPPED)
    sp = max(float(np.linalg.norm(sworld(snames[j])[:3, 3])) for j in joints if j in snames)
    print('pose de bind  : %s' % BIND)
    print('poids livres  : %s   (|position| max des memes joints = %.6f — aucune pose)'
          % (SHIPPED, sp))
    print()

    vol = read_volumes(CHAINS)
    C, R = {}, {}
    for j in ['lBoob', 'lBooc', 'rBoob', 'rBooc']:
        r, off = vol[j]
        W = world(names[j]).copy()
        W[:3, 3] *= U
        C[j] = (W[:3, :3] @ off) + W[:3, 3]
        R[j] = r

    print('joint / centre de volume, pose de bind, unites de jeu (4096 = 1 m)')
    for j in joints:
        c = ('   centre % 9.1f % 9.1f % 9.1f  r=%d' % (*C[j], R[j])) if j in C else ''
        print('  %-6s % 9.1f % 9.1f % 9.1f%s' % (j, *P[j], c))
    print()

    print('CONTROLE INTERNE — ecarts de SURFACE au repos entre volumes opposes :')
    bad = 0
    for (a, b), ref in REF_GAPS.items():
        gap = float(np.linalg.norm(C[a] - C[b])) - R[a] - R[b]
        ok = abs(gap - ref) <= 0.5
        bad += 0 if ok else 1
        print('  %-6s <-> %-6s  gap = %8.1f u   (dossier %7.1f)  %s'
              % (a, b, gap, ref, 'OK' if ok else '**DIVERGE**'))
    if bad:
        raise SystemExit('la reconstruction geometrique ne reproduit pas les ecarts au dossier '
                         '— rien de ce qui suit ne vaut.')
    print()

    print('ANGLE entre la direction RADIALE du maillon (attache -> joint, la seule que la')
    print('projection sur la sphere annule) et la direction de SEPARATION des deux volumes :')
    print('  maillon        angle(deg)   part de la poussee CONFISQUEE   part UTILE')
    for lab, a, b, va, vb in [('chestL l=0', 'chest', 'lBoob', 'lBoob', 'rBoob'),
                              ('chestL l=1', 'lBoob', 'lBooc', 'lBooc', 'rBooc'),
                              ('chestR l=0', 'chest', 'rBoob', 'rBoob', 'lBoob'),
                              ('chestR l=1', 'rBoob', 'rBooc', 'rBooc', 'lBooc')]:
        d = ang(P[b] - P[a], C[va] - C[vb])
        c2 = np.cos(np.radians(d)) ** 2
        print('  %-12s %9.2f %25.1f %% %13.1f %%' % (lab, d, 100.0 * c2, 100.0 * (1.0 - c2)))
    print()
    print('LECTURE : `confisquee` = cos^2(angle). A 100 % le solveur ne peut pas separer les deux')
    print('seins, quel que soit le nombre d\'iterations ; a 0 % la contrainte de longueur ne lui')
    print('retire rien. C\'est un TEST de l\'hypothese, pas sa confirmation.')


if __name__ == '__main__':
    main()
