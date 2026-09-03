#!/usr/bin/env python3
"""c126c_named_quantities.py — CHAQUE CLAUSE LUE AVEC L'INSTRUMENT DE SA PROPRE NATURE.

POURQUOI CE FICHIER EXISTE. §10 et §11 sont mesurees depuis le cycle 125 par LA MEME grandeur :
l'ecart-type pondere du nuage de peau le long d'un axe. Or leurs deux clauses ne nomment PAS la
meme nature de grandeur :

  §11 l.179  « Root-to-apex LENGTH: +18 to +26% »        -> une LONGUEUR, invariante par rotation
  §10 l.165  « Forward PROJECTION: -25 to -35% »         -> une SAILLIE le long d'un axe, donc
                                                            une grandeur SIGNEE sur un axe FIXE

Un ecart-type est un troisieme objet : ni l'un ni l'autre. Il sert de proxy aux deux, et le cycle
126 a mesure ce que ce proxy coute sur §11 (10,9 a 17,8 points d'ecart a la longueur nommee).
Ce fichier publie, pour chaque section, LA grandeur que sa clause nomme, a cote du proxy — jamais
a sa place, pour que l'ecart entre les deux reste lisible.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : §11 -> une LONGUEUR (norme d'une difference de centroides) ; §10 -> une SAILLIE
            (projection SIGNEE de cette meme difference sur l'axe `fwd`). Les deux sont sans
            dimension par rapport a la cellule i=0. Aucune n'est une variance de mouvement.
  REPERE  : §11 -> AUCUN (une norme est un invariant euclidien) ; §10 -> le triedre de §7 mesure
            sur le rig, transporte dans la base de l'ANCRE `chest` a CHAQUE cellule. La saillie a
            BESOIN d'un repere : c'est ce qui la distingue de la longueur, et c'est pourquoi elle
            se publie avec lui.
  LIGNE DE BASE : la cellule i=0 (pose debout d'auteur). La 2e cellule debout i=9, que rien ne
            relie a i=0 dans le balayage, donne la LECTURE HORS DEFAUT mesuree.
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
o2 = c124._ori2(txt)
res, cells = c126.run(txt, inject_fwd=1.50)

P = print
P('C126C: §11 nomme une LONGUEUR (invariante par rotation) · §10 nomme une SAILLIE (axe fixe).')
P('C126C: cellules designees par la GRAVITE MESUREE : SUPINE i=%d · PRONE i=%d' % (isup, ipro))
P('C126C: ' + '=' * 110)


DFMA = {}
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
    """|u . D| — l'echelle d'extension le long de `u`. MEME formule que
    physics_room_table.py:3423 : deux implementations d'une meme mesure finissent par diverger."""
    return math.sqrt(sum(sum(u[i] * D[i][j] for i in range(3)) ** 2 for j in range(3)))


def proj(d, i):
    """saillie = |d| . cos(angle(d, fwd)) — la composante SIGNEE le long de `fwd`."""
    return d['Lpp'][i] * math.cos(math.radians(d['ang'][i]))


for sec, cell, lo, hi, nomme in (('11', ipro, 1.18, 1.26, 'LONGUEUR racine->apex'),
                                 ('10', isup, 0.65, 0.75, 'SAILLIE avant (projection)')):
    P('C126C: §%s  cellule i=%d  bande %.2f-%.2f  — grandeur NOMMEE : %s'
      % (sec, cell, lo, hi, nomme))
    P('C126C:   %-8s %-9s | %-9s %-9s | %-9s %-9s | %-9s | %s'
      % ('chaine', 'frontiere', 'COMMANDE', 'APPLIQUE', 'NOMMEE', 'verdict', 'proxy c125',
         'verdict proxy'))
    for cname in c126.CHAINS:
        for lbl in ('w>0.00', 'w>=0.25'):
            d = res[(cname, lbl, 'FULL')]
            cmd = o2.get((list(c126.CHAINS).index(cname), cell))
            cmdv = cmd[2] if cmd else float('nan')
            # L'APPLIQUE SE LIT PAR PROJECTION SUR L'AXE, JAMAIS PAR RANG DE VALEUR SINGULIERE.
            # Apparier « la plus grande valeur singuliere » a `fwd` suppose que le tenseur est
            # aligne sur le triedre. C'est vrai au PRONE (ecart 0,2 %) et FAUX au SUPINE, ou le
            # tenseur porte 1,4 a 3,2 deg de rotation (c126b) : le rang cesse d'y designer l'axe.
            # `_rowD(D, u) = |u . D|` est la meme formule que physics_room_table.py:3423, pour que
            # les deux instruments ne divergent pas.
            applv = _rowD(DFMA[(list(c126.CHAINS).index(cname), cell)], AX[cname]['fwd'])
            val = (d['Lpp'][cell] / d['Lpp'][0]) if sec == '11' \
                else (proj(d, cell) / proj(d, 0))
            prx = d['ext'][cell]['fwd'] / d['ext'][0]['fwd']
            vd = 'SOUS' if val < lo else ('DANS' if val <= hi else 'AU-DESSUS')
            vdp = 'SOUS' if prx < lo else ('DANS' if prx <= hi else 'AU-DESSUS')
            P('C126C:   %-8s %-9s | %-9.4f %-9.4f | %-9.4f %-9s | %-9.4f | %s%s'
              % (cname, lbl, cmdv, applv, val, vd, prx, vdp,
                 '   <<< LE PROXY ET LA GRANDEUR NOMMEE NE DONNENT PAS LE MEME VERDICT'
                 if vd != vdp else ''))
    # LECTURE HORS DEFAUT, mesuree : la 2e cellule DEBOUT.
    for cname in c126.CHAINS:
        d = res[(cname, 'w>0.00', 'FULL')]
        if 9 in d['Lpp']:
            P('C126C:   LECTURE HORS DEFAUT %-8s i=9 (2e cellule DEBOUT) : nommee %.4f'
              ' (cible 1,000, seuil declare 1 %%)'
              % (cname, (d['Lpp'][9] / d['Lpp'][0]) if sec == '11' else (proj(d, 9) / proj(d, 0))))
    P('C126C: ' + '-' * 110)

P('C126C: RENDEMENT LIVRE / APPLIQUE — ce que la PEAU ajoute a ce que le TENSEUR fait :')
for sec, cell, nomme in (('11', ipro, 'elongation'), ('10', isup, 'aplatissement')):
    for cname in c126.CHAINS:
        for lbl in ('w>0.00', 'w>=0.25'):
            d = res[(cname, lbl, 'FULL')]
            applv = _rowD(DFMA[(list(c126.CHAINS).index(cname), cell)], AX[cname]['fwd'])
            val = (d['Lpp'][cell] / d['Lpp'][0]) if sec == '11' \
                else (proj(d, cell) / proj(d, 0))
            P('C126C:   §%s %-8s %-9s  applique %.4f -> livre %.4f   rendement %+.1f %% (%s)'
              % (sec, cname, lbl, applv, val, (val / applv - 1) * 100, nomme))


# ---- LA ROUTE « TOURNER LE BOUTON » MISE A L'EPREUVE SUR LA SECONDE SECTION -------------------
# Le balayage du cycle 126 donne, pour §11, une commande admissible mesuree (lam 1,1060-1,1384) qui
# mettrait ses quatre cellules dans la bande. Avant de la recommander, la MEME compensation se teste
# sur §10 — c'est le contre-controle qu'exige la directive du 2026-08-21 18:40, et le 20:50 montre
# ce que coute de ne pas le faire. Si compenser §10 demande une commande HORS de la bande de §10,
# la route est close, et elle l'est par une mesure et non par une opinion.
P('C126C: ' + '=' * 110)
P('C126C: LA ROUTE « COMPENSER PAR LA COMMANDE », TESTEE SUR LES DEUX SECTIONS :')
for sec, cell, tgt, lo, hi in (('11', ipro, 1.23, 1.18, 1.26), ('10', isup, 0.70, 0.65, 0.75)):
    for cname in c126.CHAINS:
        for lbl in ('w>0.00', 'w>=0.25'):
            d = res[(cname, lbl, 'FULL')]
            applv = _rowD(DFMA[(list(c126.CHAINS).index(cname), cell)], AX[cname]['fwd'])
            val = (d['Lpp'][cell] / d['Lpp'][0]) if sec == '11' else (proj(d, cell) / proj(d, 0))
            y = val / applv                       # rendement mesure de l'etage PEAU
            besoin = tgt / y                      # commande qu'il faudrait pour livrer le nominal
            P('C126C:   §%s %-8s %-9s  rendement peau %.4f  ->  pour LIVRER %.2f il faut COMMANDER'
              ' %.4f   bande de la section %.2f-%.2f  -> %s'
              % (sec, cname, lbl, y, tgt, besoin, lo, hi,
                 'DANS sa bande' if lo <= besoin <= hi else
                 ('HORS BANDE (x%.2f le plafond)' % (besoin / hi) if besoin > hi
                  else 'HORS BANDE (x%.2f le plancher)' % (besoin / lo))))


# ---- TEST DE RAFFINEMENT SUR LA GRANDEUR NOMMEE DE CHAQUE SECTION -----------------------------
# Registre : `instrument-refinement-test`. Le decile qui definit les deux populations est un CHOIX ;
# si le verdict en depend, la mesure ne mesure pas ce qu'elle pretend. Il est refait a 5 %, 10 % et
# 20 %, sur la grandeur NOMMEE de chaque section — donc sur la SAILLIE pour §10, pas sur la
# longueur (c'est la longueur que `Lalt` porte, et elle ne repond pas de §10).
P('C126C: ' + '=' * 110)
P('C126C: TEST DE RAFFINEMENT DU DECILE, SUR LA GRANDEUR NOMMEE (5 % / 10 % / 20 %) :')
for sec, cell, lo, hi in (('11', ipro, 1.18, 1.26), ('10', isup, 0.65, 0.75)):
    for cname in c126.CHAINS:
        for lbl in ('w>0.00', 'w>=0.25'):
            d = res[(cname, lbl, 'FULL')]
            out, verds = [], []
            for q in (0.05, 0.10, 0.20):
                if sec == '11':
                    v = d['Lalt'][q][cell] / d['Lalt'][q][0]
                else:
                    # la SAILLIE au quantile q : |d_q| . cos(angle(d_q, fwd)). L'angle n'est pas
                    # stocke par quantile, donc il est refait ici a partir des memes populations.
                    v = (d['Lalt'][q][cell] / d['Lalt'][q][0]) * (
                        math.cos(math.radians(d['ang'][cell]))
                        / math.cos(math.radians(d['ang'][0])))
                out.append(v)
                verds.append('SOUS' if v < lo else ('DANS' if v <= hi else 'AU-DESSUS'))
            flip = len(set(verds)) > 1
            P('C126C:   §%s %-8s %-9s  %s  ->  %s%s'
              % (sec, cname, lbl, ' · '.join('q=%.2f %.4f' % (q, v)
                                             for q, v in zip((0.05, 0.10, 0.20), out)),
                 ' / '.join(verds),
                 '   <<< LE VERDICT DEPEND DU QUANTILE  (etendue %.1f %%)'
                 % ((max(out) / min(out) - 1) * 100) if flip else ''))
