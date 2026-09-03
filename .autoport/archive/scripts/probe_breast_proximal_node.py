#!/usr/bin/env python3
"""probe_breast_proximal_node.py — DERIVE LE NOEUD PROXIMAL DE LA POITRINE, ET PREDIT SON EFFET.

POURQUOI CET INSTRUMENT (2026-08-18, cycle 22). `probe_breast_anchor30.py` publie, sur le mesh
LIVRE, un plancher qu'AUCUN exposant admissible ne peut franchir :

    chestL  StrongRootFraction mesuree 0.416   cible 0.30   fraction ATTEIGNABLE LA PLUS BASSE 0.390
    chestR                     mesuree 0.459   cible 0.30                                      0.446

`StrongRootFraction` est la PART DES SOMMETS dont l'ancrage depasse 0.55, et l'ancrage vaut
`RootAnchor * (1-r)^p`. A `p` fixe, cette part ne depend donc plus que de la DISTRIBUTION de `r` —
c'est-a-dire de la GEOMETRIE, pas du repesage. Et cette distribution est tassee a l'origine :

    chestL / chestR   s : p25 = 0.000
    bande « Deep root » r < 0.125 : 26 sommets sur 77 (33.8 %) et 29 sur 74 (39.2 %)

Un tiers de la chair de l'organe se projette AU NOEUD RACINE LUI-MEME et herite donc en bloc de
l'ancrage de racine. C'est la chair ARRIERE du sein, celle qui vit entre `chest` et `lBoob` : la
polyligne de la chaine commence a `lBoob`, donc tout ce qui est en amont s'ecrase a s=0.

DEUX FACONS DE CHANGER CE CHIFFRE, ET UNE SEULE EST HONNETE :
  - changer le calcul de `r` (reparametrer l'abscisse) : c'est modifier l'instrument pour faire
    bouger un nombre. INTERDIT, et c'est le piege `dont-change-the-instrument`.
  - changer la GEOMETRIE : un noeud proximal entre `chest` et `lBoob` etale ce bloc sur une plage
    d'abscisse reelle au lieu de le tasser en r=0. C'est la meme classe que l'os DISTAL qui pilote
    aujourd'hui 73 % de la chair, a l'autre bout de l'organe.

CE QUE CE SCRIPT FAIT, ET CE QU'IL NE FAIT PAS. Il DERIVE la position depuis la geometrie (jamais
choisie, jamais ajustee pour atteindre 0.30 — ce serait `never-fit-a-parameter-to-the-instrument`)
et il PREDIT la table de bandes et le StrongRootFraction qui en sortiraient. Il ne cuit rien, ne
modifie rien, n'ecrit aucun asset. La cuisson du cycle suivant CONFIRME ou FALSIFIE ces chiffres.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  : une DISTRIBUTION d'abscisse, et la part des sommets qu'elle place au-dessus d'un seuil
            d'ancrage. Pas une amplitude.
  REPERE  : la polyligne des joints de la chaine en pose de bind, racine=0 -> apex=1 (le `r` de sa
            SPEC 31), exactement l'instrument de `probe_breast_anchor30.py` — reutilise, pas reecrit.
  ABSENT  : si le noeud proximal n'apportait rien, la distribution de `r` serait inchangee et le
            StrongRootFraction atteignable resterait a 0.390 / 0.446.

USAGE : python3 .autoport/probe_breast_proximal_node.py [chemin.glb]
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_c6_volumes as c6                                        # noqa: E402
import probe_breast_anchor30 as A30                                    # noqa: E402
from probe_skin_profile import parse_chain_joints, arc_param, CHAINS, SHIPPED   # noqa: E402

UNITS = 4096.0          # unites de jeu par metre
# L'ANCRE RIGIDE DE LA POITRINE, telle que sa SPEC 30 la nomme (« r = 0 at chest attachment »).
ANCHOR_BONE = {'chestL': 'chest', 'chestR': 'chest'}


def cloud(cname, joints, names, idx_of, P, V, J, W):
    """Le nuage de la chaine et son poids somme — MEME selection que probe_breast_anchor30
    (`gate` sur le poids SOMME DE LA CHAINE), pour que les deux tables soient comparables."""
    grp = [idx_of[j] for j in joints if j in idx_of]
    ws = np.zeros(len(W))
    for c in range(J.shape[1]):
        ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
    vi = np.flatnonzero(ws > A30.GATE)
    return vi, ws[vi], grp


def bands_of(s, anchor):
    """La table des cinq bandes de la 30, calculee comme A30 la calcule."""
    out = []
    edges = [(0.000, 0.125), (0.125, 0.375), (0.375, 0.625), (0.625, 0.875), (0.875, 1.001)]
    for (lo, hi), (_r, blo, bhi, label) in zip(edges, A30.BANDS):
        m = (s >= lo) & (s < hi)
        n = int(m.sum())
        a = float(anchor[m].mean()) if n else float('nan')
        verdict = 'DANS' if (n and blo <= a <= bhi) else ('SOUS' if n and a < blo else
                                                          ('AU-DESSUS' if n else '(vide)'))
        out.append((label, lo, hi, n, a, blo, bhi, verdict))
    return out


def strongfrac_range(s):
    """Part des sommets « fortement ancres » (>= 0.55) sur TOUT l'intervalle d'exposants que les
    trois bandes interieures de la 30 autorisent. Le MINIMUM de cette plage est le plancher
    structurel : aucun repesage ne peut descendre dessous SANS changer la geometrie."""
    plo, phi = A30.feasible_p()
    best, bestp = 1.0, None
    for p in np.linspace(plo, phi, 400):
        f = float((A30.anchor_of(s, p) >= A30.STRONG).mean())
        if f < best:
            best, bestp = f, float(p)
    return plo, phi, best, bestp


def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry('keira-hd', glb=rel)
    if geo is None:
        raise SystemExit('mesh introuvable : %s' % rel)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}
    chains = parse_chain_joints(CHAINS)

    print('NOEUD PROXIMAL DE LA POITRINE — DERIVATION ET PREDICTION')
    print('mesh : %s' % rel)
    print('NATURE distribution d abscisse · REPERE polyligne des joints de la chaine, pose de')
    print('bind, racine=0 apex=1 (le `r` de sa SPEC 31) · ABSENT la distribution de r ne bouge pas')
    print('et le plancher atteignable reste 0.390 / 0.446\n')

    spec = []
    for cname in ('chestL', 'chestR'):
        rec = chains.get(cname)
        joints = rec['joints'] if rec else None
        if not joints:
            print('%s : absente du fichier de chaines (gelee ?)' % cname)
            continue
        anch = ANCHOR_BONE[cname]
        if anch not in idx_of:
            raise SystemExit('%s : ancre `%s` absente du rig' % (cname, anch))
        vi, ws, grp = cloud(cname, joints, names, idx_of, P, V, J, W)
        Pc = np.asarray([P[g] for g in grp], dtype=float)
        verts = np.asarray(V[vi], dtype=float)
        s0, _b0 = arc_param(Pc, verts)

        print('=== %s   n=%d sommets (poids somme chaine > %.2f), joints %s'
              % (cname, len(vi), A30.GATE, ' -> '.join(joints)))

        # ---- ETAT ACTUEL -----------------------------------------------------------------------
        plo, phi, f_now, p_now = strongfrac_range(s0)
        deep = int((s0 < 0.125).sum())
        print('  ACTUEL   s p25=%.3f p50=%.3f   bande Deep root r<0.125 : %d/%d = %.1f %%'
              % (np.percentile(s0, 25), np.percentile(s0, 50), deep, len(s0),
                 100.0 * deep / len(s0)))
        print('           StrongRootFraction ATTEIGNABLE LA PLUS BASSE = %.3f (p=%.3f, '
              'exposants admissibles [%.3f, %.3f])  cible %.2f'
              % (f_now, p_now, plo, phi, A30.STRONG_FRAC))

        # ---- DERIVATION DE LA POSITION ---------------------------------------------------------
        # Le bloc a etaler est celui qui se projette SUR le noeud racine (s == 0 au flottant pres).
        # On le projette sur le segment `chest -> lBoob`, et le noeud va a sa MEDIANE DE MASSE —
        # la meme regle que `subdiv` applique aux meches (« position = mediane de masse du
        # segment »), transposee au bout PROXIMAL. La regle est recopiee, pas inventee.
        a_w, b_w = P[idx_of[anch]], P[grp[0]]
        ab = b_w - a_w
        L = float(np.linalg.norm(ab))
        blk = np.flatnonzero(s0 <= 1e-6)
        if len(blk) == 0:
            print('  aucun sommet ne se projette sur le noeud racine — pas de bloc a etaler')
            continue
        t = ((verts[blk] - a_w) @ ab) / float(ab @ ab)
        wblk = ws[blk]
        order = np.argsort(t)
        cw = np.cumsum(wblk[order])
        t_med = float(t[order][np.searchsorted(cw, 0.5 * cw[-1])])
        t_med = float(np.clip(t_med, 0.05, 0.95))
        newP = a_w + t_med * ab
        print('  BLOC A ETALER : %d sommets a s<=1e-6 (%.1f %% du nuage), poids somme %.3f'
              % (len(blk), 100.0 * len(blk) / len(s0), float(wblk.sum())))
        print('  projection sur %s -> %s (longueur %.4f m) : t p05=%.3f MEDIANE DE MASSE=%.3f '
              'p95=%.3f' % (anch, joints[0], L / UNITS, float(np.percentile(t, 5)), t_med,
                            float(np.percentile(t, 95))))

        # ---- PREDICTION ------------------------------------------------------------------------
        Pn = np.vstack([newP[None, :], Pc])
        s1, _b1 = arc_param(Pn, verts)
        plo1, phi1, f_new, p_new = strongfrac_range(s1)
        deep1 = int((s1 < 0.125).sum())
        print('  PREDIT   s p25=%.3f p50=%.3f   bande Deep root r<0.125 : %d/%d = %.1f %%'
              % (np.percentile(s1, 25), np.percentile(s1, 50), deep1, len(s1),
                 100.0 * deep1 / len(s1)))
        print('           StrongRootFraction ATTEIGNABLE LA PLUS BASSE = %.3f (p=%.3f)  cible %.2f'
              '   -> %s' % (f_new, p_new, A30.STRONG_FRAC,
                            'DANS la bande 0.28-0.35' if 0.28 <= f_new <= 0.35 else
                            ('ATTEINT la cible' if f_new <= A30.STRONG_FRAC else
                             'TOUJOURS AU-DESSUS')))
        print('           bandes predites avec p=%.3f :' % p_new)
        for label, lo, hi, n, a, blo, bhi, verdict in bands_of(s1, A30.anchor_of(s1, p_new)):
            print('             %-18s r %.3f-%.3f  n=%3d  ancrage=%.3f  bande %.2f-%.2f  %s'
                  % (label, lo, hi, n, a, blo, bhi, verdict))

        newbone = float(np.linalg.norm(newP - b_w)) / UNITS
        nm = joints[0][0] + joints[0][1:].replace('Boob', 'Booa')

        # ---- QUEL VERBE ? LA COLINEARITE TRANCHE, ET ELLE SE MESURE. -------------------------
        # Le noeud proximal n'a de raison d'exister QUE s'il change l'abscisse. S'il tombe sur la
        # meme droite que la chaine, la polyligne a 3 noeuds et la polyligne a 2 noeuds dont la
        # RACINE A GLISSE decrivent la meme courbe — donc la meme abscisse, donc le meme
        # StrongRootFraction. Alors le noeud n'apporte rien qu'un glissement n'apporte pas, et il
        # coute un index (PARENT-ORDER), un reparentage, et un os que la bande « Deep root » de la
        # 30 plafonne a 0.10 de tout sommet : un os que la geometrie ignore.
        tip_w = P[grp[-1]]
        ac = tip_w - a_w
        troot = float(((b_w - a_w) @ ac) / float(ac @ ac))
        offroot = float(np.linalg.norm((b_w - a_w) - troot * ac)) / UNITS
        u1 = (b_w - a_w) / np.linalg.norm(b_w - a_w)
        u2 = (P[grp[1]] - b_w) / np.linalg.norm(P[grp[1]] - b_w)
        ang = float(np.degrees(np.arccos(np.clip(float(u1 @ u2), -1.0, 1.0))))
        s2, _b2 = arc_param(np.vstack([newP[None, :], Pc[1:]]), verts)
        dmax = float(np.abs(s1 - s2).max())
        print('  COLINEARITE  %s->%s vs %s->%s : %.5f deg   ecart de %s a la droite %s->%s : '
              '%.6f m' % (anch, joints[0], joints[0], joints[1], ang, joints[0], anch, joints[-1],
                          offroot))
        print('  ABSCISSE : |s(3 noeuds) - s(racine glissee)| max = %.2e — les deux operations '
              'sont la MEME mesure' % dmax)
        spec.append((cname, anch, nm, newP / UNITS, newbone, t_med, f_now, f_new, joints[0],
                     ang, offroot, dmax))
        print()

    if spec:
        print('SPEC DERIVEE — a recopier dans recharged_assets/keira-hd-inject-joints.txt.')
        print('CORRECTION DE LA NOTE DU CYCLE 22 : elle annoncait « le rig passe de 107 a 109')
        print('joints et TOUS les indices au-dela du point d insertion se decalent ». Le decalage')
        print('etait juste, et il est REDHIBITOIRE : quatre consommateurs exigent hd_parent < k')
        print('(retarget_fill_table.py PARENT-ORDER, hd_splice_joint_tables.py append-only,')
        print('physics_keira_gen2.py:470, et la boucle de retarget jak-hd.gc:497 qui lit la bone')
        print('du parent DEJA retargetee cette frame). Un noeud appendu en fin de skin.joints')
        print('donnerait hd_parent > k et serait refuse. La colinearite mesuree ci-dessus rend le')
        print('noeud inutile : la racine GLISSE a la meme position, meme abscisse, meme')
        print('StrongRootFraction, zero index touche.\n')
        print('# LA POSITION EST LA MEME POUR LES DEUX VERBES ; SEUL LE COUT DIFFERE.')
        print('# `reroot` GLISSE la racine de chaine a cette position sur son propre os. Aucun')
        print('# joint cree, aucun index, aucun parent change — donc aucune des quatre gardes')
        print('# PARENT-ORDER (retarget_fill_table.py / hd_splice_joint_tables.py /')
        print('# physics_keira_gen2.py:470 / jak-hd.gc:497) n a a etre touchee.')
        print('# `prepend` INSERE un noeud et reparente la racine. Il ne se justifie que si la')
        print('# chaine N EST PAS colineaire — sinon il ajoute un os que la bande « Deep root »')
        print('# de la 30 plafonne a 0.10 de tout sommet, c est-a-dire un os que la geometrie')
        print('# ignore (regle du 2026-08-18 08:55).')
        print('# chaine    joint    ancre    x            y            z    (metres)')
        for (cname, anch, nm, p, blen, t_med, f0, f1, root,
             ang, offroot, dmax) in spec:
            print('reroot  %-9s %-8s %-8s %11.6f %12.6f %12.6f'
                  % (cname, root, anch, p[0], p[1], p[2]))
            print('#   t mediane de masse=%.3f sur %s->%s  os %s->%s raccourci de %.4f m  '
                  'StrongRootFraction atteignable %.3f -> %.3f'
                  % (t_med, anch, root, anch, root, blen, f0, f1))
            print('#   colinearite %.5f deg, racine a %.6f m de la droite ancre->pointe, '
                  '|ds| max %.2e vs le noeud insere' % (ang, offroot, dmax))
        print('#')
        print('# La forme `prepend`, pour memoire et pour un rig NON colineaire :')
        for (cname, anch, nm, p, blen, t_med, f0, f1, root,
             ang, offroot, dmax) in spec:
            print('# prepend %-9s %-8s %-8s %-12s %11.6f %12.6f %12.6f'
                  % (cname, anch, root, nm, p[0], p[1], p[2]))


if __name__ == '__main__':
    main()
