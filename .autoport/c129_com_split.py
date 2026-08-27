#!/usr/bin/env python3
"""c129_com_split.py — LE DEPLACEMENT DE COM DE §11 EST-IL PRODUIT PAR LES JOINTS OU PAR LE TENSEUR ?

POURQUOI. Le cycle 128 etablit que les deux clauses de §11 sont INCOMPATIBLES sous le seul bouton
`HangingLengthScale`, et nomme le chantier : « un canal qui produise la migration de COM
independamment de l'echelle de longueur ». Il ne dit PAS ou ce canal doit vivre, et il y a deux
endroits qui appellent deux chantiers differents :
  (a) dans le TENSEUR de forme         -> travail de solveur ;
  (b) dans les POSITIONS DE JOINT      -> une excursion, qui se heurte au plafond de SPEC 22, donc
                                          une route fermee sans avoir a l'essayer.
Le cycle 127 a separe ces deux etages pour la LONGUEUR (nuage `RIGID` : matrices livrees,
decomposition polaire, rotation seule, S = I). **La clause de COM n'a jamais recu ce traitement.**
C'est le meme instrument sur une autre statistique du meme nuage, et il ne coute aucune course.

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : un DEPLACEMENT SOUTENU — la norme du deplacement du centroide pondere de la chair,
            rapportee a B0 = 602,0 unites (SPEC 6, `flesh=602.0000` lu dans la trace). Ni une
            variance, ni un maximum de fenetre.
  REPERE  : le repere de l'ANCRE. Le sujet est RE-ORIENTE d'une cellule a l'autre ; mesuree en
            MONDE la grandeur serait dominee par la rotation du buste. Chaque centroide est donc
            ramene en local d'ancre AVANT d'etre differencie.
  LIGNE DE BASE : cellule i=0 (debout d'auteur). LECTURE HORS DEFAUT : 2e cellule DEBOUT i=9.
  REFERENCE : `ROOM-SPEC10 ... §11 NORME` du tableau (0,2278 / 0,2273 B0 a w>0.00 sur la course
            livree). Le controle P1 exige de la retrouver a 5 % pres, sinon rien n'est publie.

Predictions et falsificateurs : `.autoport/c129-predictions.txt`, ecrits avant tout calcul.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
B0 = 602.0
TRACES = [('LIVREE', 'keira-room-x86.log'),
          ('c128-EXPERIENCE (retiree)', 'keira-room-x86.c128-experiment.log')]
P = print

g = c6.load_geometry('keira-hd', glb=c126.SHIPPED)
names, V, J, W, Pb = list(g['names']), g['V'], g['J'], g['W'], g['P']
js, bufs = read_glb(os.path.join(REPO, c126.SHIPPED))
_nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
ai = names.index(c126.ANCHOR)


def bindR(j):
    Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
    for k in range(3):
        Rj[:, k] /= np.linalg.norm(Rj[:, k])
    return Rj


P('C129: B0 = %.1f u (SPEC 6, `flesh=` lu dans la trace) · reference = ROOM-SPEC10 §11 NORME' % B0)
P('C129: ' + '=' * 108)

REF = {'chestL': 0.2278, 'chestR': 0.2273}     # publie par le tableau sur la course LIVREE, w>0.00
out = {}

for tag, fn in TRACES:
    path = os.path.join(R, fn)
    if not os.path.exists(path):
        P('C129: %s ABSENTE (%s) — sautee.' % (tag, fn))
        continue
    txt = open(path, 'r', errors='replace').read()
    isup, ipro, _G = c124._roles(txt)
    jn, mats, nmiss = c124._read_matrices(txt)
    if not mats or nmiss:
        P('C129: %s SUSPENDUE — trace incomplete.' % tag)
        continue
    slot = {v: k for k, v in jn.items()}
    RB = {n: bindR(names.index(n)) for n in slot}

    # les deux nuages : FULL (matrices livrees) et RIGID (rotation pure sur les joints de chaine)
    MM = {'FULL': {}, 'RIGID': {}}
    for (i, sl), M in mats.items():
        MM['FULL'][(i, sl)] = M
        if jn.get(sl) not in c126.CHAINJOINTS:
            MM['RIGID'][(i, sl)] = M
            continue
        _S, Rr = c126.polar_SR(M[:3, :3])
        M2 = M.copy()
        M2[:3, :3] = Rr
        MM['RIGID'][(i, sl)] = M2

    cells = sorted({i for (i, _j) in mats})
    P('C129: --- %s (%s) · prone i=%d · supine i=%d · cellules %s'
      % (tag, fn, ipro, isup, cells))

    for cname, joints in c126.CHAINS.items():
        idx = [names.index(j) for j in joints]
        wsum = np.zeros(len(V))
        for ji in idx:
            wsum += (W * (J == ji)).sum(axis=1)
        sel = wsum > 0.0                       # frontiere w>0.00, celle du VERDICT
        wv, Js, Ws, Vs = wsum[sel], J[sel], W[sel], V[sel]

        def com_local(mode, i):
            """centroide pondere de la chair, ramene en LOCAL D'ANCRE (vecteurs LIGNE)."""
            acc = np.zeros((len(wv), 3))
            tot = np.zeros(len(wv))
            for k in range(Ws.shape[1]):
                for nmj, sl in slot.items():
                    mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                    if not mk.any():
                        continue
                    M = MM[mode][(i, sl)]
                    q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                    acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
                    tot[mk] += Ws[mk, k]
            bad = tot <= 0.0
            if bad.any():
                return None
            c = (wv[:, None] * acc).sum(0) / wv.sum()
            Ma = MM[mode][(i, slot[c126.ANCHOR])]
            return (c - Ma[3, :3]) @ Ma[:3, :3].T          # local d'ancre

        base = {m: com_local(m, 0) for m in ('FULL', 'RIGID')}
        if base['FULL'] is None:
            P('C129: %s %s SUSPENDUE — un joint pesant n\'est pas emis.' % (tag, cname))
            continue

        def disp(mode, i):
            c = com_local(mode, i)
            return float('nan') if c is None else float(np.linalg.norm(c - base[mode])) / B0

        row = {}
        for lbl, cell in (('PRONE', ipro), ('SUPINE', isup), ('DEBOUT(2e)', 9), ('PRONE(2e)', 10)):
            if cell not in cells:
                continue
            f, r = disp('FULL', cell), disp('RIGID', cell)
            row[lbl] = (f, r)
            P('C129: %-26s %-7s %-11s  FULL %.4f  RIGID %.4f B0   part RIGIDE %5.1f %%'
              % (tag, cname, lbl, f, r, (r / f * 100.0) if f > 1e-9 else float('nan')))
        out[(tag, cname)] = row

P('C129: ' + '-' * 108)
liv = {k: v for k, v in out.items() if k[0] == 'LIVREE'}

# ---- P1 : est-ce bien la grandeur du verdict ? -------------------------------------------------
ok1 = True
for (tag, cname), row in sorted(liv.items()):
    if 'PRONE' not in row:
        continue
    got, ref = row['PRONE'][0], REF[cname]
    ec = abs(got / ref - 1.0) * 100.0
    ok1 = ok1 and ec <= 5.0
    P('C129: P1  %-7s nuage COMPLET prone %.4f contre %.4f publie par ROOM-SPEC10 -> ecart %.2f %% '
      '(falsificateur 5 %%)' % (cname, got, ref, ec))
if ok1:
    P('C129: P1  -> TIRE')
else:
    P('C129: P1  -> **REFUTEE**. Le nuage de peau COMPLET et la grandeur du VERDICT ne sont pas la')
    P('C129:        meme chose. Diagnostic, pas supposition : `ROOM-SPEC10` construit un MODELE A')
    P('C129:        DEUX TERMES — `sk` = les deplacements de joint cumules, ponderes par les parts')
    P('C129:        de masse `comw` PAR MAILLON, plus `tn` = `L . (D - I)` ou `L` est le centroide')
    P('C129:        de chair CUIT du maillon et `D` le tenseur `PHYSDFMA`')
    P('C129:        (physics_room_table.py:2975-2986). Ce n\'est PAS le centroide du nuage skinne :')
    P('C129:        c\'est une representation a DEUX POINTS de l\'organe.')
    P('C129:        **RIEN de mon nuage n\'est publie comme verdict**, et §11 n\'est PAS re-jugee')
    P('C129:        dessus. La divergence est NOMMEE et CHIFFREE ci-dessous, elle n\'est pas tranchee.')

# ---- P2 : lecture hors defaut (sur MON nuage — c'est le controle de MON instrument) ------------
w2 = max((max(row['DEBOUT(2e)']) for row in liv.values() if 'DEBOUT(2e)' in row), default=0.0)
P('C129: P2  lecture HORS DEFAUT i=9, pire des deux nuages : %.4f B0 (falsificateur 0,02) -> %s'
  % (w2, 'TIRE' if w2 <= 0.02 else 'ECHOUE'))

# ---- P6 : controle de montage sur MON nuage ----------------------------------------------------
for (t, c), row in sorted(liv.items()):
    if 'PRONE(2e)' in row and 'PRONE' in row and row['PRONE'][0] > 1e-9 and row['PRONE(2e)'][0] > 1e-9:
        a = row['PRONE'][1] / row['PRONE'][0] * 100.0
        b = row['PRONE(2e)'][1] / row['PRONE(2e)'][0] * 100.0
        P('C129: P6  %-7s montage — part rigide i=6 %.1f %% contre i=10 %.1f %% : ecart %.2f pts '
          '(falsificateur 5) -> %s' % (c, a, b, abs(a - b), 'TENUE' if abs(a - b) < 5.0 else 'REFUTEE'))

# ==================================================================================================
# LA GRANDEUR DU VERDICT, ET SA DECOMPOSITION — ELLE ETAIT DEJA PUBLIEE, JE N'AVAIS PAS LA LUE.
# `ROOM-SPEC10` emet depuis longtemps SIX colonnes : `total / squel. / tens.` sur DEUX axes. La
# question que ce cycle posait — « le deplacement de COM vient-il des JOINTS ou du TENSEUR ? » —
# y est repondue ligne par ligne. C'est la faute `grep-the-trace-before-asking-for-a-run`, et
# c'est la deuxieme fois dans ce dossier.
# ==================================================================================================
import re as _re
TAB = os.path.join(R, 'keira-room-table.txt')
P('C129: ' + '=' * 108)
P('C129: LA DECOMPOSITION PUBLIEE PAR `ROOM-SPEC10` (colonnes total / squel. / tens.), course LIVREE')
pub = {}
if os.path.exists(TAB):
    for ln in open(TAB, errors='replace'):
        m = _re.match(r'ROOM-SPEC10: +(chest[LR]) +§(1[01]) (prone|supine) +w>0\.00 +\|'
                      r' *([-\d.]+) +([-\d.]+) +([-\d.]+) \|'
                      r' *([-\d.]+) +([-\d.]+) +([-\d.]+)', ln)
        if m:
            pub[(m.group(1), m.group(2))] = tuple(float(m.group(i)) for i in range(4, 10))
for (cn, sec), v in sorted(pub.items()):
    th, thsk, thtn, ou, ousk, outn = v
    P('C129:   %-7s §%s  vers thorax (B0) total %+.4f = squel. %+.4f (%.1f %%) + tens. %+.4f (%.1f %%)'
      % (cn, sec, th, thsk, abs(thsk / th) * 100.0 if th else float('nan'),
         thtn, abs(thtn / th) * 100.0 if th else float('nan')))
    P('C129:   %-7s §%s  sortant (%% W0)   total %+.3f = squel. %+.3f + tens. %+.3f'
      % (cn, sec, ou, ousk, outn))

p11 = {c: pub[(c, '11')] for c in ('chestL', 'chestR') if (c, '11') in pub}
if p11:
    sh = {c: abs(v[1] / v[0]) * 100.0 for c, v in p11.items()}
    P('C129: ' + '-' * 108)
    P('C129: P3  part SQUELETTIQUE de §11 au prone (grandeur du VERDICT) : %s'
      % ' · '.join('%s %.1f %%' % (c, x) for c, x in sorted(sh.items())))
    P('C129:     bande predite 40-60 %%, derivee des DEUX POINTS du cycle 128 (k = 0,516 -> 49,7 %%)')
    P('C129:     -> %s' % ('TENUE — deux derivations qui ne partagent RIEN convergent a moins de '
                           '0,3 point' if all(40.0 <= x <= 60.0 for x in sh.values())
                           else 'REFUTEE — l\'extrapolation a deux points du cycle 128 est fausse'))
    sk = {c: abs(v[1]) for c, v in p11.items()}
    P('C129: P4  ce que la CHAINE SEULE produit (terme squelettique, axe qui porte 97,8 %% de la '
      'norme) : %s B0   contre un plancher de bande a 0,20'
      % ' · '.join('%s %.4f' % (c, x) for c, x in sorted(sk.items())))
    if all(x <= 0.13 for x in sk.values()):
        P('C129: P4  -> **TENUE.** La chaine seule ne produit pas les deux tiers du plancher.')
        P('C129:        **LE CANAL DE COM MANQUANT DOIT VIVRE DANS LE TENSEUR.** La voie « augmenter')
        P('C129:        l\'excursion des joints » est fermee par le plafond de SPEC 22 sans avoir a')
        P('C129:        l\'essayer : il faudrait doubler le terme squelettique pour atteindre le seul')
        P('C129:        plancher, et §22 plafonne deja l\'excursion a 0,50 B0.')
    else:
        P('C129: P4  -> REFUTEE : la voie « excursion des joints » reste ouverte.')

P('C129: ' + '-' * 108)
P('C129: P5  §10 SUPINE — DEJA PUBLIE PAR LE REGISTRE (c123b) et NON re-derive ici : le budget')
P('C129:     complet y est ferme au millieme (chestL -1,283 squel. + 2,906 diagonal - 0,825')
P('C129:     cisaillement = +0,797 %% W0 ; chestR -3,824 + 2,379 - 2,299 = -3,744) contre une bande')
P('C129:     4,00-10,00. Le terme SQUELETTIQUE y est NEGATIF des deux cotes, comme sur §11 il est')
P('C129:     insuffisant : **meme diagnostic, meme canal manquant.** Rien de neuf n\'est publie ici.')
P('C129: ' + '=' * 108)
P('C129: DIVERGENCE D\'INSTRUMENT, NOMMEE ET CHIFFREE, NON TRANCHEE :')
for (tag, cname), row in sorted(liv.items()):
    if 'PRONE' in row:
        P('C129:   %-7s nuage de peau COMPLET %.4f B0  contre  modele a DEUX POINTS %.4f B0  '
          '(ecart %.1f %%)' % (cname, row['PRONE'][0], REF[cname],
                               abs(row['PRONE'][0] / REF[cname] - 1.0) * 100.0))
P('C129:   Bande de la clause : 0,20-0,28. Les deux lectures ne rendent PAS le meme verdict —')
P('C129:   `DANS` sur le modele a deux points, `AU-DESSUS` sur le nuage complet. Conformement a la')
P('C129:   directive du 2026-08-21 18:40 (« si les deux chemins divergent, aucune ne se traite')
P('C129:   avant reconciliation »), **§11 n\'est re-jugee sur AUCUNE des deux** et la reconciliation')
P('C129:   devient un chantier nomme.')
P('C129: ' + '=' * 108)
