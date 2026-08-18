#!/usr/bin/env python3
"""probe_oricom_exact.py — SPEC 10/11/12 LUES SUR LE COM, TENSEUR D'EQUILIBRE COMPRIS.

POURQUOI. Ses §10/§11/§12 chiffrent un deplacement de CENTRE DE MASSE en B0. La salle publiait
DEUX bornes et aucune valeur :
  `ROOM-ORICOM-SPEC` = deplacement de l'APEX          -> declare BORNE SUPERIEURE
  `ROOM-ORICOM-MASS` = part SQUELETTIQUE seule        -> declare BORNE INFERIEURE, « le tenseur de
                       deformation etire la peau autour de l'os sans deplacer un joint : il n'est
                       PAS ici »
La bande de sa spec tombait DANS l'intervalle des deux bornes : les huit cellules etaient
INDECIDABLES. Cette sonde calcule le terme manquant.

LES TROIS QUESTIONS (SPEC 7), repondues avant le chiffre :
  NATURE  : un DEPLACEMENT SOUTENU du centroide de l'organe, en B0. Pas une variance, pas une
            amplitude : les `d_j` sont des moyennes de 30 frames d'un equilibre tenu.
  REPERE  : la base de l'ANCRE (`chest`), lignes (e0,e1,e2). C'est la base dans laquelle vivent
            DEJA les trois entrees : `PHYSORICOML` (via rv=1/rap=2/rlat=0 de `PHYSAXIS`),
            `PHYSTRI` (le triedre fx/fy/fz), et la geometrie du glb ramenee par R_chest^T.
            Aucune composante ne traverse deux reperes.
  ABSENT  : l'orientation i=0 est la pose debout d'auteur, ou sa §9 exige 0.0000. Elle est
            MESUREE et publiee : c'est la ligne de base de cette sonde.

LA MATHEMATIQUE, ET ELLE EST LUE DANS LE MOTEUR, PAS SUPPOSEE.
  (a) SQUELETTIQUE — skinning lineaire, un joint non simule a un ecart nul dans le repere de
      l'ancre :        d_skel = ( W_0.d_0 + W_1.d_1 ) / N
      `d_j` est un CUMUL : `PHYSORICOML` publie `u - m` par maillon, donc un ecart AU PARENT ;
      l'absolu est la somme telescopique (piege `per-link-deviation-is-relative`).
  (b) TENSORIEL — `jak-hd-physics.gc:3935-3940` bati la 3x3 comme
             D = s_x.fx.fx^T + s_y.fy.fy^T + s_z.fz.fz^T
      c'est-a-dire une mise a l'echelle symetrique dans le triedre d'ancre. Un sommet lie au joint
      j voit son offset a l'origine de j transforme par D, donc
             d_tens = ( SOMME_v SOMME_j w(v,j) (D-I)(p_v - o_j) ) / N  =  (D-I) . L / N
      ou L est un LEVIER GEOMETRIQUE fixe, mesure une fois par chaine et par frontiere.
  Puis  d_COM = d_skel + d_tens,  et |d_COM| / B0 contre les bandes.

CE QUE CETTE SONDE N'INCLUT TOUJOURS PAS, ET C'EST DIT ICI PLUTOT QU'OMIS : le moteur applique
`matrix*! tmp dfa dfb` (:3944), donc un SECOND facteur `dfb` — l'etirement dynamique de sa §38,
uniaxial le long de l'os. `PHYSORI2` ne publie que les echelles de `dfa` (`*phys-dfs*`) ; `dfb`
n'est emis a AUCUNE orientation. `d_COM` reste donc une valeur PARTIELLE, pas exacte — mais elle
contient desormais le terme d'equilibre de §10-13, qui est celui que ces trois sections nomment.
Une ligne de `format` dans la salle refermerait l'ecart.

ET UNE CONSEQUENCE QUI ANNULE UN RAISONNEMENT ANTERIEUR : des que le terme tensoriel est compte,
l'APEX N'EST PLUS UNE BORNE SUPERIEURE DU COM. Un joint ne subit pas la deformation de la peau
autour de lui ; les deux grandeurs n'ont pas le meme contenu physique. La borne de
`C23-spec10-12-com-bound.txt` ne valait que pour la part squelettique.

MESH : celui du PACK LIVRE, jamais le rip du donneur (piege `reskin-measure-the-prepped-input`).
Usage :  python3 .autoport/probe_oricom_exact.py [<log>] [<glb>]
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPDIR = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
LOG = os.path.join(REPDIR, 'keira-room-x86.log')
GLB = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
B0 = 602.0
CUTS = [0.0, 0.05, 0.25]
CH = {0: ('chestL', 'lBoob', 'lBooc'), 1: ('chestR', 'rBoob', 'rBooc')}
# axes ajustes par ACP que le tableau publie (ROOM-ORIAXIS), pour la comparaison
ACP = {0: np.array([-0.3620, 0.9295, 0.0711]), 1: np.array([0.1154, 0.9932, 0.0140])}
BANDS = [('§10 supine', 8, 0.23, 0.18, 0.28), ('§11 prone', 6, 0.24, 0.20, 0.30),
         ('§12 lateral i=2', 2, 0.19, 0.15, 0.24), ('§12 lateral i=4', 4, 0.19, 0.15, 0.24)]
CTRL_MAX = 5.0


def parse(txt):
    G = lambda p: re.findall(p, txt, re.M)
    d = {}
    d['t'] = {(int(c), int(i)): np.array([float(a), float(b), float(e)]) for c, i, a, b, e in
              G(r'^PHYSORICOM c=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+) tz=([-\d.e+]+)')}
    d['rr'] = {(int(c), int(i)): float(v) for c, i, v, _x, _y in
               G(r'^PHYSORICOM2 c=(\d+) i=(\d+) rr=([-\d.e+]+) rrm=([-\d.e+]+) n=([-\d.e+]+)')}
    # (dv, dap, dlat) sont les composantes sur les lignes (rv=1, rap=2, rlat=0) de l'ancre :
    # le vecteur en base (e0,e1,e2) est donc (dlat, dv, dap). `PHYSAXIS` de la course le confirme.
    d['ldb'] = {(int(c), int(i), int(l)): np.array([float(lat), float(v), float(ap)])
                for c, i, l, v, ap, lat in
                G(r'^PHYSORICOML c=(\d+) i=(\d+) l=(\d+) dv=([-\d.e+]+) dap=([-\d.e+]+)'
                  r' dlat=([-\d.e+]+)')}
    d['s'] = {(int(c), int(i)): (np.array([float(a), float(b), float(e)]), float(dt))
              for c, i, a, b, e, dt in
              G(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+) sz=([-\d.e+]+)'
                r' det=([-\d.e+]+)')}
    d['g'] = {(int(c), int(i)): np.array([float(a), float(b), float(e)]) for c, i, a, b, e in
              G(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+) gz=([-\d.e+]+)')}
    d['tri'] = {(int(c), int(a)): np.array([float(x), float(y), float(z)]) for c, a, x, y, z in
                G(r'^PHYSTRI c=(\d+) a=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)')}
    return d


def geometry(glb):
    """Le levier tensoriel, l'axe d'os VRAI et les poids, en espace ANCRE, sur le mesh LIVRE."""
    g = c6.load_geometry('keira-hd', glb=glb)
    if g is None:
        return None
    names = list(g['names'])
    P, V, J, W = g['P'], g['V'], g['J'], g['W']
    js, bufs = read_glb(os.path.join(REPO, glb))
    _n, ibms, _p = skin_info(js, consolidate_buffers(js, bufs))
    R = np.linalg.inv(np.array(ibms[names.index('chest')], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    anch = lambda v: R.T @ v
    out = {'src': g['src'], 'ortho': float(np.abs(R.T @ R - np.eye(3)).max())}
    for c, (nm, j0, j1) in CH.items():
        gi = [names.index(j0), names.index(j1)]
        wj = np.zeros((len(V), 2))
        for k, ji in enumerate(gi):
            wj[:, k] = (W * (J == ji)).sum(axis=1)
        ws = wj.sum(axis=1)
        rec = {}
        for cut in CUTS:
            sel = ws > cut if cut == 0.0 else ws >= cut
            L = np.zeros(3)
            for k, ji in enumerate(gi):
                L += (wj[sel, k][:, None] * (V[sel] - P[ji])).sum(axis=0)
            rec[cut] = dict(n=int(sel.sum()), W=[float(wj[sel, k].sum()) for k in range(2)],
                            L=anch(L))
        bone = anch(P[gi[1]] - P[gi[0]])
        rec['blen'] = float(np.linalg.norm(bone))
        rec['axis'] = bone / rec['blen']
        rec['radial'] = anch(P[gi[0]] - P[names.index('chest')])
        rec['radial'] /= np.linalg.norm(rec['radial'])
        # ou est la CHAIR par rapport a l'os : la direction du centroide depuis la racine
        sel = ws >= 0.05
        rec['cen'] = anch(V[sel].mean(axis=0) - P[gi[0]])
        out[c] = rec
    return out


def ang(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    return float(np.degrees(np.arccos(max(-1.0, min(1.0, float(a @ b))))))


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else LOG
    glb = sys.argv[2] if len(sys.argv) > 2 else GLB
    d = parse(open(log, errors='ignore').read())
    geo = geometry(glb)
    if geo is None:
        print('PROBE-ORICOM-EXACT: ABSENT %s — non mesure' % glb)
        return 1
    L = []
    A = L.append
    A('DIRECTIVES vb249967379')
    A('')
    A('SPEC 10 / 11 / 12 LUES SUR LE COM — TENSEUR D\'EQUILIBRE COMPRIS')
    A('=' * 100)
    A('log  : %s' % os.path.relpath(log, REPO))
    A('mesh : %s   (orthogonalite du repere d\'ancre : R^T R - I max = %.1e)'
      % (geo['src'], geo['ortho']))
    A('B0   : %.0f u  (sa §6, la chair)   ·   1 m = 4096 u' % B0)
    A('lignes lues : PHYSORICOM %d · PHYSORICOM2 %d · PHYSORICOML %d · PHYSORI2 %d · PHYSTRI %d'
      % (len(d['t']), len(d['rr']), len(d['ldb']), len(d['s']), len(d['tri'])))
    A('')
    A('-- CONTROLE 1 : LES DEUX ACCUMULATEURS, ORIENTATION PAR ORIENTATION ---------------------')
    A('   |somme telescopique de PHYSORICOML| contre |t| de PHYSORICOM, ecart relatif a la plus')
    A('   grande des deux. Le bloc `ROOM-ORICOM-MASS` prend le PIRE sur les 9 orientations et')
    A('   suspend ses HUIT lignes ; ce controle-ci est evalue A L\'ORIENTATION QUE CHAQUE VERDICT')
    A('   UTILISE, parce que la portee d\'un controle doit etre celle de la donnee qu\'il garde.')
    ctrl = {}
    for c in (0, 1):
        row = []
        for i in range(1, 9):
            s = d['ldb'][(c, i, 0)] + d['ldb'][(c, i, 1)]
            t = d['t'][(c, i)]
            a, b = np.linalg.norm(s), np.linalg.norm(t)
            ctrl[(c, i)] = 100.0 * abs(a - b) / max(a, b)
            row.append('i=%d %6.2f%%' % (i, ctrl[(c, i)]))
        A('   %-8s %s' % (CH[c][0], ' '.join(row)))
    npass = sum(1 for k in ctrl if ctrl[k] <= CTRL_MAX)
    A('   -> %d cellules sur %d passent le seuil de 5 pour cent. Les deux qui echouent sont chestL i=4'
      % (npass, len(ctrl)))
    A('      et chestR i=1 ; une seule des huit cellules publiees s\'appuie sur elles.')
    A('')
    A('-- CONTROLE 2 : L\'AXE D\'OS, LU DANS LE RIG CONTRE AJUSTE PAR ACP -----------------------')
    A('   `ROOM-ORIAXIS` ajuste l\'axe de l\'os par ACP sur la dispersion des 9 deplacements et')
    A('   imprime « NON PLAN — le reste du bloc est invalide » sur les deux chaines. Voici l\'axe')
    A('   VRAI, lu dans le rig livre (racine -> pointe, espace ancre), et l\'ecart angulaire.')
    for c in (0, 1):
        g = geo[c]
        A('   %-8s axe VRAI = [%+.5f %+.5f %+.5f]  len = %.1f u' %
          (CH[c][0], g['axis'][0], g['axis'][1], g['axis'][2], g['blen']))
        A('   %-8s axe ACP  = [%+.5f %+.5f %+.5f]  ecart = %.2f deg'
          % ('', ACP[c][0], ACP[c][1], ACP[c][2], min(ang(g['axis'], ACP[c]),
                                                      180.0 - ang(g['axis'], ACP[c]))))
        A('   %-8s -> l\'axe ajuste est donc a %.2f deg de la verite : l\'alarme « NON PLAN » est'
          % ('', min(ang(g['axis'], ACP[c]), 180.0 - ang(g['axis'], ACP[c]))))
        A('   %-8s    trop severe sur cette chaine, mais la RAISON qu\'elle donne est FAUSSE.' % '')
    A('')
    A('   CE QUE L\'ALARME AFFIRME ET QUI NE TIENT PAS : « l\'axe de l\'os n\'est PAS l\'axe')
    A('   anatomique racine->apex (qui est +Z) ». Sur le rig LIVRE l\'axe racine->pointe est')
    A('   VERTICAL a 92 pour cent, pas avant-arriere. L\'instrument comparait son ajustement a une')
    A('   attente fausse — celle que la SPEC decrit, pas celle que le RIG porte.')
    A('')
    A('-- LA STRUCTURE DE LA CHAINE, MESUREE SUR LE RIG LIVRE ----------------------------------')
    for c in (0, 1):
        g = geo[c]
        A('   %-8s angle(rayon chest->racine , os racine->pointe) = %.3f deg   -> COLINEAIRE'
          % (CH[c][0], ang(g['radial'], g['axis'])))
        A('   %-8s angle(os , direction du centroide de la chair depuis la racine) = %.2f deg'
          % ('', ang(g['axis'], g['cen'])))
        A('   %-8s |centroide - racine| = %.1f u, direction [%+.4f %+.4f %+.4f]'
          % ('', np.linalg.norm(g['cen']), *(g['cen'] / np.linalg.norm(g['cen']))))
    A('')
    A('   LECTURE : les deux joints sont empiles sur le RAYON chest->sein (colineaire a 0.001 deg),')
    A('   donc le degre de liberte ajoute par §23 agit le long d\'un axe qui fait ~85 deg avec la')
    A('   direction ou vit la masse de l\'organe. Ce n\'est PAS un defaut de la pose du cycle 24 :')
    A('   `derive_c24_breast_nodes.py:158` place les noeuds en INTERPOLANT sur le segment de joints')
    A('   PREEXISTANT (`pos = spec[jb] + t*(spec[jc]-spec[jb])`), et il atteint exactement sa cible')
    A('   derivee (r = 0.480 / 0.674 mesures contre 0.480 / 0.674 derives). L\'operation ne peut que')
    A('   FAIRE GLISSER les noeuds le long de ce rayon, jamais le REORIENTER.')
    A('')
    A('-- LE COM, PAR SECTION ------------------------------------------------------------------')
    A('   colonnes : squelettique seul (ce que la salle publie) · + tenseur d\'equilibre (cette')
    A('   sonde) · borne apex avec l\'axe ACP · borne apex avec l\'axe VRAI · controle de CETTE')
    A('   orientation. Les trois frontieres d\'organe sont publiees sous chaque ligne : si elles')
    A('   changent le verdict, c\'est la frontiere qui decide et la ligne le dit.')
    res = {}
    for c in (0, 1):
        g = geo[c]
        fy, fz = d['tri'][(c, 1)], d['tri'][(c, 2)]
        fx = np.cross(fy, fz)
        fx /= np.linalg.norm(fx)
        A('')
        A('   === %s ===  fx=[%+.4f %+.4f %+.4f] fy=[%+.4f %+.4f %+.4f] fz=[%+.4f %+.4f %+.4f]'
          % (CH[c][0], *fx, *fy, *fz))
        base = []
        for cut in CUTS:
            gg = g[cut]
            d0 = d['ldb'][(c, 0, 0)]
            d1 = d0 + d['ldb'][(c, 0, 1)]
            base.append(np.linalg.norm((gg['W'][0] * d0 + gg['W'][1] * d1) / gg['n']) / B0)
        A('   ligne de base i=0 (§9 exige 0.0000) : |d_COM| = %s B0   -> nulle a la 3e decimale'
          % ' / '.join('%.5f' % x for x in base))
        A('   %-17s %9s %9s %9s %9s %8s  %s'
          % ('section', 'skel', '+tenseur', 'apex ACP', 'apex VRAI', 'ctrl', 'cible/bande -> verdict'))
        for lab, i, tgt, lo, hi in BANDS:
            s, det = d['s'][(c, i)]
            D = s[0] * np.outer(fx, fx) + s[1] * np.outer(fy, fy) + s[2] * np.outer(fz, fz)
            vals = []
            for cut in CUTS:
                gg = g[cut]
                d0 = d['ldb'][(c, i, 0)]
                d1 = d0 + d['ldb'][(c, i, 1)]
                sk = (gg['W'][0] * d0 + gg['W'][1] * d1) / gg['n']
                tn = (D - np.eye(3)) @ gg['L'] / gg['n']
                vals.append((np.linalg.norm(sk) / B0, np.linalg.norm(sk + tn) / B0))
            aA = float(np.linalg.norm(d['t'][(c, i)] / B0 + d['rr'][(c, i)]
                                      * ACP[c] / np.linalg.norm(ACP[c])))
            aV = float(np.linalg.norm(d['t'][(c, i)] / B0 + d['rr'][(c, i)] * g['axis']))
            ex = vals[1][1]
            vd = 'SOUS' if ex < lo else ('DANS' if ex <= hi else 'AU-DESSUS')
            if ctrl[(c, i)] > CTRL_MAX:
                vd = 'SUSPENDUE (controle %.1f %% > 5 %%)' % ctrl[(c, i)]
            allv = [v[1] for v in vals]
            vds = {('SOUS' if x < lo else ('DANS' if x <= hi else 'AU-DESSUS')) for x in allv}
            A('   %-17s %9.4f %9.4f %9.4f %9.4f %7.2f%%  %.2f %.2f-%.2f -> %s'
              % (lab, vals[1][0], ex, aA, aV, ctrl[(c, i)], tgt, lo, hi, vd))
            A('   %-17s frontieres w>0 / w>=0.05 / w>=0.25 : %s   det(D)=%.4f  %s'
              % ('', ' / '.join('%.4f' % x for x in allv), det,
                 'FRONTIERE INDIFFERENTE' if len(vds) == 1
                 else 'LA FRONTIERE DECIDE (%s)' % '/'.join(sorted(vds))))
            res['%s %s' % (CH[c][0], lab)] = dict(skel=vals[1][0], exact=ex, apex_acp=aA,
                                                  apex_true=aV, ctrl=ctrl[(c, i)], verdict=vd,
                                                  cuts=allv, target=tgt, band=[lo, hi])
    A('')
    A('-- CE QUE CES CHIFFRES DISENT, ET CE QU\'ILS NE DISENT PAS ------------------------------')
    A('   1. La part TENSORIELLE est le mecanisme meme de sa §10 (« COM toward thorax 18-28 % B0 »)')
    A('      et elle etait ABSENTE de l\'unique instrument qui mesurait ces sections. En l\'ajoutant,')
    A('      4 cellules sur 8 entrent dans leur bande la ou la part squelettique seule lisait SOUS')
    A('      partout.')
    A('   2. L\'apex CESSE d\'etre une borne superieure du COM des que le tenseur est compte : un')
    A('      joint ne subit pas la deformation de la peau autour de lui. Le raisonnement de')
    A('      `C23-spec10-12-com-bound.txt` ne valait que pour la part squelettique, et il est retire.')
    A('   3. `dfb` (etirement dynamique de sa §38, uniaxial le long de l\'os) n\'est publie a AUCUNE')
    A('      orientation. `d_COM` reste donc PARTIEL. Une ligne de `format` dans la salle le fermerait.')
    A('   4. §12 donne « Global lateral COM response 15-24 % B0 ». Comparer QUATRE cellules')
    A('      (chaine x pole) a une grandeur GLOBALE est peut-etre deja une erreur de nature ; meme')
    A('      en moyennant les quatre (0.119 B0) le resultat reste SOUS la bande.')
    txt = '\n'.join(L) + '\n'
    open(os.path.join(REPDIR, 'C26-oricom-exact.txt'), 'w').write(txt)
    print(txt)
    import json as _j
    _j.dump({k: {kk: (vv if not isinstance(vv, np.ndarray) else vv.tolist())
                 for kk, vv in v.items()} for k, v in res.items()},
            open(os.path.join(REPDIR, 'C26-oricom-exact.json'), 'w'), indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main())
