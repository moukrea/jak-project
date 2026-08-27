#!/usr/bin/env python3
"""c126d_double_count.py — LA DEFORMATION LIVREE EST-ELLE LE PRODUIT DE DEUX ETAGES QUI
COMMANDENT CHACUN LA MEME CHOSE ?

POURQUOI CE FICHIER EXISTE. Le cycle 126 a etabli que la commande et le tenseur APPLIQUE sont dans
la bande sur §10 comme sur §11, et que c'est la PEAU qui en sort : rendement +4,6 a +9,8 % sur
l'elongation de §11, 0,628 a 0,727 sur l'aplatissement de §10. Il a nomme l'etage peau comme
chantier sans dire OU, dedans, l'amplification nait. Ce fichier repond a cette question-la, et il
ne coute ni build ni course.

L'HYPOTHESE, ET ELLE EST FALSIFIABLE. La chaine fait DEUX choses a la fois :
  (a) elle se RECONFIGURE — les joints tournent et se deplacent (etage RIGIDE, S = I) ;
  (b) elle porte un TENSEUR d'etirement `dfa . dfb` applique autour de chaque joint.
La spec, elle, ne demande qu'UN chiffre : « Root-to-apex length +18 to +26% » est la longueur
TOTALE livree, pas la part tensorielle. Si les deux etages se composent, on livre (a) x (b) la ou
la spec demande (b) seul -> c'est un DOUBLE COMPTE, et le correctif n'est pas de rebaisser un
bouton mais de ne commander au tenseur que le RESIDU `cible / rigide`.

    PREDICTION TESTEE ICI : livree / (rigide x applique) = 1,00.
    FALSIFICATEUR : l'ecart a 1 depasse 10 % sur l'une des 8 cellules -> les deux etages ne se
    composent pas multiplicativement, l'hypothese du double compte tombe, et le chantier doit etre
    cherche ailleurs dans l'etage peau.

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : un RAPPORT SANS DIMENSION entre trois grandeurs deja publiees. Aucune mesure neuve.
  REPERE  : celui de chaque grandeur composee — la longueur de §11 n'en a aucun (invariant
            euclidien), la saillie de §10 est dans le triedre de §7 en base d'ancre.
  LIGNE DE BASE : la cellule DEBOUT i=9, que rien ne relie a i=0 dans le balayage. Les trois
            etages y valent 1,000, donc leur produit aussi : c'est la LECTURE HORS DEFAUT, et
            elle est MESUREE ici, pas supposee.
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(os.path.join(REPO, LOG), 'r', errors='replace').read()
isup, ipro, _g = c124._roles(txt)
res, cells = c126.run(txt)

_rw = {}
for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+)'
                     r' m1=([-\d.e+]+) m2=([-\d.e+]+)', txt, re.M):
    _rw.setdefault((int(m.group(1)), int(m.group(2))), {})[int(m.group(3))] = (
        float(m.group(4)), float(m.group(5)), float(m.group(6)))
DFMA = {k: [v[0], v[1], v[2]] for k, v in _rw.items() if len(v) == 3}
_mass = json.load(open(os.path.join(REPO, c126.MASSJSON)))
AX = {cn: {k: [float(x) for x in _mass['chains'][cn]['axes'][k]]
           for k in ('out', 'up', 'fwd')} for cn in c126.CHAINS}


def _rowD(D, u):
    """|u . D| — MEME formule que physics_room_table.py:3423."""
    return math.sqrt(sum(sum(u[i] * D[i][j] for i in range(3)) ** 2 for j in range(3)))


def grandeur(d, sec, i):
    """la grandeur NOMMEE par la section : longueur pour §11, saillie pour §10."""
    if sec == '11':
        return d['Lpp'][i]
    return d['Lpp'][i] * math.cos(math.radians(d['ang'][i]))


P = print
P('C126D: la chaine fait DEUX choses : elle se RECONFIGURE (rigide) et elle porte un TENSEUR.')
P('C126D: la spec ne demande qu\'UN chiffre. Test : livree = rigide x applique ?')
P('C126D: ' + '=' * 112)
P('C126D: %-4s %-8s %-9s | %-9s %-9s %-9s | %-9s | %-8s'
  % ('sec', 'chaine', 'frontiere', 'RIGIDE', 'APPLIQUE', 'produit', 'LIVREE', 'livree/produit'))
bad = []
for sec, cell in (('11', ipro), ('10', isup)):
    for cname in c126.CHAINS:
        ci = list(c126.CHAINS).index(cname)
        for lbl in ('w>0.00', 'w>=0.25'):
            dF = res[(cname, lbl, 'FULL')]
            dR = res[(cname, lbl, 'RIGID')]
            rig = grandeur(dR, sec, cell) / grandeur(dR, 0, 0) if False else \
                grandeur(dR, sec, cell) / grandeur(dR, sec, 0)
            app = _rowD(DFMA[(ci, cell)], AX[cname]['fwd'])
            liv = grandeur(dF, sec, cell) / grandeur(dF, sec, 0)
            r = liv / (rig * app)
            bad.append((sec, cname, lbl, r))
            P('C126D: §%-3s %-8s %-9s | %-9.4f %-9.4f %-9.4f | %-9.4f | %.4f%s'
              % (sec, cname, lbl, rig, app, rig * app, liv, r,
                 '   <<< ECART > 10 %%' if abs(r - 1) > 0.10 else ''))
P('C126D: ' + '-' * 112)
ec = [abs(r - 1) for _s, _c, _l, r in bad]
P('C126D: ECART A 1 — min %.2f %% · median %.2f %% · max %.2f %%  (falsificateur declare : 10 %%)'
  % (min(ec) * 100, sorted(ec)[len(ec) // 2] * 100, max(ec) * 100))
P('C126D: -> %s' % ('HYPOTHESE TENUE : les deux etages se composent MULTIPLICATIVEMENT, donc la'
                    ' chaine livre (a) x (b) la ou la spec ne demande que (b). DOUBLE COMPTE.'
                    if max(ec) <= 0.10 else
                    'HYPOTHESE REFUTEE : les deux etages ne se composent pas multiplicativement.'))
P('C126D: ' + '-' * 112)
P('C126D: LECTURE HORS DEFAUT — cellule DEBOUT i=9, que rien ne relie a i=0 :')
for sec in ('11', '10'):
    for cname in c126.CHAINS:
        ci = list(c126.CHAINS).index(cname)
        dF, dR = res[(cname, 'w>0.00', 'FULL')], res[(cname, 'w>0.00', 'RIGID')]
        if 9 not in dF['Lpp'] or (ci, 9) not in DFMA:
            continue
        rig = grandeur(dR, sec, 9) / grandeur(dR, sec, 0)
        app = _rowD(DFMA[(ci, 9)], AX[cname]['fwd'])
        liv = grandeur(dF, sec, 9) / grandeur(dF, sec, 0)
        P('C126D:   §%-3s %-8s rigide %.4f · applique %.4f · livree %.4f -> rapport %.4f'
          ' (cible 1,0000)' % (sec, cname, rig, app, liv, liv / (rig * app)))
P('C126D: ' + '=' * 112)
P('C126D: SI L\'HYPOTHESE TIENT, LA CIBLE DU CHANTIER EST CALCULABLE ICI, ET SANS BALAYAGE :')
P('C126D: le tenseur ne doit commander que le RESIDU `cible / rigide`, pas la cible entiere.')
for sec, cell, tgt, lo, hi in (('11', ipro, 1.23, 1.18, 1.26), ('10', isup, 0.70, 0.65, 0.75)):
    for cname in c126.CHAINS:
        for lbl in ('w>0.00', 'w>=0.25'):
            dR = res[(cname, lbl, 'RIGID')]
            rig = grandeur(dR, sec, cell) / grandeur(dR, sec, 0)
            P('C126D:   §%-3s %-8s %-9s  rigide %.4f  ->  le tenseur devrait commander %.4f'
              ' (il commande %.4f aujourd\'hui)'
              % (sec, cname, lbl, rig, tgt / rig,
                 _rowD(DFMA[(list(c126.CHAINS).index(cname), cell)], AX[cname]['fwd'])))
