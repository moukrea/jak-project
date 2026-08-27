#!/usr/bin/env python3
"""c130_com_reconcile.py — RECONCILIER LES DEUX LECTURES DU COM DE §11.

POURQUOI. Le cycle 129 publie DEUX nombres pour la MEME clause (« Static COM displacement:
20-28% B0 », l.178) et ils rendent des verdicts OPPOSES :

    nuage de peau COMPLET (c129)         0,3192 / 0,3295 B0  ->  AU-DESSUS
    modele a DEUX POINTS (ROOM-SPEC10)   0,2278 / 0,2273 B0  ->  DANS

La directive du 2026-08-21 18:40 interdit de traiter la clause avant reconciliation. Reconcilier
veut dire : (1) reproduire LES DEUX BOUTS avec UN SEUL code, (2) rendre compte de l'ecart terme a
terme, (3) dire lequel est la grandeur que la spec NOMME — pas choisir celui qui arrange.

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : un DEPLACEMENT SOUTENU — la norme du deplacement du centre de masse de la chair / B0.
  REPERE  : le repere de l'ANCRE (le sujet est re-oriente d'une cellule a l'autre).
  LIGNE DE BASE : cellule i=0 (debout d'auteur) ; HORS DEFAUT : 2e cellule DEBOUT i=9.

Predictions P1..P9 et falsificateurs : `.autoport/c130-predictions.txt`, ecrits avant tout calcul.
ZERO build, ZERO course : tout se lit sur la trace archivee et le mesh livre.
"""
import json
import os
import re
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
P = print

# les deux bouts a reproduire, LUS dans les artefacts des cycles precedents (jamais retapes ici
# comme des constantes de confort : ce sont les references des controles P1 et P2).
REF_2PT = {'chestL': 0.2278, 'chestR': 0.2273}     # ROOM-SPEC10 §11 NORME, w>0.00, course LIVREE
REF_C129 = {'chestL': 0.3192, 'chestR': 0.3295}    # c129-com-split.txt, nuage FULL, prone

g = c6.load_geometry('keira-hd', glb=c126.SHIPPED)
names, V, J, W, Pb, F = list(g['names']), g['V'], g['J'], g['W'], g['P'], g['F']
js, bufs = read_glb(os.path.join(REPO, c126.SHIPPED))
_nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))

# ---- masse de sommet PROPORTIONNELLE A L'AIRE : un tiers de l'aire de chaque triangle incident --
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


P('C130: RECONCILIATION DES DEUX LECTURES DU COM DE §11 — B0 = %.1f u · mesh livre = %s'
  % (B0, c126.SHIPPED))
P('C130: masse de sommet a l\'aire : %d triangles, aire totale %.1f u^2' % (len(Ftri), _ar.sum()))
P('C130: ' + '=' * 108)

txt = open(os.path.join(R, 'keira-room-x86.log'), 'r', errors='replace').read()
isup, ipro, _G = c124._roles(txt)
jn, mats, nmiss = c124._read_matrices(txt)
assert mats and not nmiss, 'trace incomplete'
slot = {v: k for k, v in jn.items()}
RB = {n: bindR(names.index(n)) for n in slot}
cells = sorted({i for (i, _j) in mats})
P('C130: course LIVREE · prone i=%d · supine i=%d · cellules %s' % (ipro, isup, cells))

MASS = json.load(open(os.path.join(R, 'breast-com-mass.json')))
RESULT, P8ok, P7worst = {}, True, 0.0

for cname, joints in c126.CHAINS.items():
    idx = [names.index(j) for j in joints]
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)

    for cut in CUTS:
        sel = wsum > cut if cut == 0.0 else wsum >= cut
        wv, Js, Ws, Vs, Av = wsum[sel], J[sel], W[sel], V[sel], AREA[sel]
        n = int(sel.sum())

        def skinned(i):
            """position skinnee de chaque sommet selectionne, en LOCAL D'ANCRE (vecteurs LIGNE)."""
            acc = np.zeros((n, 3))
            tot = np.zeros(n)
            for k in range(Ws.shape[1]):
                for nmj in slot:
                    mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                    if not mk.any():
                        continue
                    M = mats[(i, slot[nmj])]
                    q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                    acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
                    tot[mk] += Ws[mk, k]
            # P8 — LA GARDE QUE LE CYCLE 129 N'AVAIT PAS : il ne testait que `tot > 0`, ce qui
            # laisse passer un sommet dont 40 % du poids porte sur un joint NON EMIS et dont la
            # position est alors tiree vers l'origine. On exige la couverture COMPLETE.
            err = float(np.abs(tot - 1.0).max())
            Ma = mats[(i, slot[c126.ANCHOR])]
            E = Ma[:3, :3].T.copy()
            return (acc - Ma[3, :3]) @ E, err

        S0, e0 = skinned(0)
        emax = e0
        row = {}
        for lbl, i in (('PRONE', ipro), ('SUPINE', isup), ('DEBOUT2', 9)):
            if i not in cells:
                continue
            Si, ei = skinned(i)
            emax = max(emax, ei)
            D = Si - S0                       # deplacement par sommet, en local d'ancre
            est = {
                'compte': D.mean(axis=0),                                   # masse UNIFORME
                'poids': (wv[:, None] * D).sum(0) / wv.sum(),               # ponderee par w
                'aire': (Av[:, None] * D).sum(0) / Av.sum(),                # masse a l'AIRE
                'aire_w': (Av * wv)[:, None].__mul__(D).sum(0) / (Av * wv).sum(),
            }
            row[lbl] = {k: v / B0 for k, v in est.items()}
        RESULT[(cname, cut)] = dict(row=row, n=n, wsum=float(wv.sum()),
                                    w2=float((wv ** 2).sum()), area=Av.copy(), wv=wv.copy(),
                                    emax=emax)
        P8ok = P8ok and emax <= 1e-3

P('C130: ' + '-' * 108)
P('C130: P8  COUVERTURE DE POIDS — ecart max a 1,0 sur un sommet selectionne : %.2e'
  % max(v['emax'] for v in RESULT.values()))
P('C130: P8  -> %s' % ('TIRE (falsificateur 1e-3)' if P8ok else
                       '**ECHOUE** — le nuage est FAUX, rien n\'est publie.'))
if not P8ok:
    sys.exit(1)

# ==================================================================================================
# LE TABLEAU DES QUATRE ESTIMATEURS, CELLULE DU VERDICT
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: §11 PRONE i=%d — LE MEME DEPLACEMENT, QUATRE PONDERATIONS (B0), norme' % ipro)
P('C130: %-8s %-8s %5s | %-9s %-9s %-9s %-9s'
  % ('chaine', 'frontiere', 'n', 'compte', 'poids w', 'AIRE', 'aire.w'))
nz = lambda v: float(np.linalg.norm(v))
for (cname, cut), rec in sorted(RESULT.items()):
    if 'PRONE' not in rec['row']:
        continue
    e = rec['row']['PRONE']
    P('C130: %-8s w>%.2f    %5d | %9.4f %9.4f %9.4f %9.4f'
      % (cname, cut, rec['n'], nz(e['compte']), nz(e['poids']), nz(e['aire']), nz(e['aire_w'])))

# ---- P1 / P2 : LES DEUX BOUTS SONT-ILS REPRODUITS PAR UN SEUL CODE ? ----------------------------
P('C130: ' + '-' * 108)
ok1 = ok2 = True
for cname in ('chestL', 'chestR'):
    e = RESULT[(cname, 0.0)]['row']['PRONE']
    g1, g2 = nz(e['compte']), nz(e['poids'])
    d1 = abs(g1 / REF_2PT[cname] - 1.0) * 100.0
    d2 = abs(g2 / REF_C129[cname] - 1.0) * 100.0
    ok1, ok2 = ok1 and d1 <= 5.0, ok2 and d2 <= 2.0
    P('C130: P1  %-7s masse UNIFORME %.4f  contre le modele a DEUX POINTS %.4f  -> ecart %5.2f %% '
      '(falsif. 5 %%)' % (cname, g1, REF_2PT[cname], d1))
    P('C130: P2  %-7s ponderee par w %.4f  contre le nuage du cycle 129   %.4f  -> ecart %5.2f %% '
      '(falsif. 2 %%)' % (cname, g2, REF_C129[cname], d2))
P('C130: P1  -> %s' % ('TIRE — le modele a DEUX POINTS de `ROOM-SPEC10` EST le centroide a masse '
                       'uniforme par sommet.' if ok1 else '**REFUTEE** — pas d\'ancrage, rien '
                       'n\'est arbitre.'))
P('C130: P2  -> %s' % ('TIRE — le nuage du cycle 129 EST le centroide pondere par l\'appartenance.'
                       if ok2 else '**REFUTEE** — le pont n\'a pas ses deux bouts.'))

# ---- P3 / P4 : L'ECART SE PREDIT-IL DEPUIS LA SEULE POSE DE BIND ? ------------------------------
P('C130: ' + '-' * 108)
P('C130: P3  k = n.Somme(w^2)/(Somme w)^2 — AUCUNE matrice, AUCUNE course : la POSE DE BIND seule')
ok3 = ok4 = True
for cname in ('chestL', 'chestR'):
    rec = RESULT[(cname, 0.0)]
    k = rec['n'] * rec['w2'] / (rec['wsum'] ** 2)
    e = rec['row']['PRONE']
    mes = nz(e['poids']) / nz(e['compte'])
    d = abs(k / mes - 1.0) * 100.0
    ok3, ok4 = ok3 and d <= 5.0, ok4 and k > 1.15
    P('C130: P3  %-7s k predit %.4f   rapport MESURE %.4f   -> ecart %5.2f %% (falsif. 5 %%)'
      % (cname, k, mes, d))
    P('C130: P4  %-7s k = %.4f > 1,15 ? %s   (w moyen %.4f sur %d sommets)'
      % (cname, k, 'oui' if k > 1.15 else 'NON', rec['wsum'] / rec['n'], rec['n']))
P('C130: P3  -> %s' % ('TIRE — **L\'ECART EST UNE IDENTITE DE PONDERATION**, pas une divergence '
                       'de mesure : aucune troisieme cause n\'est requise.' if ok3
                       else '**REFUTEE** — une TROISIEME cause existe, l\'arbitration est '
                            'reportee jusqu\'a ce qu\'elle soit chiffree.'))
P('C130: P4  -> %s' % ('TIRE' if ok4 else '**REFUTEE** — P3 ne discrimine rien.'))

# ---- P5 : le maillage est-il uniforme ? --------------------------------------------------------
P('C130: ' + '-' * 108)
ok5 = True
for cname in ('chestL', 'chestR'):
    a = RESULT[(cname, 0.0)]['area']
    cv = float(a.std() / a.mean())
    ok5 = ok5 and cv > 0.25
    P('C130: P5  %-7s aire par sommet : moyenne %.2f u^2, ecart-type %.2f, CV %.3f  '
      '(falsif. <= 0,25)  min %.2f max %.2f' % (cname, a.mean(), a.std(), cv, a.min(), a.max()))
P('C130: P5  -> %s' % ('TIRE — compter les sommets N\'EST PAS peser la masse : le maillage est '
                       'trop irregulier pour que le compte serve de proxy.' if ok5
                       else 'REFUTEE — le compte est un proxy acceptable de la masse ; '
                            'l\'estimateur a l\'aire est inutile et je le dis.'))

# ---- P6 : l'arbitration -------------------------------------------------------------------------
P('C130: ' + '=' * 108)
P('C130: P6  L\'ESTIMATEUR ARBITRE — masse a l\'AIRE, masse PLEINE (SPEC 30 l.375 : la chair')
P('C130:     fortement attachee est « of the rear breast VOLUME », donc du sein).')
ok6 = True
for cname in ('chestL', 'chestR'):
    a = nz(RESULT[(cname, 0.0)]['row']['PRONE']['aire'])
    d2p = abs(a / REF_2PT[cname] - 1.0) * 100.0
    dcl = abs(a / REF_C129[cname] - 1.0) * 100.0
    near2p, nearcl = d2p <= 15.0, dcl <= 15.0
    ok6 = ok6 and near2p and not nearcl
    P('C130: P6  %-7s ARBITRE %.4f B0   -> a %5.2f %% du modele a deux points · a %5.2f %% du '
      'nuage pondere  (falsif. 15 %%)' % (cname, a, d2p, dcl))
P('C130: P6  -> %s' % ('TIRE — l\'arbitration designe la MAGNITUDE du modele a deux points.'
                       if ok6 else '**REFUTEE** — la clause se re-juge sur le nombre ARBITRE '
                                   'quel qu\'il soit.'))
P('C130: ' + '-' * 108)
P('C130: VERDICT DE LA CLAUSE §11 « Static COM displacement: 20-28% B0 » SUR L\'ESTIMATEUR ARBITRE,')
P('C130:   aux TROIS frontieres d\'organe (la sensibilite reste publiee, elle n\'est pas cachee) :')
for cname in ('chestL', 'chestR'):
    vs = []
    for cut in CUTS:
        v = nz(RESULT[(cname, cut)]['row']['PRONE']['aire'])
        vs.append('w>%.2f %.4f %s' % (cut, v, 'DANS' if 0.20 <= v <= 0.28
                                      else ('SOUS' if v < 0.20 else 'AU-DESSUS')))
    P('C130:   %-8s %s' % (cname, '  ·  '.join(vs)))
    P('C130:   %-8s cible statique haute 0,30 B0 : %s'
      % (cname, 'franchie' if max(nz(RESULT[(cname, c)]['row']['PRONE']['aire'])
                                  for c in CUTS) > 0.30 else 'NON franchie'))

# ---- P7 : hors defaut ---------------------------------------------------------------------------
P('C130: ' + '-' * 108)
for cname in ('chestL', 'chestR'):
    r = RESULT[(cname, 0.0)]['row'].get('DEBOUT2')
    if r is None:
        P('C130: P7  %-7s cellule i=9 ABSENTE de la trace — controle NON FAIT, et je le dis.' % cname)
        continue
    w = max(nz(v) for v in r.values())
    P7worst = max(P7worst, w)
    P('C130: P7  %-7s HORS DEFAUT i=9, pire des quatre ponderations : %.4f B0' % (cname, w))
P('C130: P7  -> %s (falsificateur 0,02)'
  % ('TIRE' if P7worst <= 0.02 else '**ECHOUE** — rien n\'est publie.'))

# ==================================================================================================
# P9 — LA SECTION QUI PEUT RETOMBER : §12 EST `TENUE` SUR LA MEME NORMALISATION
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: P9  §12, clause l.194 « Upper/opposite breast medial migration: 10-18%% W0 » — MEME')
P('C130:     normalisation par COMPTE DE SOMMETS. Recalculee sous la ponderation ARBITREE.')
role = {}
for m in re.finditer(r'^ROOM-SPEC12:   i=(\d+)  g_lateral\(ancre\) = ([-\d.]+)  ->  (.+)$',
                     open(os.path.join(R, 'keira-room-table.txt'), errors='replace').read(), re.M):
    role[int(m.group(1))] = m.group(3).strip()
P('C130:     roles lus dans le tableau livre : %s' % (role if role else 'ABSENTS'))
ok9 = True
for cname in ('chestL', 'chestR'):
    ax = MASS['chains'][cname]['axes']
    outv = np.array(ax['out'], dtype=float)
    w0 = float(MASS['chains'][cname]['defs'][0]['W0'])
    for i in (2, 4):
        if i not in cells:
            continue
        rec = RESULT[(cname, 0.0)]
        # on refait le deplacement a cette cellule (non stocke plus haut)
        idx = [names.index(j) for j in c126.CHAINS[cname]]
        wsum = np.zeros(len(V))
        for ji in idx:
            wsum += (W * (J == ji)).sum(axis=1)
        sel = wsum > 0.0
        wv, Js, Ws, Vs, Av = wsum[sel], J[sel], W[sel], V[sel], AREA[sel]

        def sk(ii):
            acc = np.zeros((int(sel.sum()), 3))
            for k in range(Ws.shape[1]):
                for nmj in slot:
                    mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                    if not mk.any():
                        continue
                    M = mats[(ii, slot[nmj])]
                    q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                    acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
            Ma = mats[(ii, slot[c126.ANCHOR])]
            return (acc - Ma[3, :3]) @ Ma[:3, :3].T
        D = sk(i) - sk(0)
        med = lambda v: -float(v @ outv) / w0 * 100.0     # MEDIAL = oppose au sortant
        cptv, airv = med(D.mean(axis=0)), med((Av[:, None] * D).sum(0) / Av.sum())
        lab = role.get(i, '?')
        nom = ('chestL' if 'chestL' in lab and 'OPPOS' in lab.upper() else
               ('chestR' if 'chestR' in lab and 'OPPOS' in lab.upper() else None))
        adr = (nom == cname)
        st = lambda x: 'DANS' if 10.0 <= x <= 18.0 else ('SOUS' if x < 10.0 else 'AU-DESSUS')
        P('C130: P9  %-7s i=%d  compte %+7.3f %% W0 (%s)  ->  AIRE %+7.3f %% W0 (%s)   %s'
          % (cname, i, cptv, st(cptv), airv, st(airv),
             'SEIN NOMME PAR LA CLAUSE' if adr else 'diagnostic — la clause ne nomme pas ce sein'))
        if adr:
            ok9 = ok9 and st(airv) == 'DANS'
P('C130: P9  -> %s'
  % ('TIRE — §12 ne retombe pas : sa clause porteuse reste DANS sa bande sous la ponderation '
     'arbitree.' if ok9 else '**REFUTEE** — le `TENUE` de §12 est un FAUX VERT produit par la '
     'ponderation, et §12 est retrogradee DANS CE CYCLE.'))
P('C130: ' + '=' * 108)

# ==================================================================================================
# P1b — POST-HOC, DECLARE COMME TEL : LE RESIDU DE P1 EST-IL L'AGREGATION ?
# On REIMPLEMENTE la formule publiee sur LA MEME trace. Si elle reproduit le nombre du tableau,
# alors le seul ecart entre elle et l'estimateur exact est l'AGREGATION, et il est mesure.
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: P1b REIMPLEMENTATION DE LA FORMULE PUBLIEE `(W0.d0 + W1.d1 + L.(D-I))/n` (post-hoc)')
ldb = {}
for m in re.finditer(r'^PHYSORICOML c=(\d+) i=(\d+) l=(\d+) dv=([-\d.e+]+)'
                     r' dap=([-\d.e+]+) dlat=([-\d.e+]+)', txt, re.M):
    # (dlat, dv, dap) = (e0, e1, e2) de l'ancre — la convention du tableau, ligne 2713.
    ldb[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = np.array(
        [float(m.group(6)), float(m.group(4)), float(m.group(5))])
drows = {}
for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+)'
                     r' m1=([-\d.e+]+) m2=([-\d.e+]+)', txt, re.M):
    drows.setdefault((int(m.group(1)), int(m.group(2))), {})[int(m.group(3))] = [
        float(m.group(4)), float(m.group(5)), float(m.group(6))]
CIDX = {'chestL': 0, 'chestR': 1}          # `PHYSCHAIN c=0 j0=lBoob` / `c=1 j0=rBoob`
ok1b = True
BRIDGE = {}
for cname in ('chestL', 'chestR'):
    c, i = CIDX[cname], ipro
    d = MASS['chains'][cname]['defs'][0]
    Wj, nn, L = d['W'], float(d['n']), np.array(d['L'], dtype=float)
    D = np.array([drows[(c, i)][r] for r in range(3)], dtype=float)
    cum = [ldb[(c, i, 0)], ldb[(c, i, 0)] + ldb[(c, i, 1)]]      # somme telescopique
    sk = (Wj[0] * cum[0] + Wj[1] * cum[1]) / nn
    tn = np.array([sum((D[a][b] - (1.0 if a == b else 0.0)) * L[a] for a in range(3))
                   for b in range(3)]) / nn
    v = float(np.linalg.norm(sk + tn)) / B0
    dd = abs(v / REF_2PT[cname] - 1.0) * 100.0
    ok1b = ok1b and dd <= 1.0
    ex = nz(RESULT[(cname, 0.0)]['row']['PRONE']['compte'])
    BRIDGE[cname] = (v, ex)
    P('C130: P1b %-7s reimplementation %.4f  contre `ROOM-SPEC10` %.4f  -> ecart %.2f %% '
      '(falsif. 1 %%)' % (cname, v, REF_2PT[cname], dd))
P('C130: P1b -> %s'
  % ('TIRE — la ligne de verdict EST cette formule. Le seul ecart avec l\'estimateur EXACT a masse '
     'uniforme est donc l\'AGREGATION (un seul `D` en un seul `L`), et il est chiffre ci-dessous.'
     if ok1b else '**REFUTEE** — je ne sais pas ce que publie la ligne de verdict ; '
                  'l\'arbitration est NON ANCREE et la clause reste sans verdict.'))

# ---- LE PONT COMPLET : CHAQUE PAS EST NOMME ET MESURE -------------------------------------------
P('C130: ' + '=' * 108)
P('C130: LE PONT — de 0,2278 a 0,3192, chaque pas NOMME et MESURE (prone, w>0,00, B0)')
P('C130: %-8s %-9s %-9s %-9s %-9s' % ('', 'DEUX PTS', 'exact', 'ARBITRE', 'pondere w'))
for cname in ('chestL', 'chestR'):
    twop, ex = BRIDGE[cname]
    ar = nz(RESULT[(cname, 0.0)]['row']['PRONE']['aire'])
    wp = nz(RESULT[(cname, 0.0)]['row']['PRONE']['poids'])
    P('C130: %-8s %9.4f %9.4f %9.4f %9.4f' % (cname, twop, ex, ar, wp))
    P('C130: %-8s   |--AGREGATION x%.4f--|--TESSELLATION x%.4f--|      |--PONDERATION x%.4f--|'
      % ('', ex / twop, ar / ex, wp / ex))
P('C130:   AGREGATION   : un seul tenseur `D` en un seul premier moment `L`, au lieu des matrices')
P('C130:                  par sommet. C\'est le cout du modele a DEUX POINTS, et il MONTE le chiffre.')
P('C130:   TESSELLATION : compter les sommets au lieu de peser l\'aire qu\'ils portent (CV 0,60-0,65).')
P('C130:   PONDERATION  : ponderer par l\'appartenance `w` — ce qui REPOND A UNE AUTRE QUESTION,')
P('C130:                  le centroide de la PART MOBILE, et non le centre de masse de l\'organe.')
P('C130: ' + '=' * 108)

# ==================================================================================================
# P10 / P11 — LE NOMBRE PUBLIABLE. Le tableau se calcule sur la TRACE + l'instantane CUIT, sans le
# mesh : la correction de tessellation doit donc etre cuite sous la forme A DEUX POINTS.
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: P10 LA VERSION A L\'AIRE DU MODELE A DEUX POINTS (Wa / na / La cuits depuis le mesh)')
BAKE = {}
ok10 = True
for cname in ('chestL', 'chestR'):
    joints = c126.CHAINS[cname]
    idx = [names.index(j) for j in joints]
    wj = np.zeros((len(V), len(idx)))
    for k, ji in enumerate(idx):
        wj[:, k] = (W * (J == ji)).sum(axis=1)
    wsum = wj.sum(axis=1)
    BAKE[cname] = []
    for cut in CUTS:
        sel = wsum > cut if cut == 0.0 else wsum >= cut
        a = AREA[sel]
        Wa = [float((a * wj[sel, k]).sum()) for k in range(len(idx))]
        na = float(a.sum())
        La = np.zeros(3)
        for k, ji in enumerate(idx):
            La += ((a * wj[sel, k])[:, None] * (V[sel] - Pb[ji])).sum(axis=0)
        # meme base d'ancre que `probe_breast_com_mass.py` : R = axes de bind de l'ancre
        Ra = bindR(names.index(c126.ANCHOR))
        La = Ra.T @ La
        lat = (V[sel] - Pb[names.index(c126.ANCHOR)]) @ Ra @ np.array([1.0, 0.0, 0.0])
        w0a = float(lat.max() - lat.min())
        BAKE[cname].append(dict(cut=cut, na=na, Wa=Wa, La=[float(x) for x in La], W0a=w0a))

    c, i = CIDX[cname], ipro
    b = BAKE[cname][0]
    D = np.array([drows[(c, i)][r] for r in range(3)], dtype=float)
    cum = [ldb[(c, i, 0)], ldb[(c, i, 0)] + ldb[(c, i, 1)]]
    sk = (b['Wa'][0] * cum[0] + b['Wa'][1] * cum[1]) / b['na']
    Lv = np.array(b['La'])
    tn = np.array([sum((D[x][y] - (1.0 if x == y else 0.0)) * Lv[x] for x in range(3))
                   for y in range(3)]) / b['na']
    v2p_a = float(np.linalg.norm(sk + tn)) / B0
    exact_a = nz(RESULT[(cname, 0.0)]['row']['PRONE']['aire'])
    fa, fc = v2p_a / exact_a, BRIDGE[cname][0] / BRIDGE[cname][1]
    dpt = abs(fa - fc) * 100.0
    ok10 = ok10 and dpt <= 2.0
    P('C130: P10 %-7s agregation a l\'AIRE 1/%.4f=x%.4f  contre au COMPTE x%.4f  -> ecart %.2f pts'
      '  (falsif. 2)' % (cname, fa, 1.0 / fa, 1.0 / fc, dpt))
    P('C130: P10 %-7s deux points A L\'AIRE = %.4f B0  (exact a l\'aire %.4f · deux points au '
      'compte %.4f)' % (cname, v2p_a, exact_a, BRIDGE[cname][0]))
P('C130: P10 -> %s'
  % ('TIRE — l\'agregation est un facteur TRANSPORTABLE : la forme a deux points reste utilisable '
     'une fois recuite a l\'aire.' if ok10 else '**REFUTEE** — l\'agregation depend de la '
     'ponderation ; le nombre publiable doit etre re-derive avant tout cablage.'))

# ---- P11 : COMBIEN DE VERDICTS BASCULENT ? -----------------------------------------------------
P('C130: ' + '-' * 108)
P('C130: P11 BASCULES DE VERDICT SI `ROOM-SPEC10`/`ROOM-SPEC12` PASSENT AU COMPTE -> A L\'AIRE')


def twopoint(cname, cell, bake):
    """le modele a deux points sur le jeu de coefficients `bake` (compte ou aire)."""
    c = CIDX[cname]
    D = np.array([drows[(c, cell)][r] for r in range(3)], dtype=float)
    cum = [ldb[(c, cell, 0)], ldb[(c, cell, 0)] + ldb[(c, cell, 1)]]
    sk = (bake['W'][0] * cum[0] + bake['W'][1] * cum[1]) / bake['n']
    Lv = np.array(bake['L'], dtype=float)
    tn = np.array([sum((D[x][y] - (1.0 if x == y else 0.0)) * Lv[x] for x in range(3))
                   for y in range(3)]) / bake['n']
    return sk + tn


def verd(v, lo, hi):
    return 'DANS' if lo <= v <= hi else ('SOUS' if v < lo else 'AU-DESSUS')


flips, flip12 = 0, 0
for cname in ('chestL', 'chestR'):
    ax = MASS['chains'][cname]['axes']
    outv, thx = np.array(ax['out'], dtype=float), -np.array(ax['fwd'], dtype=float)
    for kcut, cut in enumerate(CUTS):
        old = MASS['chains'][cname]['defs'][kcut]
        oldb = dict(W=old['W'], n=float(old['n']), L=old['L'])
        nb = BAKE[cname][kcut]
        newb = dict(W=nb['Wa'], n=nb['na'], L=nb['La'])
        for sec, cell, kind, lo, hi in (
                ('§10 thorax', isup, 'th', 0.18, 0.28),
                ('§10 sortant', isup, 'ou', 4.0, 10.0),
                ('§11 norme', ipro, 'nr', 0.20, 0.28),
                ('§12 medial i=2', 2, 'md', 10.0, 18.0),
                ('§12 medial i=4', 4, 'md', 10.0, 18.0)):
            if cell not in cells:
                continue
            vo, vn = twopoint(cname, cell, oldb), twopoint(cname, cell, newb)
            w0o, w0n = float(old['W0']), nb['W0a']
            if kind == 'th':
                a, b_ = float(vo @ thx) / B0, float(vn @ thx) / B0
            elif kind == 'nr':
                a, b_ = float(np.linalg.norm(vo)) / B0, float(np.linalg.norm(vn)) / B0
            elif kind == 'ou':
                a, b_ = float(vo @ outv) / w0o * 100.0, float(vn @ outv) / w0n * 100.0
            else:
                a, b_ = -float(vo @ outv) / w0o * 100.0, -float(vn @ outv) / w0n * 100.0
            va, vb = verd(a, lo, hi), verd(b_, lo, hi)
            if va != vb:
                flips += 1
                if sec.startswith('§12'):
                    flip12 += 1
            P('C130: P11 %-7s %-14s w>%.2f  compte %+8.4f %-9s ->  aire %+8.4f %-9s  %s'
              % (cname, sec, cut, a, va, b_, vb, 'BASCULE' if va != vb else ''))
P('C130: P11 total des bascules : %d (predit : au plus 2) · dont sur la clause porteuse de §12 : %d'
  ' (predit : 0)' % (flips, flip12))
P('C130: P11 -> %s' % ('TIRE' if flips <= 2 and flip12 == 0 else
                       '**REFUTEE** — deplacement de verdict, pas raffinement : on remonte au lieu '
                       'de cabler.'))
P('C130: ' + '=' * 108)

# ==================================================================================================
# §10 SUPINE SUR L'ESTIMATEUR ARBITRE — declare parce que la PORTEE DERIVEE l'annonce, pas
# decouvert en chemin. La clause est « COM toward thorax: 18-28% B0 » (l.168).
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: PORTEE DERIVEE — §10 SUPINE i=%d, clause « COM toward thorax: 18-28%% B0 » (l.168),' % isup)
P('C130:   sur l\'axe THORAX, estimateur EXACT par sommet, quatre ponderations :')
for cname in ('chestL', 'chestR'):
    thx = -np.array(MASS['chains'][cname]['axes']['fwd'], dtype=float)
    for cut in CUTS:
        r = RESULT[(cname, cut)]['row'].get('SUPINE')
        if r is None:
            continue
        vs = []
        for k in ('compte', 'aire'):
            x = float(r[k] @ thx)
            vs.append('%s %+.4f %s' % (k, x, verd(abs(x), 0.18, 0.28)))
        P('C130:   %-8s w>%.2f  %s' % (cname, cut, '  ·  '.join(vs)))
P('C130: ' + '=' * 108)

# ==================================================================================================
# P12 — CONTRE-CONTROLE INDEPENDANT DE LA MASSE DE SOMMET (DIRECTIVES 2026-08-21 18:40).
# Seconde derivation : aire de VORONOI MIXTE (Meyer et al.) — meme maillage, REGLE DE PARTAGE
# DIFFERENTE (cotangentes, avec bascule moitie/quart sur triangle obtus).
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: P12 SECONDE DERIVATION DE LA MASSE DE SOMMET — AIRE DE VORONOI MIXTE')
VOR = np.zeros(len(V))
for t in Ftri:
    p0, p1, p2 = V[t[0]], V[t[1]], V[t[2]]
    e = [p2 - p1, p0 - p2, p1 - p0]                       # cote OPPOSE a chaque sommet
    ar = 0.5 * float(np.linalg.norm(np.cross(p1 - p0, p2 - p0)))
    if ar <= 0.0:
        continue
    # cotangente a chaque sommet, via les deux cotes qui en partent
    cot = []
    for k in range(3):
        u, v_ = -e[(k + 1) % 3], e[(k + 2) % 3]
        cot.append(float(np.dot(u, v_)) / (2.0 * ar))
    if min(cot) < 0.0:                                    # triangle OBTUS
        k = int(np.argmin(cot))                           # le sommet obtus
        for j in range(3):
            VOR[t[j]] += ar / 2.0 if j == k else ar / 4.0
    else:
        for j in range(3):
            VOR[t[j]] += (float(np.dot(e[(j + 1) % 3], e[(j + 1) % 3])) * cot[(j + 1) % 3]
                          + float(np.dot(e[(j + 2) % 3], e[(j + 2) % 3])) * cot[(j + 2) % 3]) / 8.0
P('C130: P12 aire barycentrique totale %.1f  ·  aire de Voronoi totale %.1f  (ecart global %.3f %%)'
  % (AREA.sum(), VOR.sum(), abs(VOR.sum() / AREA.sum() - 1.0) * 100.0))
ok12 = True
for cname in ('chestL', 'chestR'):
    joints = c126.CHAINS[cname]
    idxc = [names.index(j) for j in joints]
    wsum = np.zeros(len(V))
    for ji in idxc:
        wsum += (W * (J == ji)).sum(axis=1)
    for cut in CUTS:
        sel = wsum > cut if cut == 0.0 else wsum >= cut
        Js, Ws, Vs = J[sel], W[sel], V[sel]

        def sk2(ii):
            acc = np.zeros((int(sel.sum()), 3))
            for k in range(Ws.shape[1]):
                for nmj in slot:
                    mk = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                    if not mk.any():
                        continue
                    M = mats[(ii, slot[nmj])]
                    q = (Vs[mk] - Pb[names.index(nmj)]) @ RB[nmj]
                    acc[mk] += Ws[mk, k][:, None] * (q @ M[:3, :3] + M[3, :3])
            Ma = mats[(ii, slot[c126.ANCHOR])]
            return (acc - Ma[3, :3]) @ Ma[:3, :3].T
        Dv = sk2(ipro) - sk2(0)
        av, vv = AREA[sel], VOR[sel]
        b_ = nz((av[:, None] * Dv).sum(0) / av.sum()) / B0
        v_ = nz((vv[:, None] * Dv).sum(0) / vv.sum()) / B0
        d = abs(v_ / b_ - 1.0) * 100.0
        same = verd(b_, 0.20, 0.28) == verd(v_, 0.20, 0.28)
        ok12 = ok12 and d <= 5.0 and same
        P('C130: P12 %-7s w>%.2f  barycentrique %.4f %-9s  ·  Voronoi %.4f %-9s  -> ecart %.2f %% '
          '%s' % (cname, cut, b_, verd(b_, 0.20, 0.28), v_, verd(v_, 0.20, 0.28), d,
                  '' if same else '  VERDICT DIFFERENT'))
P('C130: P12 -> %s'
  % ('TIRE — la masse de sommet est DETERMINEE par le maillage : deux regles de partage '
     'independantes rendent le meme deplacement ET le meme verdict.' if ok12
     else '**REFUTEE** — l\'estimateur ARBITRE n\'est pas unique ; l\'arbitration est publiee '
          'comme DEPENDANTE DU PROXY DE MASSE.'))
P('C130: ' + '=' * 108)

# ==================================================================================================
# P13 — LA CORRECTION EST-ELLE UN SCALAIRE INDEPENDANT DE LA POSE ?
# `comw = W_l/N` est CUIT dans `physics_chains.txt` et lu par le moteur ; `d_COM` y est LINEAIRE en
# `comw`. Si le rapport aire/compte est le MEME sur les deux maillons, la correction est un scalaire
# exact a toute pose — et l'effet sur §14 a §22 se chiffre sans une course de plus.
# ==================================================================================================
P('C130: ' + '=' * 108)
P('C130: P13 `comw` PAR MAILLON — COMPTE contre AIRE (la cle est CUITE dans le fichier livre)')
ok13 = True
for cname in ('chestL', 'chestR'):
    d = MASS['chains'][cname]['defs'][0]
    b = BAKE[cname][0]
    cw_c = [d['W'][k] / float(d['n']) for k in range(2)]
    cw_a = [b['Wa'][k] / b['na'] for k in range(2)]
    rat = [cw_a[k] / cw_c[k] for k in range(2)]
    sp = abs(rat[0] / rat[1] - 1.0) * 100.0
    ok13 = ok13 and sp <= 5.0
    P('C130: P13 %-7s compte %.4f,%.4f  ->  aire %.4f,%.4f   rapports x%.4f / x%.4f   ecart entre '
      'maillons %.2f %% (falsif. 5)' % (cname, cw_c[0], cw_c[1], cw_a[0], cw_a[1],
                                        rat[0], rat[1], sp))
P('C130: P13 -> %s'
  % ('TIRE — la correction est un SCALAIRE : toute cellule de COM normalisee par `comw` se corrige '
     'du meme facteur, a toute pose et tout regime.' if ok13
     else '**REFUTEE** — la correction depend du melange des maillons, donc de la pose ; son effet '
          'sur §14-§22 reste NON ETABLI et ne s\'extrapole pas depuis le prone.'))
if ok13:
    P('C130: P13 EFFET CHIFFRE SUR LES CELLULES A BANDE LES PLUS SERREES (valeurs du tableau LIVRE) :')
    for cname, rho in (('chestL', None), ('chestR', None)):
        d = MASS['chains'][cname]['defs'][0]
        b = BAKE[cname][0]
        r = (b['Wa'][0] / b['na']) / (d['W'][0] / float(d['n']))
        CELLS = {'chestL': [('ROOM-REGIME r=1 §14', 0.1571, 0.15, 0.25),
                            ('ROOM-REGB-COM r=1 §14', 0.2499, 0.15, 0.25),
                            ('ROOM-REGB-COM r=8 §17', 0.2689, 0.18, 0.27),
                            ('ROOM-COM §22 pic', 0.3398, 0.0, 0.35),
                            ('ROOM-COM §22 max', 0.4630, 0.0, 0.40)],
                 'chestR': [('ROOM-REGIME r=1 §14', 0.2434, 0.15, 0.25),
                            ('ROOM-REGB-COM r=4 §14', 0.2350, 0.25, 0.32),
                            ('ROOM-REGIME r=13 §20', 0.2499, 0.15, 0.22),
                            ('ROOM-COM §22 pic', 0.3259, 0.0, 0.35),
                            ('ROOM-COM §22 max', 0.4536, 0.0, 0.40)]}[cname]
        for lab, v, lo, hi in CELLS:
            n_ = v * r
            P('C130: P13   %-7s %-24s %.4f %-9s ->  x%.4f = %.4f %-9s %s'
              % (cname, lab, v, verd(v, lo, hi), r, n_, verd(n_, lo, hi),
                 'BASCULE' if verd(v, lo, hi) != verd(n_, lo, hi) else ''))
P('C130: ' + '=' * 108)
