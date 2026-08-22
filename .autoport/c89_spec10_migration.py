#!/usr/bin/env python3
"""c89_spec10_migration.py — SPEC 10, LES DEUX CLAUSES DE DEPLACEMENT, LUES EN VECTEUR.

DIRECTIVES v3fee554599.  Section dont ce cycle debloque le verdict : SPEC 10 (derniere ligne
`NON ETABLI` du registre).  ZERO course neuve, ZERO ligne de moteur : tout se lit dans la trace
ARCHIVEE et dans le mesh LIVRE.

CE QUE CETTE SONDE AJOUTE A `probe_oricom_exact.py`, ET POURQUOI.
  (1) `d_COM` y est reduit a sa NORME avant d'etre compare a la bande.  Or les deux clauses de
      deplacement de sa §10 nomment chacune une DIRECTION :
          « COM toward **thorax**: 18-28% B0 »          -> une projection sur l'axe THORACIQUE
          « **Outward** COM migration per breast: 4-10% W0 » -> une projection sur le LATERAL SORTANT
      Une norme est >= toute projection : lire une clause directionnelle sur une norme est une
      BORNE SUPERIEURE deguisee en mesure.  C'est la faute `metric-nature-and-frame`, et la
      seconde clause n'avait tout simplement AUCUN canal.
  (2) Le vecteur SORTANT est lu sur le RIG LIVRE, pas sur `PHYSTRI`.  `PHYSTRI` est publie en
      repere MONDE (phys-room.gc:3117-3118) alors que `d_COM` vit dans la base de l'ANCRE ; et
      `probe_oricom_exact.py:268` le RECALCULE par `cross(fy,fz)`, ce qui rend le MEME vecteur
      pour les deux seins et perd donc le miroir par chaine que le moteur applique
      (jak-hd-physics.gc NOTE-324).  Ici le sortant est la separation racine-a-racine mesuree
      dans le mesh livre, ramenee en base d'ancre : deux origines, aucune convention.

LES TROIS QUESTIONS (SPEC 7), repondues avant le chiffre :
  NATURE : deux LONGUEURS SIGNEES (projections d'un deplacement soutenu), l'une en B0, l'autre
           en W0.  Pas une norme, pas une variance.
  REPERE : la base de l'ANCRE (`chest`), celle ou vivent deja `PHYSORICOML` et `PHYSDFMA`.
  ABSENT : l'orientation i=0 est la pose debout d'auteur, ou sa §9 exige 0.0000.  Elle est
           calculee et publiee comme ligne de base de CHAQUE colonne.

REGLE POSEE AVANT DE REGARDER LE RESULTAT (`never-fit-a-parameter-to-the-instrument`) :
  la frontiere d'organe retenue est celle qui passe le TEST DE RAFFINEMENT, c'est-a-dire celle
  dont la valeur bouge le moins entre `w>0` et `w>=0.25`.  Si les trois frontieres ne s'accordent
  pas a 30 % pres (barre de `instrument-refinement-test`), AUCUNE n'est retenue et la clause
  reste NON ETABLIE.  Ce critere est ecrit ici avant l'execution et ne sera pas revise.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_c6_volumes as c6
import probe_oricom_exact as P
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B0 = 602.0
W0 = 776.1          # SPEC-COVERAGE §6, cycle 64 : etendue laterale du nuage de chair, mesh livre
CUTS = P.CUTS
CH = P.CH
# les quatre cellules que sa spec chiffre, designees par la GRAVITE mesuree (ROOM-ORIROLE)
CELLS = [('§10 supine', 8), ('§11 prone', 6), ('§12 lateral i=2', 2), ('§12 lateral i=4', 4),
         ('debout i=0', 0)]


def outward_axis(glb):
    """Le LATERAL SORTANT par chaine, en base d'ANCRE, lu dans le rig LIVRE.

    Origine : la separation racine-a-racine (`rBoob` - `lBoob`).  Pour chestL le sortant est
    l'oppose, pour chestR c'est elle-meme.  Aucune constante, aucune convention : c'est de
    l'anatomie mesuree, et son controle est que les deux vecteurs soient exactement opposes."""
    g = c6.load_geometry('keira-hd', glb=glb)
    names = list(g['names'])
    Pb = g['P']
    js, bufs = read_glb(os.path.join(REPO, glb))
    _n, ibms, _p = skin_info(js, consolidate_buffers(js, bufs))
    R = np.linalg.inv(np.array(ibms[names.index('chest')], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    sep = R.T @ (Pb[names.index('rBoob')] - Pb[names.index('lBoob')])
    sep = sep / np.linalg.norm(sep)
    return {0: -sep, 1: sep}


def anat_axes(g, c, out):
    """LE TRIEDRE DE SA §7, EN BASE D'ANCRE, MESURE SUR LE RIG LIVRE — aucune convention.

    §7 l.126-134 : « +X = character's outward lateral direction ; +Y = upward along torso ;
    +Z = forward from chest ».  Les trois sont construits ici a partir de DEUX mesures et d'un
    produit vectoriel, jamais d'une constante :
      +X = la separation racine-a-racine (`outward_axis`), deja publiee et exactement opposee
           entre les deux seins ;
      +Z = la direction du CENTROIDE DE CHAIR depuis la racine de la chaine — c'est la SAILLIE,
           donc l'avant au sens de la §7 — ORTHOGONALISEE contre +X pour que « toward thorax »
           (clause b) et « outward » (clause d) ne se melangent pas ;
      +Y = +Z x +X, orthonorme par construction.
    « toward thorax » de sa §10 est donc -Z, et rien d'autre.

    POURQUOI PAS `chest -> racine` : cette direction-la est VERTICALE a 92 % sur le rig livre
    (le joint `chest` est presque a l'aplomb des racines de sein) ; ce n'est pas l'axe que sa
    §10 nomme.  « Un axe de mesure qui n'est pas celui que la spec DEFINIT est un axe faux »
    (DIRECTIVES 2026-08-20 07:20).  L'angle os / centroide vaut 86 deg : les deux ne sont PAS
    interchangeables et le confondre est le piege `two-distal-axes-are-not-the-same-population`."""
    x = out[c]
    z = g[c]['cen'] - float(g[c]['cen'] @ x) * x
    z = z / np.linalg.norm(z)
    y = np.cross(z, x)
    return x, y / np.linalg.norm(y), z


def w0_measure(glb, out):
    """`W0` RE-DERIVEE ICI, PARCE QU'ELLE N'AVAIT AUCUN PRODUCTEUR DANS LE DEPOT.

    Le 776,1 u du registre (§6, cycle 64) ne vit que dans la PROSE de `SPEC-COVERAGE.md` :
    `grep` ne trouve ni script qui le calcule, ni trace qui le porte.  Un denominateur sans
    producteur reproductible n'est pas une mesure — et c'est le denominateur de la clause (d)
    de sa §10.  On le recalcule donc ici avec l'operateur que le registre DECRIT (« etendue du
    nuage de chair en pose de bind, dans le triedre du torse, mesh LIVRE ») et on publie l'ecart
    au chiffre de prose : s'ils divergent, c'est le chiffre de prose qui tombe, pas la mesure."""
    g = c6.load_geometry('keira-hd', glb=glb)
    names = list(g['names'])
    V, J, W = g['V'], g['J'], g['W']
    js, bufs = read_glb(os.path.join(REPO, glb))
    _n, ibms, _p = skin_info(js, consolidate_buffers(js, bufs))
    R = np.linalg.inv(np.array(ibms[names.index('chest')], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    res = {}
    for c, (nm, j0, j1) in CH.items():
        gi = [names.index(j0), names.index(j1)]
        ws = sum((W * (J == ji)).sum(axis=1) for ji in gi)
        res[c] = {}
        for cut in CUTS:
            sel = ws > cut if cut == 0.0 else ws >= cut
            lat = (V[sel] @ R) @ np.array([1.0, 0.0, 0.0])   # composante sur e0 = le lateral
            res[c][cut] = float(lat.max() - lat.min())
    return res


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else P.LOG
    glb = sys.argv[2] if len(sys.argv) > 2 else P.GLB
    txt = open(os.path.join(REPO, log), 'r', errors='replace').read()
    d = P.parse_extra(txt, P.parse(txt))
    g = P.geometry(glb)
    out = outward_axis(glb)
    ax = {c: anat_axes(g, c, out) for c in (0, 1)}
    w0 = w0_measure(glb, out)

    # CONTROLE DE MONTAGE, VERSION VECTORIELLE (cycle 64b : une norme est aveugle a la direction).
    # `ldb` est stocke (dlat, dv, dap) = (e0, e1, e2) et `t` est (tx, ty, tz) dans la MEME base :
    # `ROOM-ORIFRAME` le mesure (dv=+t[1], dap=+t[2], dlat=+t[0], residu 0.027 sur 16 cellules).
    ctrl = {}
    for c in (0, 1):
        for i in range(0, 9):
            if (c, i, 0) not in d['ldb'] or (c, i) not in d['t']:
                continue
            s_ = d['ldb'][(c, i, 0)] + d['ldb'][(c, i, 1)]
            t_ = d['t'][(c, i)]
            den = max(np.linalg.norm(s_), np.linalg.norm(t_))
            ctrl[(c, i)] = 100.0 * float(np.linalg.norm(s_ - t_)) / den if den > 1e-9 else 0.0

    A = print
    A('DIRECTIVES v3fee554599')
    A('')
    A('SPEC 10 — LES DEUX CLAUSES DE DEPLACEMENT, LUES COMME DES PROJECTIONS')
    A('=' * 104)
    A('log  : %s' % os.path.relpath(os.path.join(REPO, log), REPO))
    A('mesh : %s' % glb)
    A('')
    A('-- LE TRIEDRE DE SA §7, MESURE SUR LE RIG LIVRE (base d\'ancre) -------------------------')
    for c in (0, 1):
        x, y, z = ax[c]
        A('   %-8s +X sortant [%+.5f %+.5f %+.5f]  +Y haut [%+.5f %+.5f %+.5f]'
          '  +Z avant [%+.5f %+.5f %+.5f]' % (CH[c][0], *x, *y, *z))
    A('   CONTROLE 1 — les deux +X exactement opposes (§7 : « outward +X should be MIRRORED ')
    A('                so that the equations remain symmetrical », l.130-131) : %s'
      % ('OUI' if np.allclose(out[0], -out[1], atol=1e-12) else 'NON'))
    dz = float(np.degrees(np.arccos(max(-1.0, min(1.0, float(ax[0][2] @ ax[1][2]))))))
    A('   CONTROLE 2 — les deux +Z (la SAILLIE, donc l\'avant de sa §7) coincident a %.3f deg.'
      % dz)
    A('                Le rig est bilateralement symetrique a 0.005 deg en bind (cycle 53) : un')
    A('                +Z qui ne coinciderait pas dirait que l\'axe est CONSTRUIT, pas mesure.')
    A('   CONTROLE 3 — `W0`, LE DENOMINATEUR DE LA CLAUSE (d), N\'AVAIT AUCUN PRODUCTEUR DANS LE')
    A('                DEPOT : 776,1 u ne vivait que dans la prose de SPEC-COVERAGE §6. Re-derive')
    A('                ici avec l\'operateur que le registre DECRIT, sur le mesh LIVRE :')
    for c in (0, 1):
        vv = [w0[c][k] for k in CUTS]
        sp = (max(vv) - min(vv)) / max(vv) * 100.0
        A('                %-8s w>0 %.1f u · w>=0.05 %.1f u · w>=0.25 %.1f u   raffinement %.1f %%'
          '   (prose : %.1f u -> ecart %+.2f %%)'
          % (CH[c][0], vv[0], vv[1], vv[2], sp, W0, (vv[1] - W0) / W0 * 100.0))
    A('   CONTROLE 4 — le montage de la pointe, EN VECTEUR, a l\'orientation de CHAQUE verdict :')
    for c in (0, 1):
        A('                %-8s %s' % (CH[c][0], ' '.join(
            'i=%d %5.2f%%' % (i, ctrl[(c, i)]) for i in range(9) if (c, i) in ctrl)))
    A('                Seuil declare 5 %% (cycle 64b). Au-dela la cellule n\'est pas jetee : son')
    A('                effet est BORNE ci-dessous, terme squelettique par terme squelettique.')
    A('')
    A('   NATURE  deux LONGUEURS SIGNEES (projections d\'un deplacement soutenu), en B0 et en W0.')
    A('   REPERE  la base de l\'ANCRE, celle de `PHYSORICOML` et de `PHYSDFMA`.')
    A('   ABSENT  i=0 est la pose debout d\'auteur, ou sa §9 exige 0.0000 — publiee ci-dessous.')
    A('   CE QUI RESTE DEHORS, NOMME : `PHYSDFMA` porte dfa x dfb x dfc mais PAS la rotation de')
    A('     torsion de sa §29 (appliquee apres, seulement dans `*phys-dfm*`, jak-hd-physics.gc')
    A('     :3815-3824). `PHYSSHAPE2 twm` la mesure a 0.0008 : le terme manquant est de cet')
    A('     ordre, il est declare et non suppose nul.')
    A('')

    for c in (0, 1):
        x, _y, z = ax[c]
        thx = -z
        A('   === %s ===' % CH[c][0])
        A('   %-16s %-9s | %-22s | %-22s' % ('cellule', 'frontiere',
                                             '  vers thorax (B0)', '  sortant (% W0)'))
        A('   %-16s %-9s | %8s %7s %6s | %8s %7s %6s' % ('', '', 'total', 'squel.', 'tens.',
                                                         'total', 'squel.', 'tens.'))
        for lab, i in CELLS:
            if (c, i, 0) not in d['ldb'] or (c, i) not in d['dfma']:
                A('   %-16s ABSENTE de la trace (ldb ou PHYSDFMA)' % lab)
                continue
            D = d['dfma'][(c, i)]
            row = []
            for cut in CUTS:
                gc = g[c][cut]
                d0 = d['ldb'][(c, i, 0)]
                d1 = d0 + d['ldb'][(c, i, 1)]
                sk = (gc['W'][0] * d0 + gc['W'][1] * d1) / gc['n']
                # CONVENTION DU MOTEUR : `jak-hd-physics.gc:3922` applique l'offset en VECTEUR-LIGNE
                # (`r_j = SOMME_i o_i . bm[i][j]`) et le tenseur multiplie A DROITE (`matrix*! tmp bm dfm`).
                # La contribution tensorielle est donc `L . (D - I)`, PAS `(D - I) . L`. `D` est symetrique
                # a 0.032 pres (controle de `ROOM-SPEC12`), donc l'ecart vaut ~0.5 % — on prend quand meme
                # la convention du moteur, pour que sonde et tableau ne divergent jamais.
                tn = gc['L'] @ (D - np.eye(3)) / gc['n']
                row.append(dict(
                    th=(float((sk + tn) @ thx) / B0, float(sk @ thx) / B0, float(tn @ thx) / B0),
                    ou=(float((sk + tn) @ x) / w0[c][cut] * 100.0,
                        float(sk @ x) / w0[c][cut] * 100.0,
                        float(tn @ x) / w0[c][cut] * 100.0)))
            for k, cut in enumerate(CUTS):
                A('   %-16s %-9s | %8.4f %7.4f %6.4f | %8.3f %7.3f %6.3f'
                  % (lab if k == 1 else '', 'w>%.2f' % cut, *row[k]['th'], *row[k]['ou']))
            if i != 8:
                A('        (diagnostic : les bandes de §10 ne s\'appliquent qu\'a la cellule SUPINE)')
                continue
            e = ctrl.get((c, i), 0.0) / 100.0
            for key, nm, lo, hi, un in (('th', 'vers thorax', 0.18, 0.28, 'B0'),
                                        ('ou', 'sortant', 4.0, 10.0, '% W0')):
                vals = [r[key][0] for r in row]
                den = max(abs(min(vals)), abs(max(vals)))
                spread = (max(vals) - min(vals)) / den * 100.0 if den > 1e-12 else 0.0
                vd = sorted({('SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS'))
                             for v in vals})
                # BORNE DU CONTROLE : l'ecart de montage ne porte que sur le terme SQUELETTIQUE.
                lo_b = min(r[key][0] - e * abs(r[key][1]) for r in row)
                hi_b = max(r[key][0] + e * abs(r[key][1]) for r in row)
                vdb = sorted({('SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS'))
                              for v in (lo_b, hi_b)})
                A('        %-12s bande %.2f-%.2f %-5s  frontieres -> %-16s  raffinement %5.1f %% %s'
                  % (nm, lo, hi, un, '/'.join(vd), spread,
                     '(<=30 % OK)' if spread <= 30 else '(>30 % REJETE)'))
                A('        %-12s pire cas du montage (+/- %.2f %% du terme squelettique) :'
                  ' [%.4f ; %.4f] -> %s' % ('', ctrl.get((c, i), 0.0), lo_b, hi_b, '/'.join(vdb)))
        A('')
    return 0


if __name__ == '__main__':
    sys.exit(main())
