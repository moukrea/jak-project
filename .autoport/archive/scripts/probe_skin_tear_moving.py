#!/usr/bin/env python3
"""probe_skin_tear_moving.py — LES ARETES QUI ENJAMBENT LA FRONTIERE FIGE/MOBILE.

Ce script ne modifie rien. Il lit `recharged_assets/physics_chains.txt` (le fichier LIVRE) et le
mesh LIVRE, et corrige UN angle mort de `ROOM-SKINCOV` qui rend son `tear` structurellement aveugle
au defaut PRIORITE 1.

L'ANGLE MORT, ET IL EST MECANIQUE.

`ROOM-SKINCOV` calcule `tear` = nombre d'aretes dont les deux bouts ont des fractions PILOTEES qui
different de plus de 0.5. Sa colonne « pilote » compte TOUS les joints de la chaine — y compris le
maillon 0, alors que toutes les chaines de cheveux et d'oreilles portent `rootlock=1`. Or un maillon
`rootlock=1` publie `link0=0.0000` sur les cinq pilotages (keira-room-table.txt, ROOM-GRADIENT) :
il est SOUDE a son os porteur, aussi immobile que `head`.

Consequence : un sommet pese 100 % sur `Lbanga` (fige) et son voisin pese 100 % sur `Lbangb`
(mobile) rendent tous les deux « pilote = 1.00 ». Leur ecart vaut 0.00 et l'arete n'est PAS comptee
— alors que c'est exactement, mot pour mot, ce que l'owner decrit : « des polygones qui bougent et
des polygones voisins parfaitement statiques, causant la geometrie qui casse ».

`tear=0` sur les cheveux du mesh livre ne veut donc pas dire « pas de cassure » : il veut dire
« je ne regarde pas la frontiere ou la cassure se produit ». C'est le meme piege que la couverture
qui comptait un joint epingle (0.979 publie contre 0.473 mobile).

LES TROIS QUESTIONS DE LA SPEC 7, REPONDUES AVANT D'ECRIRE LA MESURE :

  NATURE  : un COMPTE d'aretes du maillage qui enjambent une discontinuite de mouvement. Ce n'est
            ni une amplitude ni une fraction : le defaut decrit est une CASSURE entre voisins, donc
            la grandeur fidele porte sur les ARETES, pas sur les sommets ni sur leur moyenne.
  REPERE  : la fraction de poids portee par les joints qui BOUGENT REELLEMENT (maillon 0 exclu
            quand `rootlock=1`), sans dimension. La position n'intervient que pour DIRE OU se
            trouve la cassure (abscisse curviligne, comme probe_skin_profile).
  ABSENT  : `tear_mov = 0`. Une peau graduee correctement fait varier la fraction pilotee
            CONTINUMENT le long de la meche ; aucune arete ne saute alors de plus de 0.5.

CONTROLE POSITIF INTEGRE (SPEC 7 : « tout zero exige un controle qui a MONTE »). On declare fige un
maillon INTERMEDIAIRE de la chaine — un defaut de la meme nature, injecte a un endroit connu. Le
compte doit monter. S'il ne monte pas, la mesure ne lit pas ce qu'elle annonce et ses zeros ne
valent rien.

USAGE : python3 .autoport/probe_skin_tear_moving.py [chemin.glb]
        (defaut : out/jak1/fr3/skin/keira-hd-lod0.glb, le mesh du pack livre)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_c6_volumes as c6          # noqa: E402

CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
JUMP = 0.5          # meme seuil que ROOM-SKINCOV, pour que les deux comptes soient comparables


def parse_chains(path):
    """nom -> dict(joints ORDONNES, rootlock). Lu dans le fichier LIVRE, pas dans le generateur."""
    out, cur = {}, None
    for raw in open(path, errors='ignore'):
        tok = raw.strip().split()
        if not tok or tok[0].startswith('#') or tok[0].startswith('['):
            continue
        if tok[0] == 'chain':
            kv = dict(t.split('=', 1) for t in tok[2:] if '=' in t)
            cur = tok[1]
            out[cur] = dict(joints=[], rootlock=int(kv.get('rootlock', 0)))
        elif tok[0] == 'j' and cur is not None:
            out[cur]['joints'].append(tok[1])
    return out


def dense_weights(g):
    """Matrice sommets x joints, quelle que soit la forme rendue par le lecteur."""
    V = g['V']
    names = g['names']
    W = g['W']
    if W.ndim == 2 and W.shape[1] == len(names):
        return V, names, W
    J = g['J']
    Wd = np.zeros((len(V), len(names)), dtype=np.float64)
    for k in range(W.shape[1]):
        np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])
    return V, names, Wd


def edge_set(F):
    e = set()
    for t in F:
        a, b, c = int(t[0]), int(t[1]), int(t[2])
        for u, v in ((a, b), (b, c), (a, c)):
            e.add((u, v) if u < v else (v, u))
    return e


def parent_map(g, names):
    """`parent` -> dict(nom -> nom du parent). Le lecteur rend une LISTE d'indices ; on la
    normalise ici plutot que de supposer sa forme (l'inverse a coute une trace ce cycle)."""
    par = g.get('parent')
    if isinstance(par, dict):
        return par
    out = {}
    if par is None:
        return out
    for i, p in enumerate(par):
        try:
            pi = int(p)
        except (TypeError, ValueError):
            continue
        if 0 <= pi < len(names) and i < len(names):
            out[names[i]] = names[pi]
    return out


def descendants(par, roots, names_set):
    """Fermeture descendante : un poids sur un DESCENDANT non simule est quand meme entraine."""
    drv = set(roots)
    changed = True
    while changed:
        changed = False
        for j, p in par.items():
            if p in drv and j not in drv and j in names_set:
                drv.add(j)
                changed = True
    return drv


def arc_of(P, verts):
    """Abscisse curviligne normalisee (racine=0, pointe=1) — pour DIRE OU est la cassure."""
    seg = P[1:] - P[:-1]
    L2 = np.maximum((seg * seg).sum(axis=1), 1e-9)
    cum = np.concatenate([[0.0], np.cumsum(np.sqrt(L2))])
    total = cum[-1] if cum[-1] > 1e-9 else 1.0
    best_d = np.full(len(verts), np.inf)
    best_t = np.zeros(len(verts))
    for i in range(len(seg)):
        w = verts - P[i]
        t = np.clip((w @ seg[i]) / L2[i], 0.0, 1.0)
        q = P[i] + t[:, None] * seg[i]
        d = np.linalg.norm(verts - q, axis=1)
        upd = d < best_d
        best_d[upd] = d[upd]
        best_t[upd] = cum[i] + t[upd] * np.sqrt(L2[i])
    return best_t / total


def measure(chain_joints, idx_of, par, Wd, edges, pos_groups, frozen):
    """Compte les aretes et les sommets coincidents qui enjambent la frontiere fige/mobile.

    `frozen` = les joints de la chaine declares NON MOBILES. Tout le reste de la chaine (et leurs
    descendants) est mobile. On rend aussi la fraction mobile par sommet, pour situer la cassure."""
    present = [j for j in chain_joints if j in idx_of]
    if len(present) < 2:
        return None
    moving = [j for j in present if j not in frozen]
    if not moving:
        return None
    names_set = set(idx_of)
    drv = descendants(par, moving, names_set) if par else set(moving)
    # un joint FIGE de la chaine ne redevient pas mobile par la fermeture
    drv -= set(frozen)
    cols = [idx_of[j] for j in drv if j in idx_of]
    if not cols:
        return None
    mov_frac = Wd[:, cols].sum(1)

    # les sommets DE LA CHAINE : ceux qui portent du poids sur un joint de la chaine (fige inclus),
    # sinon on raterait justement le cote fige de la frontiere.
    allcols = [idx_of[j] for j in present]
    own = np.flatnonzero(Wd[:, allcols].sum(1) > 0.0)
    ownset = set(int(x) for x in own)
    if not ownset:
        return None

    tear = [(u, v) for (u, v) in edges
            if (u in ownset or v in ownset) and abs(mov_frac[u] - mov_frac[v]) > JUMP]
    weld = 0
    for grp in pos_groups.values():
        if len(grp) > 1 and any(i in ownset for i in grp):
            vals = [mov_frac[i] for i in grp]
            if max(vals) - min(vals) > JUMP:
                weld += 1
    return dict(tear=tear, weld=weld, mov=mov_frac, own=own)


def main():
    glb = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    g = c6.load_geometry('keira-hd', glb=glb)
    if g is None:
        print('mesh introuvable : %s' % glb)
        return 1
    V, names, Wd = dense_weights(g)
    idx_of = {n: i for i, n in enumerate(names)}
    par = parent_map(g, names)
    F = g.get('F')
    if F is None:
        print('ARETES ILLISIBLES — la mesure ne peut pas etre prise, et un zero ne voudrait rien dire')
        return 1
    edges = edge_set(F)
    P = g.get('P')

    pos_groups = {}
    for i in range(len(V)):
        pos_groups.setdefault((round(float(V[i][0]), 3), round(float(V[i][1]), 3),
                               round(float(V[i][2]), 3)), []).append(i)

    chains = parse_chains(CHAINS)
    print('ARETES QUI ENJAMBENT LA FRONTIERE FIGE/MOBILE — mesh : %s' % glb)
    print('NATURE compte d\'aretes · REPERE fraction de poids portee par les joints qui BOUGENT')
    print('(maillon 0 exclu si rootlock=1) · ABSENT tear_mov = 0')
    print('%d sommets, %d aretes, %d joints' % (len(V), len(edges), len(names)))
    print('')
    print('%-12s %5s %8s %8s %6s   %s' % ('chaine', 'n', 'tear_aveugle', 'tear_mov', 'weld', 'ou (abscisse des aretes cassees)'))

    results = {}
    for cn in sorted(chains):
        cj = chains[cn]['joints']
        rl = chains[cn]['rootlock']
        present = [j for j in cj if j in idx_of]
        if len(present) < 2:
            continue
        # LECTURE AVEUGLE : celle de ROOM-SKINCOV — le maillon 0 compte comme pilote.
        blind = measure(cj, idx_of, par, Wd, edges, pos_groups, frozen=set())
        # LECTURE HONNETE : le maillon epingle est fige, parce qu'il l'est.
        frozen = {present[0]} if rl else set()
        hon = measure(cj, idx_of, par, Wd, edges, pos_groups, frozen=frozen)
        if hon is None:
            continue
        results[cn] = (blind, hon, frozen)

        where = '-'
        if hon['tear'] and P is not None:
            jidx = [idx_of[j] for j in present]
            try:
                Pj = np.array([P[i] for i in jidx], dtype=np.float64)
                s = arc_of(Pj, V)
                sv = sorted(set([float(s[u]) for (u, v) in hon['tear']]
                                + [float(s[v]) for (u, v) in hon['tear']]))
                where = 's=%.2f..%.2f (median %.2f)' % (sv[0], sv[-1], sv[len(sv) // 2])
            except Exception:
                where = '(abscisse non calculable)'
        print('%-12s %5d %8d %8d %6d   %s'
              % (cn, len(hon['own']), len(blind['tear']) if blind else -1,
                 len(hon['tear']), hon['weld'], where))

    # ---- CONTROLE POSITIF : ON RECOLLE DE LA PEAU SUR `head`, ET LE COMPTE DOIT MONTER ---------
    #
    # PREMIERE VERSION REFUSEE, ET C'EST LA MESURE QUI L'A REFUSEE. Elle declarait fige un maillon
    # INTERMEDIAIRE de la chaine ; le compte a BAISSE partout (lbang 18 -> 0, backhair 28 -> 0).
    # La SPEC 7 est explicite : « un controle qui fait BAISSER le compteur est un controle casse ».
    # La cause est mecanique et vaut d'etre ecrite : figer un maillon ne fabrique pas un defaut
    # independant, il change la DEFINITION de « mobile » pour toute la chaine. Les sommets distaux
    # perdaient assez de fraction mobile pour que la marche existante repasse SOUS le seuil de 0.5
    # — l'injection MASQUAIT le defaut qu'elle etait censee ajouter.
    #
    # LA VERSION QUI TIENT injecte le defaut tel qu'il se produit REELLEMENT : on prend des sommets
    # bien a l'interieur de la zone pilotee (abscisse > 0.7, fraction mobile > 0.9) et on recolle
    # leur poids a 100 % sur `head`, un os fige. C'est exactement « un polygone soude au crane colle
    # a des polygones mobiles ». On touche aux DONNEES, pas a l'interpretation, donc le reste de la
    # chaine garde le sens qu'il avait.
    print('')
    print('CONTROLE POSITIF : on recolle de la peau sur `head` (os fige) au coeur de la zone')
    print('pilotee. C\'est le defaut lui-meme, injecte. Le compte doit MONTER.')
    print('%-12s %10s %10s %9s   %s' % ('chaine', 'tear_mov', 'injecte', 'delta', 'sommets recolles'))
    fired = tested = 0
    head_col = idx_of.get('head')
    for cn in sorted(results):
        cj = chains[cn]['joints']
        present = [j for j in cj if j in idx_of]
        base, frozen = results[cn][1], results[cn][2]
        if head_col is None or P is None:
            continue
        try:
            Pj = np.array([P[idx_of[j]] for j in present], dtype=np.float64)
            s = arc_of(Pj, V)
        except Exception:
            continue
        cand = [int(i) for i in base['own']
                if s[i] > 0.7 and base['mov'][i] > 0.9]
        if len(cand) < 3:
            continue
        victims = cand[:max(3, len(cand) // 4)]
        W2 = Wd.copy()
        W2[victims, :] = 0.0
        W2[victims, head_col] = 1.0
        inj = measure(cj, idx_of, par, W2, edges, pos_groups, frozen=frozen)
        if inj is None:
            continue
        tested += 1
        d = len(inj['tear']) - len(base['tear'])
        if d > 0:
            fired += 1
        print('%-12s %10d %10d %+9d   %d sommets a s>0.7'
              % (cn, len(base['tear']), len(inj['tear']), d, len(victims)))
    print('')
    print('CONTROLE: %d chaine(s) sur %d testees ont vu le compte MONTER.' % (fired, tested))
    if tested and fired < tested:
        print('  Une chaine dont le compte NE MONTE PAS quand on lui recolle de la peau sur un os')
        print('  fige ne mesure pas ce qu\'elle annonce : ses zeros ne prouvent rien.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
