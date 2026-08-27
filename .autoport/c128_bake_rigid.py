#!/usr/bin/env python3
"""c128_bake_rigid.py — CUIT LES CONSTANTES DE L'ETAGE RIGIDE DE §11 ET LES ECRIT DANS
`recharged_assets/physics_mesh.txt` SOUS L'ENREGISTREMENT `rg`.

CE QUE CA CUIT, ET POURQUOI C'EST UNE CONSTANTE DE MESH ET PAS UN REGLAGE.
Le skinning lineaire est LINEAIRE en les matrices d'os, donc le vecteur racine->apex — la
grandeur que §11 nomme — est EXACTEMENT une somme par OS :

    d = c_dist - c_prox = Somme_b ( ds_b . R_b + dm_b t_b )

    ds_b = s_b^dist / T_dist - s_b^prox / T_prox      s_b = Somme_v w_v W_vb q_vb
    dm_b = m_b^dist / T_dist - m_b^prox / T_prox      m_b = Somme_v w_v W_vb
    T_pop = Somme_{b dans keep} m_b^pop

`ds_b` et `dm_b` ne dependent que du MESH LIVRE et de la pose de BIND. Aucun verdict, aucune
mesure de course n'entre dans leur calcul. C'est la meme classe que `*phys-lcx/lcy/lcz*` (centre
de chair) et `*phys-apx/apy/apz*` (apex), deja cuits et deja lus par le moteur.

DEUX PROPRIETES QU'ON EXPLOITE, ET ELLES SONT EXACTES, PAS DES APPROXIMATIONS :
  1. **Somme_b dm_b = 0** (chaque population est renormalisee par son propre total). Donc le terme
     de translation est invariant par translation : on peut remplacer `t_b` par `t_b - p_ancre`
     sans rien changer au resultat. On le fait, pour deux raisons — la contribution de l'ANCRE
     s'annule (un flottant de moins), et les magnitudes tombent de ~1e5 unites monde a ~1e3
     unites d'offset, ce qui rend le transport en MILLI-UNITES (`phys_mi`, 1e-3) sans effet.
  2. `dm` est malgre tout multiplie par un offset de ~1e3 unites : on le cuit donc **x1000** et le
     moteur le remultiplie par 0,001. Sans ce facteur l'erreur de quantification atteindrait
     0,4 point sur le rapport ; avec, elle est de 0,0004 point.

PAS DE DENOMINATEUR CUIT — L'ESTIMATEUR EST AUTO-NORMALISANT, ET C'EST UNE CORRECTION DU PREMIER
JET DE CE SCRIPT. Cuire `L0` a la pose de BIND donne 706,4 / 717,4 u la ou la cellule DEBOUT de la
course en mesure 597,6 / 645,3 : **la pose debout d'auteur n'est PAS la pose de bind**, ecart de
10,1 a 15,4 %. Le rapport devenait faux d'autant, alors que la FORME de l'estimateur etait juste a
0,06 / 0,40 point. Le moteur calcule donc les DEUX au meme instant :

    d_defl = ds_a . R_ancre + Somme_l [ ds_l . (R_auteur,l . rot_l) + dm_l (p_solvee,l - ancre) ]
    d_auth = ds_a . R_ancre + Somme_l [ ds_l .  R_auteur,l          + dm_l (p_auteur,l - ancre) ]
    rigide = |d_defl| / |d_auth|

`d_auth` est la MEME chaine sans la deflexion physique, a la MEME orientation : le rapport est donc
« ce que la reconfiguration ajoute », exactement la definition du nuage `RIGID`. Ca vaut 1,000 par
construction quand la physique ne deflechit rien, sans aucune constante de reference.
RESERVE DECLAREE : cette forme suppose que |d_auth| ne depend pas de l'orientation — vrai si
l'animation ne pilote pas les joints de poitrine (SPEC §5). Ce n'est PAS verifiable hors ligne (la
trace ne porte que les matrices LIVREES) : le moteur PUBLIE donc |d_auth| a cote du rapport, et la
constance se lit sur la course. Une garde, pas une hypothese muette.

FORMAT DE L'ENREGISTREMENT, une ligne par chaine, dans `physics_mesh.txt` :

    rg <chaine> <sax> <say> <saz> <s0x> <s0y> <s0z> <m0k> <s1x> <s1y> <s1z> <m1k>

  sa*           = ds de l'ANCRE, dans le repere BIND-LOCAL de l'ancre, unites de jeu
  s0*/s1*       = ds des maillons 0 et 1, dans leur propre repere BIND-LOCAL, unites de jeu
  m0k/m1k       = dm des maillons 0 et 1, x1000 (sans dimension)

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : des CONSTANTES GEOMETRIQUES (un vecteur d'offset pondere par os, une part de masse,
            une longueur), pas une mesure de course.
  REPERE  : chaque `ds_b` vit dans le repere BIND-LOCAL de SON os — c'est ce qui permet au moteur
            de le faire tourner avec cet os. `L0` est une longueur, invariante.
  LIGNE DE BASE : la pose de BIND, ou le rapport vaut 1,000 par construction.
  CONTROLE : ce script REJOUE le NUMERATEUR de l'estimateur sur la trace livree, normalise par la
            cellule DEBOUT i=0 — la seule normalisation que la trace permette — et exige de
            retrouver le nuage `RIGID` de `c126_rotation_vs_stretch.run()` a moins de 5 points sur
            la cellule PRONE et a moins de 1 % de 1,000 sur la cellule DEBOUT i=9. Il n'ECRIT RIEN
            si ca echoue. Le denominateur reel du moteur (|d_auth|) se verifie A LA COURSE.

POPULATION CUITE : la frontiere `w>0.00` (tout sommet que la chaine touche). L'autre frontiere
publiee (`w>=0.25`) donne un etage rigide different de ~3 points ; l'ecart est DECLARE, pas
corrige — un seul estimateur ne peut pas servir deux definitions de population.
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
MESHFILE = os.path.join(REPO, 'recharged_assets/physics_mesh.txt')
CUT, CUTLBL = 0.0, 'w>0.00'
WRITE = '--write' in sys.argv
LOG = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'

txt = open(os.path.join(REPO, LOG), 'r', errors='replace').read()
isup, ipro, _G = c124._roles(txt)
jn, mats, nmiss = c124._read_matrices(txt)
if not mats or nmiss:
    raise SystemExit('c128-bake: SUSPENDU — trace incomplete.')
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
P = print
P('C128BAKE: SUPINE i=%d · PRONE i=%d · population cuite = %s' % (isup, ipro, CUTLBL))

lines = {}
ok_all = True
for cname, joints in c126.CHAINS.items():
    jp, jd = joints
    keep = [c126.ANCHOR, jp, jd]
    idx = [names.index(j) for j in joints]
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)
    AX = {a: np.asarray(mass['chains'][cname]['axes'][a], dtype=float)
          for a in ('out', 'up', 'fwd')}
    sel = wsum > CUT
    wv = wsum[sel]
    xb = (V[sel] - Pb[ai]) @ Ranc @ AX['fwd']
    qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
    pops = {'prox': xb <= qlo, 'dist': xb >= qhi}
    Js, Ws, Vs = J[sel], W[sel], V[sel]

    agg = {}
    for pn, pm in pops.items():
        wsub, tot = wv[pm], float(wv[pm].sum())
        d = {}
        for nmj in slot:
            bi = names.index(nmj)
            s, m = np.zeros(3), 0.0
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

    T = {pn: sum(agg[pn][b][1] for b in keep if b in agg[pn]) for pn in agg}
    ds, dm = {}, {}
    for b in keep:
        sd, md = agg['dist'].get(b, (np.zeros(3), 0.0))
        sp, mp = agg['prox'].get(b, (np.zeros(3), 0.0))
        ds[b] = sd / T['dist'] - sp / T['prox']
        dm[b] = md / T['dist'] - mp / T['prox']
    P('C128BAKE: %-7s  Somme(dm) = %+.3e  (exigee nulle : le terme de translation est alors '
      'invariant par translation)' % (cname, sum(dm.values())))

    # ---- reference de bind, PUBLIEE pour montrer l'ecart a la pose debout d'auteur -------------
    dbind = np.zeros(3)
    for b in keep:
        dbind += ds[b] @ RB[b] + dm[b] * (Pb[names.index(b)] - Pb[ai])
    Lbind = float(np.linalg.norm(dbind))

    # ---- controle : le meme d, calcule comme le moteur le calculera, sur les cellules ----------
    def dnow(i):
        v = ds[c126.ANCHOR] @ MM[(i, slot[c126.ANCHOR])][:3, :3]
        anc = MM[(i, slot[c126.ANCHOR])][3, :3]
        for l, b in enumerate((jp, jd)):
            Mb = MM[(i, slot[b])]
            v = v + ds[b] @ Mb[:3, :3] + dm[b] * (Mb[3, :3] - anc)
        return float(np.linalg.norm(v))

    ref = res[(cname, CUTLBL, 'RIGID')]
    L0 = dnow(0)
    P('C128BAKE: %-7s  |d| pose de BIND = %10.3f u   |d| cellule DEBOUT = %10.3f u   ecart %.3f %% '
      '<- POURQUOI AUCUN DENOMINATEUR N\'EST CUIT'
      % (cname, Lbind, L0, abs(Lbind / L0 - 1.0) * 100.0))
    for cell, tag in ((0, 'DEBOUT(base)'), (ipro, 'PRONE'), (isup, 'SUPINE'), (9, 'DEBOUT(2e)')):
        got, exp = dnow(cell) / L0, ref['Lpp'][cell] / ref['Lpp'][0]
        ec = abs(got - exp) * 100.0
        bad = (tag == 'PRONE' and ec >= 5.0) or (tag == 'DEBOUT(2e)' and abs(got - 1.0) * 100 > 1.0)
        ok_all = ok_all and not bad
        P('C128BAKE: %-7s  %-12s  estime %.4f   RIGID mesure %.4f   ecart %6.3f pts %s'
          % (cname, tag, got, exp, ec, '<-- ECHEC' if bad else ''))

    v = list(ds[c126.ANCHOR])
    for b in (jp, jd):
        v += list(ds[b]) + [dm[b] * 1000.0]
    lines[cname] = 'rg %s %s' % (cname, ' '.join('%.4f' % x for x in v))

P('C128BAKE: ' + '-' * 100)
for cname, ln in lines.items():
    P('C128BAKE: %s' % ln)
if not ok_all:
    P('C128BAKE: CONTROLE ECHOUE — RIEN N\'EST ECRIT.')
    sys.exit(1)
P('C128BAKE: controle TIRE sur les 2 chaines et les 4 cellules.')

if not WRITE:
    P('C128BAKE: mode lecture seule (passer --write pour ecrire dans physics_mesh.txt).')
    sys.exit(0)

src = open(MESHFILE, 'r').read()
keptl = [l for l in src.split('\n') if not l.startswith('rg ')]
hdr = ('# rg <chain> <sax> <say> <saz> <s0x> <s0y> <s0z> <m0k> <s1x> <s1y> <s1z> <m1k>'
       '   L ETAGE RIGIDE de SPEC 11 (cycle 128) : le vecteur racine->apex est une somme PAR OS,'
       ' ds/dm sont des constantes du MESH LIVRE. dm est cuit x1000. Voir .autoport/c128_bake_rigid.py.')
if hdr not in keptl:
    for i, l in enumerate(keptl):
        if l.startswith('# ax '):
            keptl.insert(i + 1, hdr)
            break
    else:
        keptl.insert(1, hdr)
out = '\n'.join(keptl).rstrip('\n') + '\n' + '\n'.join(lines.values()) + '\n'
open(MESHFILE, 'w').write(out)
P('C128BAKE: %d lignes `rg` ecrites dans recharged_assets/physics_mesh.txt' % len(lines))
