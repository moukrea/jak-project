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

CYCLE 89 — TROIS GRANDEURS AJOUTEES, TOUTES GEOMETRIQUES, AUCUNE DE PHYSIQUE.
  `L`   le PREMIER MOMENT de chair, `SOMME_v SOMME_j w(v,j).(v_bind - p_j_bind)`, en base
        d'ANCRE. C'est le terme par lequel le TENSEUR de deformation deplace la peau sans
        deplacer un joint : `d_tens = (D - I).L / N`. Sans lui `d_COM` n'est qu'une BORNE
        INFERIEURE, et c'est ce qui laissait sa §10 indecidable depuis le cycle 64.
  `W0`  l'etendue LATERALE du nuage de chair en pose de bind — le denominateur de la clause
        « Outward COM migration per breast: 4-10% W0 ». Il valait 776,1 u dans la PROSE de
        `SPEC-COVERAGE.md` §6 et **n'avait aucun producteur dans le depot** : aucun script ne
        le calculait, aucune trace ne le portait. Un denominateur sans producteur n'est pas
        une mesure.
  `axes` le triedre de sa §7 en base d'ancre, mesure et non construit : `+X` = separation
        racine-a-racine (donc MIROITE par chaine, comme sa §7 l.130-131 l'exige), `+Z` = la
        direction du centroide de chair depuis la racine (la SAILLIE), orthogonalisee contre
        `+X`, `+Y = +Z x +X`. « toward thorax » de sa §10 est `-Z`.

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
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

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
    # LA BASE DE L'ANCRE, celle ou vivent `PHYSORICOML` et `PHYSDFMA` : les colonnes de
    # l'inverse de l'inverse-bind de `chest`, normalisees. `anch(v) = R^T v`.
    js, bufs = read_glb(os.path.join(REPO, glb) if not os.path.isabs(glb) else glb)
    _nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
    R = np.linalg.inv(np.array(ibms[ai], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    out['anchor_ortho'] = float(np.abs(R.T @ R - np.eye(3)).max())
    anch = lambda v: R.T @ np.asarray(v, dtype=float)
    # +X SORTANT : la separation racine-a-racine, exactement opposee entre les deux seins.
    sepv = anch(P[names.index('rBoob')] - P[names.index('lBoob')])
    sepv = sepv / np.linalg.norm(sepv)
    OUTW = {'chestL': -sepv, 'chestR': sepv}
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
            # PREMIER MOMENT DE CHAIR, en base d'ancre — le levier par lequel le tenseur agit.
            Lm = np.zeros(3)
            for k, ji in enumerate(idx):
                Lm += (wj[sel, k][:, None] * (V[sel] - P[ji])).sum(axis=0)
            Lm = anch(Lm)
            # W0 : etendue du nuage sur le lateral de l'ancre (le signe est indifferent a une
            # etendue, donc `sepv` brut suffit et le resultat est le meme sur les deux seins).
            lat = (V[sel] - P[ai]) @ R @ np.array([1.0, 0.0, 0.0])
            w0 = float(lat.max() - lat.min())
            print('PROBE-COM-MASS: %-8s w>=%.2f  n=%-4d  %s  N=%d  '
                  'part_chaine=%.4f  bras_bind(u): %s  centroide=%.1f'
                  % (cname, cut, n,
                     '  '.join('W[%s]=%8.3f' % (joints[k], Wj[k]) for k in range(len(idx))),
                     n, sum(Wj) / n,
                     ' '.join('%s=%.1f' % (joints[k], arms[k]) for k in range(len(idx))), arm_c))
            rec['defs'].append(dict(cut=cut, n=n, W=Wj, arms=arms, arm_centroid=arm_c,
                                    L=[float(x) for x in Lm], W0=w0))
            print('PROBE-COM-MASS: %-8s w>=%.2f  L(ancre)=[%+9.1f %+9.1f %+9.1f] u   W0=%.1f u'
                  % (cname, cut, Lm[0], Lm[1], Lm[2], w0))
        # LE TRIEDRE DE SA §7, en base d'ancre. `+Z` est la SAILLIE (centroide depuis la racine)
        # orthogonalisee contre `+X` pour que « toward thorax » et « outward » ne se melangent pas.
        selz = wsum >= 0.05
        xo = OUTW[cname]
        zf = anch(V[selz].mean(axis=0) - P[idx[0]])
        zf = zf - float(zf @ xo) * xo
        zf = zf / np.linalg.norm(zf)
        # SEUL `+X` EST MIROITE. Sa §7 l.130-131 ecrit « for the left and right breasts, outward
        # +X should be MIRRORED » — et RIEN d'autre : `+Y = upward along torso` et
        # `+Z = forward from chest` sont communs aux deux seins. Construire `+Y = +Z x +X` avec un
        # `+X` miroite le retourne d'une chaine a l'autre (mesure : 167.7 deg entre les deux `up`),
        # ce qui est faux des qu'on s'en sert pour autre chose qu'une ECHELLE (une norme est
        # aveugle au signe, une projection ne l'est pas — [[feedback_directional_clause_read_as_a_norm]]).
        # `+Y` se construit donc sur un `+X` COMMUN, celui de chestR, et il sort identique des
        # deux cotes.
        yu = np.cross(zf, OUTW['chestR'])
        rec['axes'] = {'out': [float(v) for v in xo], 'up': [float(v) for v in yu],
                       'fwd': [float(v) for v in zf]}
        print('PROBE-COM-MASS: %-8s +X=[%+.5f %+.5f %+.5f] +Y=[%+.5f %+.5f %+.5f]'
              ' +Z=[%+.5f %+.5f %+.5f]' % (cname, *xo, *yu, *zf))
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
