#!/usr/bin/env python3
"""c125_repro.py — LE BRUIT DE COURSE DE LA FORME LIVREE, ET LES VERDICTS QUI LUI SURVIVENT.

DIRECTIVES vd9e8b66782 · phase Grecharged-secondary-motion · poitrine de Keira seule.

POURQUOI CE FICHIER EXISTE. Le cycle 124 avait ecrit son controle negatif (P5) sous la forme
« la course neuve reproduit la course archivee enregistrement pour enregistrement ». Mesure du
cycle 125 : DEUX COURSES SANS AUCUNE EMISSION NEUVE different deja sur 70 451 enregistrements sur
93 013, soit 75,7 %. Ce controle n'a donc AUCUN CONTRASTE — il ne peut pas distinguer une emission
qui perturbe d'une emission qui ne perturbe rien, et le lire comme un echec serait un FAUX ROUGE.

CE QUI LE REMPLACE, ET C'EST PLUS EXIGEANT. Ce qui doit se reproduire n'est pas la trace, c'est LA
MESURE. On rejoue le MEME calcul de forme livree sur DEUX courses independantes et on publie, par
cellule, l'ecart entre les deux — c'est le BRUIT DE COURSE. Puis on publie, a cote, la MARGE de
chaque cellule au bord de bande le plus proche. Registre, `refutation-must-be-robust-to-its-noise-
floor` : un verdict dont la marge est sous le bruit n'est pas un verdict, c'est un tirage.

NATURE  : deux RAPPORTS sans dimension (cellule d'orientation / cellule debout), compares entre
          deux courses. Ni amplitude, ni variance de mouvement.
REPERE  : celui de `c124_delivered_shape.py`, inchange (triedre de §7 dans la base de l'ancre).
LIGNE DE BASE : l'ecart que l'instrument lit quand RIEN n'a change, c'est-a-dire exactement ce que
          ce fichier mesure. C'est sa raison d'etre.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import c124_delivered_shape as shape

BANDS = shape.BANDS


def margin(v, lo, hi):
    """Combien, EN RELATIF DE v, la valeur doit bouger pour changer de verdict."""
    if v < lo:
        return (lo - v) / v, 'SOUS'
    if v > hi:
        return (v - hi) / v, 'AU-DESSUS'
    return min(v - lo, hi - v) / v, 'DANS'


def main():
    if len(sys.argv) < 3:
        print('usage: c125_repro.py <courseA.log> <courseB.log>')
        return 2
    res = []
    for p in sys.argv[1:3]:
        txt = open(p, 'r', errors='replace').read()
        _l, rows, rc = shape.measure(txt)
        if rc != 0 or not rows:
            print('C125-REPRO: SUSPENDU — la course %s ne rend aucune forme (rc=%d). Aucun bruit'
                  ' n\'est publie : un bruit calcule sur une seule course serait invente.'
                  % (p, rc))
            return 1
        res.append(rows)
    A, B = res
    keys = sorted(set(A) & set(B))
    if len(keys) != 24:
        print('C125-REPRO: ATTENTION — %d cellules communes au lieu de 24.' % len(keys))
    print('C125-REPRO: courses comparees : A=%s  B=%s' % (sys.argv[1], sys.argv[2]))
    print('C125-REPRO: %-8s %-8s §%-3s %-4s | LIVREE A  LIVREE B   ecart %%  | marge %%  verdict'
          % ('chaine', 'frontiere', '', 'axe'))
    dev = []
    rowsout = []
    for k in keys:
        cn, lbl, sec, ax = k
        a, b = A[k][0], B[k][0]
        d = abs(b / a - 1.0)
        dev.append(d)
        lo, hi = BANDS[sec][ax]
        m, vd = margin(a, lo, hi)
        mb, vdb = margin(b, lo, hi)
        rowsout.append((k, a, b, d, m, vd, vdb))
        print('C125-REPRO: %-8s %-8s §%-3s %-4s | %8.4f %8.4f   %7.3f  | %7.3f  %s%s'
              % (cn, lbl, sec, ax, a, b, d * 100.0, m * 100.0, vd,
                 '' if vd == vdb else '   <<< LE VERDICT CHANGE ENTRE LES DEUX COURSES (B=%s)' % vdb))
    dev.sort()
    nmed = dev[len(dev) // 2]
    nmax = dev[-1]
    print('C125-REPRO: ------------------------------------------------------------------')
    print('C125-REPRO: BRUIT DE COURSE, TOUTES CELLULES CONFONDUES : median %.3f %%  max %.3f %%'
          % (nmed * 100.0, nmax * 100.0))
    # ---- LE PLANCHER NE SE TIRE PAS A TRAVERS LA VARIABLE EXPERIMENTALE ----------------------
    # Registre, `floor-drawn-across-the-experimental-variable` : le seuil global ci-dessus est
    # fixe par la cellule la PLUS BRUYANTE, et s'en servir pour disqualifier les cellules d'une
    # AUTRE orientation est la faute exacte que cette entree nomme. §10 est lue dans la cellule
    # SUPINE (i=8), §11 dans la cellule PRONE (i=6) : ce sont deux gestes differents, donc deux
    # populations de bruit. Le plancher est donc PAR SECTION, et les deux sont publies.
    floor = {}
    for sec in ('10', '11'):
        d = [r[3] for r in rowsout if r[0][2] == sec]
        floor[sec] = max(d) if d else 0.0
        print('C125-REPRO: PLANCHER §%s (cellule %s) : max %.3f %%  median %.3f %%  sur %d cellules'
              % (sec, 'SUPINE i=8' if sec == '10' else 'PRONE i=6',
                 max(d) * 100.0, sorted(d)[len(d) // 2] * 100.0, len(d)))
    print('C125-REPRO: RAPPORT DES DEUX PLANCHERS : x%.0f — les deux cellules ne sont PAS de meme'
          ' qualite, et un plancher unique l\'aurait cache.'
          % (max(floor.values()) / max(min(floor.values()), 1e-12)))
    flips = [r for r in rowsout if r[5] != r[6]]
    print('C125-REPRO: verdicts qui CHANGENT entre les deux courses : %d' % len(flips))
    keep = [r for r in rowsout if r[4] > floor[r[0][2]] and r[5] == r[6]]
    print('C125-REPRO: PLANCHER DECLARE : une cellule ne porte un verdict que si sa MARGE depasse'
          ' le bruit MAX DE SA PROPRE SECTION *et* que son verdict ne change pas de course.')
    print('C125-REPRO: cellules qui portent un verdict : %d / %d' % (len(keep), len(rowsout)))
    for r in rowsout:
        f = floor[r[0][2]]
        if r[4] <= f or r[5] != r[6]:
            print('C125-REPRO:   SANS VERDICT  %-8s %-8s §%-3s %-4s  marge %.3f %% / bruit §%s'
                  ' %.3f %%%s'
                  % (r[0][0], r[0][1], r[0][2], r[0][3], r[4] * 100.0, r[0][2], f * 100.0,
                     '  + LE VERDICT CHANGE DE COURSE' if r[5] != r[6] else ''))
    print('C125-REPRO: ------------------------------------------------------------------')
    print('C125-REPRO: CLAUSES HORS BANDE SUR LES DEUX CHAINES ET LES DEUX FRONTIERES,'
          ' ROBUSTES AU BRUIT :')
    for sec in ('10', '11'):
        for ax in ('fwd', 'out', 'up'):
            cells = [r for r in rowsout if r[0][2] == sec and r[0][3] == ax]
            if len(cells) != 4:
                continue
            vds = {r[5] for r in cells}
            rob = all(r[4] > floor[sec] and r[5] == r[6] for r in cells)
            if len(vds) == 1 and vds != {'DANS'} and rob:
                lo, hi = BANDS[sec][ax]
                vals = [r[1] for r in cells]
                print('C125-REPRO:   §%s %-4s  %-9s  livree %.4f a %.4f   bande %.2f-%.2f'
                      '   marge min %.2f %% contre un bruit de %.3f %%'
                      % (sec, ax, vds.pop(), min(vals), max(vals), lo, hi,
                         min(r[4] for r in cells) * 100.0, floor[sec] * 100.0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
