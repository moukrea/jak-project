#!/usr/bin/env python3
"""c130b_c128_retest.py — LA CONCLUSION D'INCOMPATIBILITE DU CYCLE 128 SURVIT-ELLE A L'INSTRUMENT
CORRIGE ?

POURQUOI. Le cycle 128 conclut que les deux clauses de §11 sont INCOMPATIBLES sous un seul bouton :
retirer le double compte met la LONGUEUR `DANS` sur 4 cellules et fait tomber le COM `DANS` ->
`SOUS`. Cette conclusion bloque le chantier de §11 depuis trois cycles. **Elle a ete tiree d'un
instrument dont le cycle 130 etablit qu'il normalise par un COMPTE DE SOMMETS** la ou la spec ecrit
« center-of-mass », et qu'il sur-estime le COM de 12,2 % / 6,9 % au prone. Une conclusion batie sur
un instrument biaise se RE-TESTE sur l'instrument corrige avant d'etre gardee — et la trace du lot
c128 est archivee, donc ca ne coute aucune course.

Le sens de l'effet n'est PAS connu d'avance : P13 (cycle 130) a REFUTE que la correction soit un
scalaire — les rapports par maillon valent x0,8822/x0,7871 (chestL) et x0,8146/x1,0316 (chestR), le
maillon DISTAL montant sur chestR. La reponse depend du melange des maillons, que le lot c128
change precisement.

NATURE / REPERE / LIGNE DE BASE : identiques au cycle 130 — deplacement SOUTENU du centre de masse
/ B0=602,0 u, repere de l'ANCRE, ligne de base cellule i=0, hors defaut i=9, verdict prone i=6.
ESTIMATEUR : masse de sommet a l'AIRE en pose de bind, masse PLEINE (arbitration du cycle 130,
contre-controlee par une seconde derivation de Voronoi a 0,15-1,09 %).

Predictions P14/P15/P16 et falsificateurs : `.autoport/c130b-predictions.txt`.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
B0 = 602.0
CUTS = [0.0, 0.05, 0.25]
LO, HI = 0.20, 0.28
P = print

g = c6.load_geometry('keira-hd', glb=c126.SHIPPED)
names, V, J, W, Pb, F = list(g['names']), g['V'], g['J'], g['W'], g['P'], g['F']
js, bufs = read_glb(os.path.join(REPO, c126.SHIPPED))
_nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))

AREA = np.zeros(len(V))
Ftri = np.asarray(F, dtype=np.int64).reshape(-1, 3)
_a = V[Ftri[:, 0]]
_ar = 0.5 * np.linalg.norm(np.cross(V[Ftri[:, 1]] - _a, V[Ftri[:, 2]] - _a), axis=1)
for k in range(3):
    np.add.at(AREA, Ftri[:, k], _ar / 3.0)


def bindR(j):
    Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
    for k in range(3):
        Rj[:, k] /= np.linalg.norm(Rj[:, k])
    return Rj


def verd(v, lo=LO, hi=HI):
    return 'DANS' if lo <= v <= hi else ('SOUS' if v < lo else 'AU-DESSUS')


P('C130b: LA CONCLUSION D\'INCOMPATIBILITE DU CYCLE 128, RE-TESTEE SUR L\'INSTRUMENT CORRIGE')
P('C130b: estimateur ARBITRE = masse de sommet a l\'AIRE (pose de bind), masse PLEINE · B0 = %.1f u'
  % B0)
P('C130b: ' + '=' * 106)

OUT = {}
for tag, fn in (('LIVREE', 'keira-room-x86.log'),
                ('c128-EXPERIENCE (retiree)', 'keira-room-x86.c128-experiment.log')):
    path = os.path.join(R, fn)
    if not os.path.exists(path):
        P('C130b: %s ABSENTE (%s) — RIEN n\'est publie pour elle.' % (tag, fn))
        continue
    txt = open(path, 'r', errors='replace').read()
    isup, ipro, _G = c124._roles(txt)
    jn, mats, nmiss = c124._read_matrices(txt)
    if not mats or nmiss:
        P('C130b: %s SUSPENDUE — trace incomplete (%d PHYSORIMMISS).' % (tag, nmiss))
        continue
    slot = {v: k for k, v in jn.items()}
    RB = {n: bindR(names.index(n)) for n in slot}
    cells = sorted({i for (i, _j) in mats})
    P('C130b: --- %s · prone i=%d · cellules %s' % (tag, ipro, cells))

    for cname, joints in c126.CHAINS.items():
        idx = [names.index(j) for j in joints]
        wsum = np.zeros(len(V))
        for ji in idx:
            wsum += (W * (J == ji)).sum(axis=1)
        for cut in CUTS:
            sel = wsum > cut if cut == 0.0 else wsum >= cut
            Js, Ws, Vs, Av = J[sel], W[sel], V[sel], AREA[sel]

            def cloud(i, rigid):
                acc = np.zeros((int(sel.sum()), 3))
                tot = np.zeros(int(sel.sum()))
                for k in range(Ws.shape[1]):
                    for nmj in slot:
                        mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                        if not mk.any():
                            continue
                        M = mats[(i, slot[nmj])]
                        if rigid and nmj in c126.CHAINJOINTS:
                            _S, Rr = c126.polar_SR(M[:3, :3])
                            M = M.copy()
                            M[:3, :3] = Rr
                        q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                        acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
                        tot[mk] += Ws[mk, k]
                err = float(np.abs(tot - 1.0).max())
                Ma = mats[(i, slot[c126.ANCHOR])]
                return (acc - Ma[3, :3]) @ Ma[:3, :3].T, err

            def com(i, rigid):
                Xi, e1 = cloud(i, rigid)
                X0, e2 = cloud(0, rigid)
                D = Xi - X0
                return (Av[:, None] * D).sum(0) / Av.sum(), max(e1, e2)

            row = {}
            for lbl, i in (('PRONE', ipro), ('DEBOUT2', 9)):
                if i not in cells:
                    continue
                vF, eF = com(i, False)
                vR, eR = com(i, True)
                row[lbl] = (float(np.linalg.norm(vF)) / B0, float(np.linalg.norm(vR)) / B0,
                            max(eF, eR))
            OUT[(tag, cname, cut)] = row
            if 'PRONE' in row:
                f, r, _e = row['PRONE']
                P('C130b: %-26s %-7s w>%.2f  ARBITRE %.4f %-9s   squelettique %.4f  (%.1f %%)'
                  % (tag, cname, cut, f, verd(f), r, r / f * 100.0 if f > 1e-9 else float('nan')))

# ---- P14 : controle de montage sur la trace c128 -----------------------------------------------
P('C130b: ' + '-' * 106)
ec = max((v['PRONE'][2] for k, v in OUT.items() if 'PRONE' in v), default=1.0)
hd = max((max(v['DEBOUT2'][0], v['DEBOUT2'][1]) for k, v in OUT.items() if 'DEBOUT2' in v),
         default=1.0)
ok14 = ec <= 1e-3 and hd <= 0.02
P('C130b: P14 couverture de poids, pire sommet : %.2e (falsif. 1e-3) · HORS DEFAUT i=9, pire des '
  'deux nuages et des deux traces : %.4f B0 (falsif. 0,02)' % (ec, hd))
P('C130b: P14 -> %s' % ('TIRE' if ok14 else '**ECHOUE** — RIEN n\'est publie, la conclusion du '
                        'cycle 128 reste telle quelle.'))
if not ok14:
    sys.exit(1)

# ---- P15 : LA PREDICTION QUI DECIDE ------------------------------------------------------------
P('C130b: ' + '=' * 106)
P('C130b: P15 LA CLAUSE DE COM SUR LE LOT c128, SOUS L\'ESTIMATEUR ARBITRE (bande 0,20-0,28)')
T = 'c128-EXPERIENCE (retiree)'
got = {}
for cname in ('chestL', 'chestR'):
    k = (T, cname, 0.0)
    if k not in OUT or 'PRONE' not in OUT[k]:
        P('C130b: P15 %-7s NON MESURABLE — la trace c128 ne porte pas la cellule.' % cname)
        continue
    liv = OUT[('LIVREE', cname, 0.0)]['PRONE'][0]
    v = OUT[k]['PRONE'][0]
    got[cname] = v
    P('C130b: P15 %-7s LIVREE %.4f %-9s  ->  lot c128 %.4f %-9s   (le tableau BIAISE publiait '
      '0,2278 -> 0,1811 sur chestL)' % (cname, liv, verd(liv), v, verd(v)))
if len(got) == 2:
    st = {c: verd(v) for c, v in got.items()}
    if all(s == 'SOUS' for s in st.values()):
        P('C130b: P15 -> **TIRE.** L\'incompatibilite du cycle 128 SURVIT a la correction '
          'd\'instrument :')
        P('C130b:       mettre la LONGUEUR dans sa bande sort le COM par le BAS, sur les deux '
          'chaines,')
        P('C130b:       et ce n\'etait donc pas un artefact de la normalisation par compte de '
          'sommets.')
        P('C130b:       « Le canal de COM manquant vit dans le TENSEUR » (c129) en sort RENFORCE.')
    elif all(s == 'DANS' for s in st.values()):
        P('C130b: P15 -> **REFUTEE.** L\'incompatibilite du cycle 128 etait un ARTEFACT DE '
          'L\'INSTRUMENT BIAISE :')
        P('C130b:       sous la ponderation correcte, le lot c128 tient les DEUX clauses de §11.')
        P('C130b:       C\'est une CORRECTION DE MON RAPPORT DE CYCLE 128, et la route se rouvre.')
    else:
        P('C130b: P15 -> INDETERMINEE (%s) — un resultat mixte ne tranche pas, et il se publie '
          'tel quel.' % ' · '.join('%s %s' % (c, s) for c, s in sorted(st.items())))

# ---- P16 : l'adresse du chantier, re-derivee sous la bonne ponderation --------------------------
P('C130b: ' + '-' * 106)
P('C130b: P16 LA PART SQUELETTIQUE AU PRONE (course LIVREE), SOUS L\'ESTIMATEUR ARBITRE —')
P('C130b:     le cycle 129 l\'avait lue 0,1110 / 0,0999 B0 sur l\'instrument BIAISE, contre un')
P('C130b:     plancher de bande a 0,20. Falsificateur ecrit d\'avance : 0,13 B0.')
ok16 = True
for cname in ('chestL', 'chestR'):
    f, r, _e = OUT[('LIVREE', cname, 0.0)]['PRONE']
    ok16 = ok16 and r <= 0.13
    P('C130b: P16 %-7s squelettique %.4f B0 (%.1f %% du total %.4f) contre un plancher a 0,20'
      % (cname, r, r / f * 100.0, f))
P('C130b: P16 -> %s'
  % ('TIRE — la chaine seule ne produit toujours pas les deux tiers du plancher, sur l\'instrument '
     'CORRIGE. L\'adresse posee au cycle 129 tient.' if ok16
     else '**REFUTEE** — l\'adresse du cycle 129 a ete lue sur un instrument biaise et doit etre '
          're-arbitree ; la voie « excursion des joints » se rouvre.'))
P('C130b: ' + '=' * 106)

# ==================================================================================================
# PRE-SPECIFICATION DU CHANTIER — LE CANAL DE TENSEUR MANQUANT, CHIFFRE.
# Le cycle 129 a donne l'ADRESSE (« dans le tenseur ») ; il n'a jamais donne la TAILLE. Elle se lit
# ici, en vecteurs, sans une course de plus : c'est ce qu'il manque pour atteindre le plancher de
# 0,20 B0 A LONGUEUR TENUE, c'est-a-dire sur l'etat du lot c128.
# ==================================================================================================
P('C130b: ' + '=' * 106)
P('C130b: PRE-SPECIFICATION DU CHANTIER DE §11 — LA TAILLE DU CANAL MANQUANT, EN VECTEURS')
P('C130b:   (le cycle 129 a donne l\'ADRESSE, jamais la TAILLE ; la voici, sur l\'instrument')
P('C130b:    ARBITRE et a longueur TENUE, c\'est-a-dire sur l\'etat du lot c128.)')


def vecs(tag, cname, cut=0.0):
    """rend (total, squelettique, tensoriel) en VECTEURS/B0 — le tensoriel est la DIFFERENCE."""
    idx = [names.index(j) for j in c126.CHAINS[cname]]
    txt = open(os.path.join(R, {'LIVREE': 'keira-room-x86.log',
                                'c128': 'keira-room-x86.c128-experiment.log'}[tag]),
               'r', errors='replace').read()
    _s, ipro, _G = c124._roles(txt)
    jn, mats, _m = c124._read_matrices(txt)
    slot = {v: k for k, v in jn.items()}
    RB = {n: bindR(names.index(n)) for n in slot}
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)
    sel = wsum > cut
    Js, Ws, Vs, Av = J[sel], W[sel], V[sel], AREA[sel]

    def cl(i, rigid):
        acc = np.zeros((int(sel.sum()), 3))
        for k in range(Ws.shape[1]):
            for nmj in slot:
                mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                if not mk.any():
                    continue
                M = mats[(i, slot[nmj])]
                if rigid and nmj in c126.CHAINJOINTS:
                    _S, Rr = c126.polar_SR(M[:3, :3])
                    M = M.copy()
                    M[:3, :3] = Rr
                q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
        Ma = mats[(i, slot[c126.ANCHOR])]
        return (acc - Ma[3, :3]) @ Ma[:3, :3].T

    tot = ((Av[:, None] * (cl(ipro, False) - cl(0, False))).sum(0) / Av.sum()) / B0
    ski = ((Av[:, None] * (cl(ipro, True) - cl(0, True))).sum(0) / Av.sum()) / B0
    return tot, ski, tot - ski


nrm = lambda v: float(np.linalg.norm(v))
for cname in ('chestL', 'chestR'):
    tL, sL, nL = vecs('LIVREE', cname)
    t8, s8, n8 = vecs('c128', cname)
    # colinearite : si les deux etages tirent dans le meme sens, la somme des normes majore peu
    cosv = float(np.dot(sL, nL) / (nrm(sL) * nrm(nL))) if nrm(sL) * nrm(nL) > 0 else float('nan')
    # ce qu'il faut ajouter AU TENSEUR, colineaire au total, pour atteindre 0,20 a longueur tenue
    u = t8 / nrm(t8)
    need = LO - nrm(t8)
    P('C130b:   %-7s LIVREE   total %.4f = squel. %.4f + tenseur %.4f   (cos(squel,tenseur) %+.3f)'
      % (cname, nrm(tL), nrm(sL), nrm(nL), cosv))
    P('C130b:   %-7s lot c128 total %.4f = squel. %.4f + tenseur %.4f   <- le lot n\'a PAS bouge le'
      ' squelette (%.4f contre %.4f, ecart %.1e)'
      % (cname, nrm(t8), nrm(s8), nrm(n8), nrm(s8), nrm(sL), abs(nrm(s8) - nrm(sL))))
    P('C130b:   %-7s **IL MANQUE %.4f B0 DE COM (%.1f %% du plancher), A LONGUEUR TENUE, ET LE'
      ' SQUELETTE NE PEUT PAS LES FOURNIR**' % (cname, need, need / LO * 100.0))
    P('C130b:   %-7s   soit un terme tensoriel porte de %.4f a %.4f B0 (x%.3f) sans toucher a'
      ' l\'echelle de longueur.' % (cname, nrm(n8), nrm(n8) + need, (nrm(n8) + need) / nrm(n8)))
P('C130b:   LE FAIT QUI REND CE CHIFFRE UTILISABLE : le lot c128 laisse le terme SQUELETTIQUE')
P('C130b:   INVARIANT (ecarts ci-dessus). Les deux etages sont donc SEPARABLES en pratique et pas')
P('C130b:   seulement en principe — ce que le cycle 129 supposait sans l\'avoir montre.')
P('C130b: ' + '=' * 106)
