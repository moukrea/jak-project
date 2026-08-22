#!/usr/bin/env python3
"""c90_spec12.py — SPEC 12 (gravite laterale) : SES TROIS CLAUSES, CHACUNE SUR SON PROPRE SEIN.

DIRECTIVES v3fee554599.  ZERO course neuve, ZERO ligne de moteur : trace ARCHIVEE + mesh LIVRE.

LE TEXTE, CITE VERBATIM (`SPEC-breast-softbody.md` l.186-196) :

    The breasts shall not behave identically. The gravity-side breast experiences stronger
    thoracic compression, while the opposite breast migrates across the chest.

        Global lateral COM response:            15-24% B0, nominal 19%
        Upper/opposite breast medial migration: 10-18% W0, nominal 14%
        Gravity-side lateral flattening:        -15 to -25%, nominal -20%

CE QUE PERSONNE N'AVAIT FAIT, ET C'EST LA PREMIERE PHRASE DE LA SECTION.  **Deux de ses trois
clauses ne s'appliquent PAS aux deux seins.**  « Upper/opposite » nomme le sein du HAUT ;
« Gravity-side » nomme celui du BAS.  L'instrument existant lit les deux clauses sur LES DEUX
chaines et aux DEUX poles — quatre cellules la ou la spec en designe une seule par pole.  Un
verdict pris sur une cellule que la clause n'adresse pas ne vaut rien, dans un sens comme dans
l'autre.

LE ROLE EST DERIVE DE LA GRAVITE MESUREE, PAS CHOISI.  `PHYSORI4 r0` est la gravite projetee sur
la ligne LATERALE de l'ancre (rlat=0, donc `e0`).  Le sortant de chaque chaine est mesure sur le
rig livre (`+e0` pour chestL, `-e0` pour chestR, exactement opposes).  Une chaine est du COTE DE
LA GRAVITE quand `dot(g, sortant) > 0`, et c'est tout : aucune etiquette, aucune constante.

LES TROIS QUESTIONS (SPEC 7) :
  NATURE  des LONGUEURS SIGNEES (projections d'un deplacement soutenu) en B0 et en % W0, et un
          RAPPORT D'ECHELLE sans unite pour l'aplatissement.  Jamais une norme sur une clause
          directionnelle.
  REPERE  la base de l'ANCRE (e0,e1,e2), celle de `PHYSORICOML` et de `PHYSDFMA`.
  ABSENT  i=0 (debout) : les trois grandeurs y valent zero et l'echelle y vaut 1 — publie.

« GLOBAL LATERAL COM RESPONSE » EST AMBIGUE, DONC LES TROIS LECTURES SONT PUBLIEES.  Le mot
« global » peut designer (A) la reponse laterale de CHAQUE sein, (B) leur moyenne au pole, (C) la
norme du deplacement de chaque sein.  Aucune ne se choisit par gout : les trois sont calculees et
le verdict n'est prononce QUE si elles s'accordent.  C'est la seule facon honnete de traiter une
ligne de spec qui se lit de plusieurs facons ([[feedback_spec_line_quoted_from_memory]]).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_oricom_exact as P

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B0 = 602.0
CUTS = P.CUTS
CH = P.CH
POLES = (2, 4)          # les deux poles lateraux, designes par la gravite (voir ROOM-ORIROLE)
BAND_GLOB = (0.15, 0.24)        # B0
BAND_MED = (10.0, 18.0)         # % W0
BAND_FLAT = (0.75, 0.85)        # -15 a -25 %  ->  echelle 0.85 a 0.75


def main():
    import json
    log = sys.argv[1] if len(sys.argv) > 1 else P.LOG
    glb = sys.argv[2] if len(sys.argv) > 2 else P.GLB
    txt = open(os.path.join(REPO, log), 'r', errors='replace').read()
    d = P.parse_extra(txt, P.parse(txt))
    g = P.geometry(glb)
    mass = json.load(open(os.path.join(
        REPO, '.autoport/reports/Grecharged-secondary-motion/breast-com-mass.json')))
    ax = {c: np.array(mass['chains'][CH[c][0]]['axes']['out'], dtype=float) for c in (0, 1)}
    w0 = {c: {dd['cut']: float(dd['W0']) for dd in mass['chains'][CH[c][0]]['defs']}
          for c in (0, 1)}

    A = print
    A('DIRECTIVES v3fee554599')
    A('')
    A('SPEC 12 — GRAVITE LATERALE : CHAQUE CLAUSE SUR LE SEIN QU\'ELLE NOMME')
    A('=' * 104)
    A('log  : %s' % log)
    A('')
    A('-- LE ROLE, DERIVE DE LA GRAVITE MESUREE (`PHYSORI4 r0`) ET DU SORTANT DU RIG ----------')
    role = {}
    for i in POLES:
        gl = d['g'].get((0, i))
        # `PHYSORI` publie (gx,gy,gz) dans le triedre de SPEC 7 ; `PHYSORI4` publie la meme
        # gravite sur les LIGNES de l'ancre. On lit la composante LATERALE de l'ancre, r0.
        g4 = _ori4(txt, 0, i)
        for c in (0, 1):
            # `ax[c]` est +e0 pour chestL, -e0 pour chestR : `dot` se reduit a +/- g4[0].
            dot = float(g4[0] * ax[c][0])
            role[(c, i)] = 'GRAVITE' if dot > 0 else 'OPPOSE'
        A('   i=%d   g_lateral(ancre) = %+.4f   ->   %-8s %-8s · %-8s %-8s'
          % (i, g4[0], CH[0][0], role[(0, i)], CH[1][0], role[(1, i)]))
    A('   « gravity-side » = dot(g, sortant) > 0. Aucune etiquette, aucune constante : le sortant')
    A('   vient du rig livre et la gravite de la trace.')
    A('')

    A('-- CLAUSE 2 : « Upper/opposite breast medial migration: 10-18%% W0 » -------------------')
    A('   Elle ne s\'applique QU\'AU SEIN OPPOSE. Les cellules du sein du bas sont publiees en')
    A('   DIAGNOSTIC, sans bande : la clause ne les adresse pas.')
    A('   %-8s %-4s %-9s %9s %9s %9s   %s'
      % ('chaine', 'i', 'role', 'w>0', 'w>=0.05', 'w>=0.25', 'verdict'))
    med_verdicts = {}
    for c in (0, 1):
        for i in POLES:
            vals = [_proj(d, g, c, i, cut, ax[c]) / w0[c][cut] * -100.0 for cut in CUTS]
            r = role[(c, i)]
            if r != 'OPPOSE':
                A('   %-8s %-4d %-9s %9.3f %9.3f %9.3f   DIAGNOSTIC — la clause ne le nomme pas'
                  % (CH[c][0], i, r, *vals))
                continue
            vd = sorted({_band(v, *BAND_MED) for v in vals})
            med_verdicts[c] = (vals, vd)
            A('   %-8s %-4d %-9s %9.3f %9.3f %9.3f   %s'
              % (CH[c][0], i, r, *vals, '/'.join(vd)))
    A('')

    A('-- CLAUSE 1 : « Global lateral COM response: 15-24%% B0 » — TROIS LECTURES -------------')
    lat = {}
    for c in (0, 1):
        for i in POLES:
            lat[(c, i)] = [_proj(d, g, c, i, cut, ax[c]) / B0 for cut in CUTS]
    A('   (A) par sein, composante LATERALE signee sur son propre sortant, en B0')
    for c in (0, 1):
        for i in POLES:
            v = lat[(c, i)]
            A('       %-8s i=%d  %+8.4f %+8.4f %+8.4f   |.| -> %s'
              % (CH[c][0], i, *v, '/'.join(sorted({_band(abs(x), *BAND_GLOB) for x in v}))))
    A('   (B) par POLE, moyenne des deux seins ramenee dans la base commune e0 (le sortant de')
    A('       chestR est -e0 : on le retourne pour additionner deux composantes du MEME axe)')
    for i in POLES:
        v = [(lat[(0, i)][k] - lat[(1, i)][k]) / 2.0 for k in range(3)]
        A('       pole i=%d      %+8.4f %+8.4f %+8.4f   |.| -> %s'
          % (i, *v, '/'.join(sorted({_band(abs(x), *BAND_GLOB) for x in v}))))
    A('   (C) par sein, NORME du deplacement complet, en B0')
    for c in (0, 1):
        for i in POLES:
            v = [_norm(d, g, c, i, cut) / B0 for cut in CUTS]
            A('       %-8s i=%d  %8.4f %8.4f %8.4f   -> %s'
              % (CH[c][0], i, *v, '/'.join(sorted({_band(x, *BAND_GLOB) for x in v}))))
    A('')
    A('-- CLAUSE 3 : « Gravity-side lateral flattening: -15 to -25%% » ------------------------')
    A('   Echelle laterale du tenseur COMPLET (|D.e_x|), donc ce que la PEAU recoit. Bande')
    A('   0.75-0.85. Elle ne s\'applique QU\'AU SEIN DU COTE DE LA GRAVITE.')
    for c in (0, 1):
        for i in POLES:
            D = d['dfma'].get((c, i))
            if D is None:
                continue
            sx = float(np.linalg.norm(D @ ax[c]))
            r = role[(c, i)]
            A('   %-8s i=%d %-9s echelle laterale %.4f   %s'
              % (CH[c][0], i, r, sx,
                 _band(sx, *BAND_FLAT) if r == 'GRAVITE'
                 else 'DIAGNOSTIC — la clause ne le nomme pas'))
    return 0


def _ori4(txt, c, i):
    import re
    m = re.search(r'^PHYSORI4 c=%d i=%d r0=([-\d.e+]+) r1=([-\d.e+]+) r2=([-\d.e+]+)' % (c, i),
                  txt, re.M)
    return np.array([float(m.group(1)), float(m.group(2)), float(m.group(3))]) if m else \
        np.zeros(3)


def _vec(d, g, c, i, cut):
    gc = g[c][cut]
    d0 = d['ldb'][(c, i, 0)]
    d1 = d0 + d['ldb'][(c, i, 1)]
    sk = (gc['W'][0] * d0 + gc['W'][1] * d1) / gc['n']
    tn = (d['dfma'][(c, i)] - np.eye(3)) @ gc['L'] / gc['n']
    return sk + tn


def _proj(d, g, c, i, cut, u):
    return float(_vec(d, g, c, i, cut) @ u)


def _norm(d, g, c, i, cut):
    return float(np.linalg.norm(_vec(d, g, c, i, cut)))


def _band(v, lo, hi):
    return 'SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS')


if __name__ == '__main__':
    sys.exit(main())
