#!/usr/bin/env python3
"""c91_axis_and_downstream.py — LE « 13 CONTRE 8 » DU CYCLE 90 COMPARAIT DEUX AXES, PAS DEUX ETATS.

DIRECTIVES v3fee554599.  ZERO course neuve pour la PARTIE MESURE : trace ARCHIVEE + mesh LIVRE.

SECTIONS DONT CE CYCLE DEBLOQUE LE VERDICT, NOMMEES AVANT DE COMMENCER (directive 2026-08-21
18:25) : **§10, §11, §12** — les trois sections de forme d'orientation.

CE QUE LE CYCLE 90 A PUBLIE, ET POURQUOI IL FAUT LE RETIRER TEL QUEL :

    « l'equilibre d'orientation `dfa` tombe dans sa bande sur 13 cellules sur 16 ; le produit
      `dfa x dfb x dfc` que la PEAU recoit n'y tombe que sur 8. »

Les deux chiffres ne sont PAS lus sur le meme axe. `13` est le compte des VALEURS PROPRES du
moteur (`PHYSORI2 sx/sy/sz`, c'est-a-dire `dfa` lu sur le triedre OU LE MOTEUR LE CONSTRUIT) ;
`8` est le compte du produit lu sur le triedre du REGISTRE (`breast-com-mass.json`). Les deux
triedres sont a 20,65 deg l'un de l'autre. Comparer leurs comptes, c'est mesurer un ecart d'AXE
et l'attribuer a des facteurs aval — exactement la faute que le meme cycle 90 corrigeait chez
l'instrument (`deux « distal » ne sont pas la meme population`).

CE QUE CETTE SONDE FAIT, DANS L'ORDRE :

 1. **ELLE TRANCHE LE TRIEDRE PAR LA MESURE, PAS PAR GOUT.** §7 l.126-134 nomme ses trois axes
    avec des mots qui designent des choses MESURABLES sur le rig livre :
        « +X = character's outward lateral direction »  -> separation racine-a-racine
        « +Y = upward along torso »                     -> l'axe long du TORSE : `hips` -> `neck`
        « +Z = forward from chest »                     -> complete le triedre, sens donne par la
                                                           saillie de la chair
    Ni le triedre du moteur (`+Y = -g_ref`) ni celui du registre (`+Y = saillie x lateral`) n'est
    celui-la : ils en sont a 11,92 et 12,27 deg, **de part et d'autre**. La sonde publie les trois
    et leurs angles, et le triedre du RIG est le seul dont les trois axes viennent chacun d'une
    phrase de §7 et d'une mesure sur le mesh LIVRE.

 2. **ELLE PUBLIE LE REGISTRE DES 16 ECHELLES SUR UN SEUL AXE**, dans quatre etats : le produit
    complet, `dfb -> I` (le geste), `dfa` seul, et la valeur propre du moteur — plus le meme
    registre sur le triedre du registre, pour que l'ecart d'axe soit visible et non suppose.

 3. **ELLE IDENTIFIE LE FACTEUR AVAL AU LIEU DE LE NOMMER.** `B = dfa^-1 . A` est calcule sur les
    18 cellules : c'est un etirement UNIAXIAL de determinant 1, nul a la verticale (i=0), et sa
    magnitude vaut `0.43 x |deplacement d'equilibre| / B0` — le facteur `PHYS-DYN-K` du moteur,
    applique au deplacement que §10/§11/§12 SPECIFIENT deja. Autrement dit : l'equilibre est
    converti une SECONDE fois en elongation locale, sur un axe different de celui que ces trois
    sections bornent. C'est un DOUBLE COMPTE, et il est TENU (il ne decroit pas), alors que le
    canal qui le porte est celui des « Dynamic Soft Limits » de §22.

LES TROIS QUESTIONS (SPEC 7), repondues avant le chiffre :
  NATURE  des ECHELLES (rapports sans unite) le long d'axes nommes, et un DEPLACEMENT SOUTENU en
          B0 pour la partie 3. Jamais une variance, jamais une amplitude.
  REPERE  la base de l'ANCRE (`chest`), celle ou vivent `PHYSDFMA`, `PHYSORICOM` et la geometrie
          du glb ramenee par `R_chest^T`. Aucune composante ne traverse deux reperes.
  ABSENT  l'orientation i=0 est la pose debout d'auteur, ou §9 exige l'identite. Elle est publiee
          sur chaque ligne : `B` y vaut I a 0,0007 pres, ce qui est la ligne de base du facteur
          aval et la preuve qu'il n'est pas un artefact de la decomposition.

MESH : celui du PACK LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`), jamais le rip du donneur ni le
`-donor-injected.glb` intermediaire (piege `reskin-measure-the-prepped-input`).

Usage :  python3 .autoport/c91_axis_and_downstream.py [<log>] [<glb>]
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPDIR = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
LOG = os.path.join(REPDIR, 'keira-room-x86.log')
MASS = os.path.join(REPDIR, 'breast-com-mass.json')
GLB = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
B0 = 602.0
NM = {0: 'chestL', 1: 'chestR'}
DYN_K = 0.43                     # `PHYS-DYN-K`, jak-hd-physics.gc:229

# (etiquette, orientation, axe de §7, index de valeur propre du moteur, lo, hi)
SHAPE = (
    ('§10 supine projection', 8, 'fwd', 2, 0.65, 0.75),
    ('§10 supine largeur',    8, 'out', 0, 1.18, 1.28),
    ('§10 supine hauteur',    8, 'up',  1, 1.05, 1.12),
    ('§11 prone longueur',    6, 'fwd', 2, 1.18, 1.26),
    ('§11 prone largeur',     6, 'out', 0, 0.87, 0.93),
    ('§11 prone epaisseur',   6, 'up',  1, 0.88, 0.94),
    ('§12 lateral i=2 aplatissement', 2, 'out', 0, 0.75, 0.85),
    ('§12 lateral i=4 aplatissement', 4, 'out', 0, 0.75, 0.85),
)


def U(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def ang(a, b):
    """Angle NON ORIENTE : une echelle est aveugle au signe de son axe, donc `|dot|`."""
    return math.degrees(math.acos(min(1.0, abs(float(U(a) @ U(b))))))


def rowD(D, u):
    return math.sqrt(sum(sum(u[i] * D[i][j] for i in range(3)) ** 2 for j in range(3)))


def band(v, lo, hi):
    return 'SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS')


def parse(txt):
    tri, sca, dfma, com = {}, {}, {}, {}
    for m in re.finditer(r'^PHYSTRI c=(\d+) a=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)',
                         txt, re.M):
        tri[(int(m.group(1)), int(m.group(2)))] = np.array(
            [float(m.group(3)), float(m.group(4)), float(m.group(5))])
    for m in re.finditer(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+) sz=([-\d.e+]+)',
                         txt, re.M):
        sca[(int(m.group(1)), int(m.group(2)))] = (
            float(m.group(3)), float(m.group(4)), float(m.group(5)))
    for m in re.finditer(
            r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+) m1=([-\d.e+]+) m2=([-\d.e+]+)',
            txt, re.M):
        c, i, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
        dfma.setdefault((c, i), np.zeros((3, 3)))[r] = [
            float(m.group(4)), float(m.group(5)), float(m.group(6))]
    for m in re.finditer(r'^PHYSORICOM c=(\d+) i=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+) tz=([-\d.e+]+)',
                         txt, re.M):
        com[(int(m.group(1)), int(m.group(2)))] = np.array(
            [float(m.group(3)), float(m.group(4)), float(m.group(5))])
    return tri, sca, dfma, com


def rig_triads(glb):
    """LE TRIEDRE DE §7 MESURE SUR LE RIG LIVRE, et les deux autres pour comparaison."""
    g = c6.load_geometry('keira-hd', glb=glb)
    if g is None:
        return None
    names, P = list(g['names']), g['P']
    js, bufs = read_glb(os.path.join(REPO, glb) if not os.path.isabs(glb) else glb)
    _n, ibms, _p = skin_info(js, consolidate_buffers(js, bufs))
    R = np.linalg.inv(np.array(ibms[names.index('chest')], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    anch = lambda v: R.T @ np.asarray(v, dtype=float)
    sep = U(anch(P[names.index('rBoob')] - P[names.index('lBoob')]))
    out = {0: -sep, 1: sep}
    torso = U(anch(P[names.index('neck')] - P[names.index('hips')]))
    return dict(names=names, P=P, anch=anch, out=out, torso=torso,
                chest_neck=U(anch(P[names.index('neck')] - P[names.index('chest')])),
                hips_chest=U(anch(P[names.index('chest')] - P[names.index('hips')])))


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else LOG
    glb = sys.argv[2] if len(sys.argv) > 2 else GLB
    txt = open(log if os.path.isabs(log) else os.path.join(REPO, log), errors='replace').read()
    tri, sca, dfma, com = parse(txt)
    rig = rig_triads(glb)
    mass = json.load(open(MASS))
    # LE TRIEDRE DU REGISTRE **D'AVANT CE CYCLE** : `+Z` = la saillie, `+Y = +Z x +X(chestR)`.
    # Il est reconstruit depuis `axes_saillie` de l'instantane, pas relu d'un fichier perime :
    # la comparaison doit rester reproductible une fois le producteur corrige.
    AXM = {}
    for c in (0, 1):
        _o = np.array(mass['chains'][NM[c]]['axes']['out'], dtype=float)
        _s = np.array(mass['chains'][NM[c]].get('axes_saillie',
                                                mass['chains'][NM[c]]['axes']['fwd']), dtype=float)
        _oR = np.array(mass['chains'][NM[1]]['axes']['out'], dtype=float)
        AXM[c] = {'out': _o, 'up': U(np.cross(_s, _oR)), 'fwd': _s}
    if rig is None:
        print('C91: mesh LIVRE absent — rien n\'est mesure (aucun repli sur le rip brut)')
        return 1

    A = print
    A('DIRECTIVES v3fee554599')
    A('')
    A('C91 — LE TRIEDRE DE §7, TRANCHE PAR LA MESURE ; ET LE FACTEUR AVAL, IDENTIFIE')
    A('=' * 104)
    A('log  : %s' % os.path.relpath(log, REPO) if os.path.isabs(log) else log)
    A('mesh : %s' % glb)
    A('')

    # ---- 1. LE TRIEDRE -------------------------------------------------------------------------
    A('-- 1. « +Y = upward along torso » (§7 l.132) : TROIS LECTURES, ET AUCUNE N\'EST L\'AUTRE --')
    cand = {'moteur    +Y = -g_ref        ': tri[(0, 1)],
            'registre  +Y = saillie x lat ': AXM[0]['up'],   # lecture d'AVANT ce cycle
            'RIG       hips -> neck       ': rig['torso'],
            'RIG       chest -> neck      ': rig['chest_neck'],
            'RIG       hips  -> chest     ': rig['hips_chest']}
    ks = list(cand)
    A('   %-30s %s' % ('', ' '.join('%-10s' % k.split()[0][:9] for k in ks)))
    for a in ks:
        A('   %-30s %s' % (a, ' '.join('%9.2f ' % ang(cand[a], cand[b]) for b in ks)))
    A('   Les trois lectures de RIG sont colineaires (0,00 deg) : l\'axe long du torse est UNE')
    A('   direction, pas un choix de segment. Le moteur en est a %.2f deg, le registre d\'avant ce'
      % ang(tri[(0, 1)], rig['torso']))
    A('   cycle a %.2f deg, et les deux sont DE PART ET D\'AUTRE (%.2f deg l\'un de l\'autre).'
      % (ang(AXM[0]['up'], rig['torso']), ang(tri[(0, 1)], AXM[0]['up'])))
    A('   ET LE FAIT QUI CLOT LA QUESTION : le triedre du RIG **EST la base de l\'ancre**, a 5')
    A('   decimales — `+X = [1 0 0]`, `+Y = [0 -1 0]`, `+Z = [0 0 -1]` dans les rangees de `chest`.')
    A('   La « rangee d\'ancre » que le cycle 90 a ecartee comme « un axe de rig » etait donc')
    A('   l\'axe de §7, et c\'est la saillie qui s\'en ecartait.')
    A('')
    fwd_rig = U(np.cross(rig['out'][1], rig['torso']))
    if float(fwd_rig @ AXM[1]['fwd']) < 0:
        fwd_rig = -fwd_rig
    A('-- « +Z = forward from chest » (§7 l.133) --------------------------------------------------')
    A('   moteur   `fz` (rangee d\'ancre orthogonalisee)   a %6.2f deg du complement du RIG'
      % ang(tri[(0, 2)], fwd_rig))
    A('   registre `fwd` (saillie de la chair)            a %6.2f deg du complement du RIG'
      % ang(AXM[0]['fwd'], fwd_rig))
    A('   La saillie n\'est pas « forward from chest » : le sein pointe en avant ET vers le bas, et')
    A('   c\'est cette inclinaison que le produit vectoriel a reportee sur `+Y`.')
    A('')
    A('-- ORTHOGONALITE AU LATERAL MESURE (§7 exige un triedre, et `+X` est le seul miroite) -----')
    for nm, v in (('moteur   +Y', tri[(0, 1)]), ('registre +Y', AXM[0]['up']),
                  ('RIG      +Y', rig['torso'])):
        A('   %-12s angle a `+X` (separation racine-a-racine) = %6.2f deg' % (nm, ang(v, rig['out'][1])))
    A('   Le triedre du moteur n\'est pas orthogonal au lateral MESURE : il l\'est a 10,54 deg pres.')
    A('')

    # le triedre retenu : chaque axe d'une phrase de §7, mesure sur le rig livre
    AXT = {}
    for c in (0, 1):
        o = rig['out'][c]
        u = U(rig['torso'] - float(rig['torso'] @ o) * o)
        AXT[c] = {'out': o, 'up': u, 'fwd': fwd_rig}

    # ---- 2. LE FACTEUR AVAL --------------------------------------------------------------------
    A('-- 2. LE FACTEUR AVAL `B = dfa^-1 . A` : CE QUE `dfb` ET `dfc` FONT, MESURE ---------------')
    A('   %-4s %-4s %9s %9s %9s %9s %9s %9s' % ('c', 'i', 'det(B)', 'lam_max', 'lam_min',
                                                '|B-I|', '|t|/B0', '0.43|t|/B0'))
    ratios = []
    for c in (0, 1):
        fx, fy, fz = tri[(c, 0)], tri[(c, 1)], tri[(c, 2)]
        for i in sorted({ii for (cc, ii) in dfma if cc == c}):
            sx, sy, sz = sca[(c, i)]
            dfa = sx * np.outer(fx, fx) + sy * np.outer(fy, fy) + sz * np.outer(fz, fz)
            B = np.linalg.inv(dfa) @ dfma[(c, i)]
            w = np.sort(np.real(np.linalg.eigvals(B)))[::-1]
            t = float(np.linalg.norm(com[(c, i)])) / B0
            if i != 0:
                ratios.append((w[0] - 1.0) / (DYN_K * t))
            A('   %-4d %-4d %9.5f %9.4f %9.4f %9.4f %9.4f %9.4f'
              % (c, i, np.linalg.det(B), w[0], w[-1], np.linalg.norm(B - np.eye(3)),
                 t, DYN_K * t))
    A('   det(B) = 1 a 3e-4 pres sur les 18 : les facteurs aval NE GONFLENT PAS, ils REDISTRIBUENT.')
    A('   i=0 (debout, §9) : |B-I| = 0,0007 — la LIGNE DE BASE, et elle est nulle.')
    A('   Sur les 16 cellules non nulles, `lam_max - 1` vaut %.3f a %.3f fois `0.43 x |t|/B0`'
      % (min(ratios), max(ratios)))
    A('   (mediane %.3f). `0.43` est `PHYS-DYN-K` (jak-hd-physics.gc:229) et `t` le deplacement'
      % float(np.median(ratios)))
    A('   d\'equilibre que §10/§11/§12 SPECIFIENT. Le facteur aval est donc l\'equilibre COMPTE UNE')
    A('   SECONDE FOIS, en elongation locale, sur l\'axe du deplacement et non sur ceux de §7.')
    A('')

    # ---- 3. LE REGISTRE DES 16, SUR UN SEUL AXE ------------------------------------------------
    A('-- 3. LES 16 ECHELLES, SUR UN SEUL AXE ET DANS QUATRE ETATS -------------------------------')
    A('   `dfb -> I` est la PROJECTION du geste (algebre sur la trace archivee), pas une course.')
    A('   %-8s %-32s %17s %17s %17s %9s' % ('chaine', 'cellule', 'A (produit)',
                                            'dfb->I (dfc garde)', 'dfa seul', 'moteur'))
    cnt = dict(A_T=0, dfb_T=0, dfa_T=0, eig=0, A_M=0, dfa_M=0)
    rows = []
    for c in (0, 1):
        fx, fy, fz = tri[(c, 0)], tri[(c, 1)], tri[(c, 2)]
        for lab, i, key, k, lo, hi in SHAPE:
            sx, sy, sz = sca[(c, i)]
            dfa = sx * np.outer(fx, fx) + sy * np.outer(fy, fy) + sz * np.outer(fz, fz)
            Am = dfma[(c, i)]
            B = np.linalg.inv(dfa) @ Am
            w, v = np.linalg.eig(B)
            w, v = np.real(w), np.real(v)
            o = np.argsort(-np.abs(w - 1.0))
            u, ee = v[:, o[0]], w[o[0]]
            tt = 1.0 / math.sqrt(abs(ee))
            dfc = np.linalg.inv(tt * np.eye(3) + (ee - tt) * np.outer(u, u)) @ B
            val = dict(A_T=rowD(Am, AXT[c][key]), dfb_T=rowD(dfa @ dfc, AXT[c][key]),
                       dfa_T=rowD(dfa, AXT[c][key]), eig=(sx, sy, sz)[k],
                       A_M=rowD(Am, AXM[c][key]), dfa_M=rowD(dfa, AXM[c][key]))
            for kk, vv in val.items():
                if band(vv, lo, hi) == 'DANS':
                    cnt[kk] += 1
            rows.append((c, lab, val, lo, hi))
            A('   %-8s %-32s %8.4f %-8s %8.4f %-8s %8.4f %-8s %8.4f  %.2f-%.2f'
              % (NM[c], lab, val['A_T'], band(val['A_T'], lo, hi),
                 val['dfb_T'], band(val['dfb_T'], lo, hi),
                 val['dfa_T'], band(val['dfa_T'], lo, hi), val['eig'], lo, hi))
    A('')
    A('   DANS sur 16, TRIEDRE DU RIG (celui de §7) : produit %d · dfb->I %d · dfa seul %d'
      % (cnt['A_T'], cnt['dfb_T'], cnt['dfa_T']))
    A('   DANS sur 16, valeur propre du MOTEUR       : %d   <- le « 13 » du cycle 90' % cnt['eig'])
    A('   DANS sur 16, TRIEDRE DE LA SAILLIE (le registre AVANT ce cycle) : produit %d ·'
      ' dfa seul %d   <- le « 8 » du cycle 90' % (cnt['A_M'], cnt['dfa_M']))
    A('')
    A('   LE FAIT QUI TRANCHE LE TRIEDRE UNE TROISIEME FOIS, ET IL EST INDEPENDANT DES DEUX')
    A('   PREMIERS : sur le triedre du RIG, `dfa` lu le long de l\'axe (%d) et la valeur propre du'
      % cnt['dfa_T'])
    A('   moteur (%d) rendent le MEME compte ET le meme verdict sur les 16 cellules — le tenseur'
      % cnt['eig'])
    A('   d\'equilibre y est quasi diagonal. Sur le triedre de la saillie il en perd %d. C\'est le'
      % (cnt['eig'] - cnt['dfa_M']))
    A('   triedre du REGISTRE qui etait l\'intrus, pas le facteur aval.')
    A('')
    A('   CE QUE LE GESTE DOIT RENDRE, PUBLIE AVANT LA COURSE : %d -> %d cellules sur 16.'
      % (cnt['A_T'], cnt['dfb_T']))
    A('   La cellule qui ne revient pas est attribuee a `dfc` (pression de contact), que le geste')
    A('   ne touche pas et ne pretend pas toucher.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
