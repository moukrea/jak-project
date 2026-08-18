#!/usr/bin/env python3
"""probe_breast_com_mass.py — LA MASSE DE CHAIR PORTEE PAR CHAQUE MAILLON DE LA POITRINE.

POURQUOI. SPEC 10/11/12 chiffrent un deplacement de **COM** (`SupineCOMDepth 0.23 B0`,
`HangingCOMDisplacement 0.24 B0`, `SideGravityCOM 0.19 B0`). La salle ne sait publier que le
deplacement de l'**APEX** (le point que le solveur integre) : `ROOM-ORICOM` le dit lui-meme et
declare que c'est une BORNE SUPERIEURE, pas la grandeur visee. Comparer un apex a une cible de
COM est exactement le piege `instrument-axis-vs-complaint` — et c'est pour ca que le rapport du
cycle 20 refuse de re-regler §10/§12 avant d'avoir fait bouger l'instrument.

CE QUE CETTE SONDE PRODUIT, ET RIEN D'AUTRE. Sous skinning lineaire, le deplacement d'un sommet
vaut la somme ponderee des deplacements de ses joints. Dans le repere de l'ancre (`chest`), un
joint NON simule a un deplacement identiquement nul — il n'a aucun ecart a la pose d'auteur.
Donc, sur l'ensemble de sommets qui constitue l'organe :

    d_COM = ( W_0 * d_0  +  W_1 * d_1 ) / N          W_j = somme des poids du joint j
                                                     N   = nombre de sommets de l'organe
                                                     d_j = deplacement du maillon j (salle)

La sonde ne mesure QUE `W_0`, `W_1`, `N`. Les `d_j` viennent de la course. Aucune valeur de
physique n'est choisie ici.

LA FRONTIERE DE L'ORGANE EST UN CHOIX : ON LA PUBLIE TROIS FOIS. §30 veut « no hard attachment
boundary », donc il n'existe pas de bord net a lire dans la donnee. Trois definitions sont
publiees cote a cote (`w>0`, `w>=0.05`, `w>=0.25`) : si les trois rendent le meme rapport, la
frontiere ne decide pas du verdict ; si elles divergent, c'est CA la mesure et le rapport le dit.

MESH : celui du PACK LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`), jamais le rip brut du
donneur — piege `reskin-measure-the-prepped-input`, paye une fois deja sur cette phase.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
CHAINS = {'chestL': ['lBoob', 'lBooc'], 'chestR': ['rBoob', 'rBooc']}
ANCHOR = 'chest'
CUTS = [0.0, 0.05, 0.25]


def main():
    glb = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    g = c6.load_geometry('keira-hd', glb=glb)
    if g is None:
        print('PROBE-COM-MASS: ABSENT %s — non mesure (aucun repli sur le rip brut)' % glb)
        return 1
    names = list(g['names'])
    V, J, W, P = g['V'], g['J'], g['W'], g['P']
    print('PROBE-COM-MASS: source=%s  verts=%d  joints=%d' % (g['src'], len(V), len(names)))
    out = {'source': g['src'], 'chains': {}}
    ai = names.index(ANCHOR) if ANCHOR in names else None
    for cname, joints in CHAINS.items():
        idx = [names.index(j) for j in joints if j in names]
        if len(idx) != len(joints):
            print('PROBE-COM-MASS: %s — joint(s) absent(s) du mesh livre : %s  NON MESURE'
                  % (cname, [j for j in joints if j not in names]))
            continue
        # poids de chaque joint de la chaine, par sommet (J/W sont les 4 influences par sommet)
        wj = np.zeros((len(V), len(idx)))
        for k, ji in enumerate(idx):
            wj[:, k] = (W * (J == ji)).sum(axis=1)
        wsum = wj.sum(axis=1)
        rec = {'joints': joints, 'defs': []}
        for cut in CUTS:
            sel = wsum > cut if cut == 0.0 else wsum >= cut
            n = int(sel.sum())
            if n == 0:
                print('PROBE-COM-MASS: %-8s w>=%.2f  DOMAINE VIDE' % (cname, cut))
                continue
            Wj = [float(wj[sel, k].sum()) for k in range(len(idx))]
            # bras de levier de bind, pour situer les maillons (jamais utilise dans d_COM)
            arms = [float(np.linalg.norm(P[ji] - P[ai])) if ai is not None else float('nan')
                    for ji in idx]
            cen = V[sel].mean(axis=0)
            arm_c = float(np.linalg.norm(cen - P[ai])) if ai is not None else float('nan')
            print('PROBE-COM-MASS: %-8s w>=%.2f  n=%-4d  %s  N=%d  '
                  'part_chaine=%.4f  bras_bind(u): %s  centroide=%.1f'
                  % (cname, cut, n,
                     '  '.join('W[%s]=%8.3f' % (joints[k], Wj[k]) for k in range(len(idx))),
                     n, sum(Wj) / n,
                     ' '.join('%s=%.1f' % (joints[k], arms[k]) for k in range(len(idx))), arm_c))
            rec['defs'].append(dict(cut=cut, n=n, W=Wj, arms=arms, arm_centroid=arm_c))
        out['chains'][cname] = rec
    # HORODATAGE DE LA SOURCE — sans lui, un consommateur ne peut pas savoir si ce fichier est
    # PLUS VIEUX que le mesh qu'il pretend decrire. Paye une fois : le 2026-08-18 ce fichier a ete
    # ecrit a 13:15, le mesh recuit a 14:05, et `ROOM-ORICOM-MASS` a compose les huit valeurs de
    # §10/§11/§12 de la course de 17:31 avec les poids du mesh d'AVANT (W[lBooc] 23.9 au lieu de
    # 33.0, soit 38 % d'ecart) en imprimant le chemin du mesh LIVRE comme provenance. Le chemin
    # etait juste, l'instant etait faux, et rien ne pouvait le voir.
    path = g.get('path') or os.path.join(REPO, g['src'])
    src_abs = path if os.path.isabs(path) else os.path.join(REPO, path)
    try:
        st = os.stat(src_abs)
        out['source_mtime'] = st.st_mtime
        out['source_size'] = st.st_size
    except OSError:
        out['source_mtime'] = None
        out['source_size'] = None
    dest = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion/breast-com-mass.json')
    json.dump(out, open(dest, 'w'), indent=1)
    print('PROBE-COM-MASS: ecrit %s' % os.path.relpath(dest, REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main())
