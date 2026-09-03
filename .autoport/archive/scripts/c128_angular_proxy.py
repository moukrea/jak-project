#!/usr/bin/env python3
"""c128_angular_proxy.py — UN ESTIMATEUR D'ETAGE RIGIDE QUE LE MOTEUR PEUT PAYER

POURQUOI. Le cycle 127 etablit (a) que l'etage rigide vaut 1,0977-1,1415 au prone et que le tenseur
recoit malgre tout la cible TOTALE — double compte ; (b) qu'un estimateur EXACT existe (agregat par
os, P8b : 0,013-0,403 pt) mais coute ~12 flottants cuits et ~26 lignes de moteur, alors que le
plafond `CLEAN` GELE ne laisse que 6 lignes. Ce script cherche le candidat LE MOINS COUTEUX EN
LIGNES DE MOTEUR qui passe le meme falsificateur.

LES CANDIDATS SONT PRE-ENREGISTRES dans `.autoport/c128-predictions.txt`, ecrits avant tout calcul,
avec la regle de selection. Les quatre sont calcules et publies quel que soit le vainqueur.

  C0   rigid = 1                                    0 flottant   CONTROLE NEGATIF, doit ECHOUER
  C1   rigid = 1 + k (1 - cos theta)                1 flottant   k ANALYTIQUE, jamais ajuste
  C2   agregat a 2 os {ancre, distal}               8 flottants
  C3   agregat a 3 os {ancre, proximal, distal}    12 flottants  (deja valide c127c)

DERIVATION DE `k`, ECRITE AVANT LA MESURE ET SANS AUCUN AJUSTEMENT SUR `RIGID`.
Dans le repere de l'ANCRE, le vecteur racine->apex se scinde en la part qui NE bouge pas avec le
maillon distal et celle qui bouge :   d(theta) = a + R(n,theta) b.
    |d|^2 = |a|^2 + |b|^2 + 2 a . R(n,theta) b
En moyennant sur l'axe n uniformement — SEULE hypothese, et elle est declaree ici :
    <R(n,theta) b> = b [ cos + (1-cos)/3 ]   car <(n.b)n> = b/3 et <n x b> = 0
    => |d(theta)|^2 = |d(0)|^2 - (4/3)(a.b)(1-cos theta)
    => rigid = |d(theta)|/|d(0)| ~= 1 - (2/3)(a.b)(1-cos theta)/|d(0)|^2
    => k = -(2/3) (a . b) / |d(0)|^2      <- constante de BIND pure

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : rapport de LONGUEUR sans dimension (racine->apex) ; ecart en POINTS DE POURCENTAGE.
  REPERE  : les angles se lisent dans le repere de l'ANCRE, donc la rotation du buste s'annule ;
            un rapport de longueurs est un invariant euclidien.
  LIGNE DE BASE : cellule i=0 (debout d'auteur). LECTURE HORS DEFAUT : 2e cellule DEBOUT i=9.
  REFERENCE : le nuage `RIGID` de `c126_rotation_vs_stretch.run()`, sommet par sommet.

CONVENTION DE SKINNING : vecteurs LIGNE. monde = q . R + t, avec R = M[:3,:3] et t = M[3,:3].
C'est la convention de `c127c_bone_aggregate.py`, dont ce script reprend l'agregation telle quelle.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(os.path.join(REPO, LOG) if not os.path.isabs(LOG) else LOG,
           'r', errors='replace').read()

isup, ipro, _G = c124._roles(txt)
jn, mats, nmiss = c124._read_matrices(txt)
if not mats or nmiss:
    raise SystemExit('c128: SUSPENDU — trace incomplete.')
slot = {v: k for k, v in jn.items()}

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


Ranc = bindR(ai)
RB = {n: bindR(names.index(n)) for n in slot}
mass = json.load(open(os.path.join(REPO, c126.MASSJSON)))

# ---- LES MATRICES `RIGID` : rotation pure sur les joints de chaine (identique a c127c) ---------
MM = {}
for (i, sl), M in mats.items():
    nm = jn.get(sl)
    if nm not in c126.CHAINJOINTS:
        MM[(i, sl)] = M
        continue
    S, Rr = c126.polar_SR(M[:3, :3])
    M2 = M.copy()
    M2[:3, :3] = Rr
    MM[(i, sl)] = M2

res, cells = c126.run(txt, inject_fwd=1.50)
CELLS = [(0, 'DEBOUT(base)'), (ipro, 'PRONE'), (isup, 'SUPINE'), (9, 'DEBOUT(2e)')]
P = print
P('C128: SUPINE i=%d · PRONE i=%d · reference = nuage RIGID sommet par sommet' % (isup, ipro))
P('C128: ' + '=' * 112)


def rotangle(R):
    """angle de la rotation R, en degres."""
    c = (float(np.trace(R)) - 1.0) / 2.0
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


rows = []
worst = {'C0': 0.0, 'C1': 0.0, 'C2': 0.0, 'C3': 0.0}
worst_pro = {'C0': 0.0, 'C1': 0.0, 'C2': 0.0, 'C3': 0.0}
worst_i9 = {'C0': 0.0, 'C1': 0.0, 'C2': 0.0, 'C3': 0.0}
ref_i9 = 0.0
kvals = {}
thetas = {}
corr_pro = {}

for cname, joints in c126.CHAINS.items():
    jp, jd = joints
    idx = [names.index(j) for j in joints]
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)
    AX = {a: np.asarray(mass['chains'][cname]['axes'][a], dtype=float)
          for a in ('out', 'up', 'fwd')}
    for cut, lbl in ((0.0, 'w>0.00'), (0.25, 'w>=0.25')):
        sel = wsum > cut if cut == 0.0 else wsum >= cut
        wv = wsum[sel]
        xb = (V[sel] - Pb[ai]) @ Ranc @ AX['fwd']
        qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
        pops = {'prox': xb <= qlo, 'dist': xb >= qhi}
        Js, Ws, Vs = J[sel], W[sel], V[sel]

        # ---- AGGREGATION PAR OS : s_b (vecteur) et m_b (scalaire), par population -------------
        agg = {}
        for pn, pm in pops.items():
            wsub, tot = wv[pm], float(wv[pm].sum())
            d = {}
            for nmj in slot:
                bi = names.index(nmj)
                s = np.zeros(3)
                m = 0.0
                for k in range(Ws.shape[1]):
                    mk = (Js[pm][:, k] == bi) & (Ws[pm][:, k] > 0)
                    if not mk.any():
                        continue
                    ww = wsub[mk] * Ws[pm][mk, k]
                    q = (Vs[pm][mk] - Pb[bi]) @ RB[nmj]
                    s += (ww[:, None] * q).sum(0)
                    m += float(ww.sum())
                if m > 0.0 or np.any(s):
                    d[nmj] = (s / tot, m / tot)
            agg[pn] = d

        SETS = {'C3': {c126.ANCHOR, jp, jd}, 'C2': {c126.ANCHOR, jd}}

        def centro(pn, i, keep):
            s3, tot = np.zeros(3), 0.0
            for nmj, (s, m) in agg[pn].items():
                if nmj not in keep:
                    continue
                M = MM[(i, slot[nmj])]
                s3 += s @ M[:3, :3] + m * M[3, :3]
                tot += m
            return s3 / tot if tot > 0 else s3

        def contrib(pn, i, nmj):
            """contribution du SEUL os nmj au centroide (numerateur), sans renormalisation."""
            s, m = agg[pn].get(nmj, (np.zeros(3), 0.0))
            M = MM[(i, slot[nmj])]
            return s @ M[:3, :3] + m * M[3, :3]

        # ---- k ANALYTIQUE : scission de d(0) en part fixe `a` et part portee par le distal `b`,
        #      dans le repere de l'ANCRE. AUCUNE valeur mesuree de RIGID n'entre ici.
        keep3 = SETS['C3']
        tot_d = sum(agg['dist'][b][1] for b in keep3 if b in agg['dist'])
        tot_p = sum(agg['prox'][b][1] for b in keep3 if b in agg['prox'])
        Manc0 = MM[(0, slot[c126.ANCHOR])]
        Ra0 = Manc0[:3, :3]
        d0v = centro('dist', 0, keep3) - centro('prox', 0, keep3)
        bvec = (contrib('dist', 0, jd) / tot_d) - (contrib('prox', 0, jd) / tot_p if jd in agg['prox'] else 0.0)
        # exprime dans le repere de l'ancre (vecteurs LIGNE : x_ancre = x_monde . Ra0^T)
        d0a = d0v @ Ra0.T
        ba = bvec @ Ra0.T
        aa = d0a - ba
        L0sq = float(d0a @ d0a)
        k = -(2.0 / 3.0) * float(aa @ ba) / L0sq
        kvals[(cname, lbl)] = k

        ref = res[(cname, lbl, 'RIGID')]
        L0 = {sn: float(np.linalg.norm(centro('dist', 0, SETS[sn]) - centro('prox', 0, SETS[sn])))
              for sn in SETS}

        for cell, tag in CELLS:
            exp = ref['Lpp'][cell] / ref['Lpp'][0]
            # theta : rotation du bone DISTAL dans le repere de l'ANCRE, relative a la cellule 0
            Rd_i, Ra_i = MM[(cell, slot[jd])][:3, :3], MM[(cell, slot[c126.ANCHOR])][:3, :3]
            Rd_0, Ra_0 = MM[(0, slot[jd])][:3, :3], MM[(0, slot[c126.ANCHOR])][:3, :3]
            Rt_i = Rd_i @ Ra_i.T
            Rt_0 = Rd_0 @ Ra_0.T
            th_bone = rotangle(Rt_i @ Rt_0.T)
            # theta : angle des DIRECTIONS de position depuis le pivot d'ancre (ce que le moteur
            # calcule deja a :3854-3860), lu dans le repere de l'ancre
            def dirac(i):
                p = MM[(i, slot[jd])][3, :3] - MM[(i, slot[c126.ANCHOR])][3, :3]
                p = p @ MM[(i, slot[c126.ANCHOR])][:3, :3].T
                return p / max(np.linalg.norm(p), 1e-9)
            th_pos = math.degrees(math.acos(max(-1.0, min(1.0, float(dirac(cell) @ dirac(0))))))
            got = {'C0': 1.0,
                   'C1': 1.0 + k * (1.0 - math.cos(math.radians(th_bone)))}
            for sn in SETS:
                got[sn] = float(np.linalg.norm(centro('dist', cell, SETS[sn])
                                               - centro('prox', cell, SETS[sn]))) / L0[sn]
            ec = {c: abs(got[c] - exp) * 100.0 for c in got}
            for c in ec:
                worst[c] = max(worst[c], ec[c])
                if tag == 'PRONE':
                    worst_pro[c] = max(worst_pro[c], ec[c])
                if tag == 'DEBOUT(2e)':
                    worst_i9[c] = max(worst_i9[c], abs(got[c] - 1.0) * 100.0)
            if tag == 'DEBOUT(2e)':
                ref_i9 = max(ref_i9, abs(exp - 1.0) * 100.0)
            if tag == 'PRONE':
                thetas[(cname, lbl)] = (th_bone, th_pos)
                corr_pro[(cname, lbl)] = k * (1.0 - math.cos(math.radians(th_bone)))
            rows.append((cname, lbl, tag, exp, got, ec, th_bone, th_pos))

hdr = 'C128: %-7s %-8s %-12s  RIGID    C0       C1       C2       C3    |  ecarts (pts)  th_os  th_pos' % ('chaine', 'coupe', 'cellule')
P(hdr)
for (cname, lbl, tag, exp, got, ec, thb, thp) in rows:
    P('C128: %-7s %-8s %-12s %.4f  %.4f  %.4f  %.4f  %.4f  | %5.2f %5.2f %5.2f %5.2f  %5.1f  %5.1f'
      % (cname, lbl, tag, exp, got['C0'], got['C1'], got['C2'], got['C3'],
         ec['C0'], ec['C1'], ec['C2'], ec['C3'], thb, thp))

P('C128: ' + '-' * 112)
P('C128: k ANALYTIQUE (constante de bind, aucun ajustement) : ' +
  ' · '.join('%s/%s %.4f' % (c, l, v) for (c, l), v in kvals.items()))
kmin, kmax = min(kvals.values()), max(kvals.values())
P('C128: P4  rapport max/min de k = %.3f  (falsificateur >= 2,0) -> %s'
  % (kmax / kmin if kmin > 0 else float('inf'),
     'TENUE' if kmin > 0 and kmax / kmin < 2.0 else 'REFUTEE'))
cmin = min(corr_pro.values())
P('C128:     correction k(1-cos th) au PRONE, min sur les 4 cellules = %.4f  (falsificateur < 0,05) -> %s'
  % (cmin, 'TENUE' if cmin > 0.05 else 'REFUTEE'))
thmin = min(min(t) for t in thetas.values())
P('C128: P3  theta minimal au PRONE = %.1f deg  (falsificateur < 10 deg) -> %s'
  % (thmin, 'TENUE' if thmin >= 10.0 else 'VACUEUSE'))
P('C128: P2  controle HORS DEFAUT i=9 : ecart a 1,000 du RIGID mesure = %.3f %%  (seuil 1 %%) -> %s'
  % (ref_i9, 'TIRE' if ref_i9 <= 1.0 else 'INSTRUMENT FAUX, RIEN N\'EST PUBLIE'))
for c in ('C0', 'C1', 'C2', 'C3'):
    P('C128:     i=9 %s : ecart a 1,000 = %.3f %%' % (c, worst_i9[c]))
P('C128: ' + '-' * 112)
for c in ('C0', 'C1', 'C2', 'C3'):
    P('C128: P1  %s — ecart max sur les 4 cellules PRONE : %6.3f pts  (falsificateur 5) -> %s'
      % (c, worst_pro[c], 'PASSE' if worst_pro[c] < 5.0 else 'ECHOUE'))
P('C128:     (rappel : C0 DOIT echouer — c\'est le controle negatif du double compte)')
winner = None
for c in ('C1', 'C2', 'C3'):
    if worst_pro[c] < 5.0 and worst_i9[c] <= 1.0:
        winner = c
        break
P('C128: REGLE DE SELECTION (pre-enregistree) — le moins couteux en LIGNES qui passe (a) 5 pts au '
  'PRONE et (b) 1 %% a i=9 : %s' % (winner if winner else 'AUCUN'))
P('C128: P5  couverture SUPINE (declaree, pas exigee) : ' +
  ' · '.join('%s %.2f pts' % (c, max(e[c] for (_, _, t, _, _, e, _, _) in rows if t == 'SUPINE'))
             for c in ('C0', 'C1', 'C2', 'C3')))
P('C128: ' + '=' * 112)
