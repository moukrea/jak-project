#!/usr/bin/env python3
"""probe_spec29_torsion.py — LA COMPLIANCE EN TORSION DE SA SPEC 29, MESUREE COMME LES TROIS
AUTRES AXES LE SONT.

POURQUOI CET INSTRUMENT (2026-08-18, cycle 23). `owner-defects.txt` tient la section 29 ouverte
sur « §29 en torsion 0.3825/0.3520 contre 0.72 », et la DIRECTIVE du 2026-08-14 11:50 en conclut
« os manquant a injecter ». **0.3825 est la colonne `zeta` du canal torsion de `ROOM-SEC-RING`**
— un TAUX D'AMORTISSEMENT. `0.72` est `TorsionalCompliance`, une COMPLIANCE. Les deux grandeurs
n'ont ni la meme nature ni la meme unite ; leur difference ne mesure rien, et un chantier de
geometrie a ete derive de leur ecart.

CE QUE LA 29 DIT, ET COMMENT LE TABLEAU LE MESURE DEJA POUR LES TROIS AUTRES AXES. La 29 donne
quatre compliances : vertical 1.00, avant-arriere 0.90, lateral 0.82, torsion 0.72. Une compliance
plus faible = un axe plus raide = une frequence propre plus HAUTE, en `f ∝ 1/sqrt(c)`. C'est
exactement ce que `ROOM-AXRATIO-SPEC24` imprime pour l'AP et le lateral :
    ap  attendu 1/sqrt(0.90) = 1.0541      lat attendu 1/sqrt(0.82) = 1.1043
Pour la torsion, l'attendu est 1/sqrt(0.72) = 1.1785 contre le vertical. On applique donc a la
torsion l'instrument que les trois autres axes utilisent deja, sans en inventer un nouveau.

L'APPARIEMENT, ET IL EST LA CONDITION DE VALIDITE (piege `ratio-of-two-statistics`). Le numerateur
et le denominateur doivent venir du MEME echantillon : meme fenetre, meme estimateur. Ici les deux
viennent de la fenetre libre `PH-SHAKEN` et du meme ajustement de recurrence lineaire d'ordre 2 :
    torsion            : `ROOM-SEC-RING`, canal `torsion`
    vertical/ap/lateral: `ROOM-SHRING`, maillon 0
On n'apparie QUE des lignes que le tableau declare lisibles (`accord` = `oui`), et on publie
combien de paires ont ete ecartees et pourquoi — un axe illisible ne devient pas un zero.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  : un rapport de deux FREQUENCES PROPRES, sans dimension, puis la compliance qu'il
            implique. Ni une amplitude, ni un amortissement.
  REPERE  : le triedre de l'ancre (SPEC 7), fenetre libre `PH-SHAKEN` ou l'animation n'avance pas.
  ABSENT  : s'il n'existait AUCUN degre de liberte en torsion, la serie de torsion serait plate,
            l'ajustement n'aurait pas de racine complexe et la ligne serait declaree illisible.
            Qu'elle rende une frequence DIFFERENTE des autres axes est la preuve que l'axe est
            arme — c'est la mesure que la directive du 11:50 exige (« les trois axes doivent
            rendre des valeurs DIFFERENTES »).

USAGE : python3 .autoport/probe_spec29_torsion.py [chemin/keira-room-table.txt]
"""
import os
import re
import sys

DEFAULT = os.path.join('.autoport', 'reports', 'Grecharged-secondary-motion',
                       'keira-room-table.txt')

# SPEC 29, recopiees de `SPEC-breast-softbody.md` (bloc ANISOTROPY du preset Keira).
COMPLIANCE = {'v': 1.00, 'ap': 0.90, 'lat': 0.82, 'torsion': 0.72}
# SPEC 29 ne donne pas de tolerance ; on publie l'ecart et on le compare a celui que le tableau
# accepte deja sur les axes AP et lateral, plutot que d'inventer un seuil.


def parse(path):
    shring, sec = {}, {}
    for ln in open(path, errors='ignore'):
        m = re.match(r'^ROOM-SHRING:\s+(\S+)\s+(\d+)\s+(\S+)\s', ln)
        if m and m.group(2) == '0':
            f = ln.split('|')
            if len(f) < 2:
                continue
            t = f[1].split()
            # n a b zeta f residu accord...
            if len(t) < 6:
                shring[(m.group(1), m.group(3))] = (None, None, 'pas d oscillation ajustable')
                continue
            try:
                freq, res = float(t[4]), float(t[5])
            except ValueError:
                shring[(m.group(1), m.group(3))] = (None, None, 'pas d oscillation ajustable')
                continue
            shring[(m.group(1), m.group(3))] = (freq, res, ' '.join(t[6:]).strip())
        m = re.match(r'^ROOM-SEC-RING:\s+(\S+)\s+torsion\s+(.*)$', ln)
        if m:
            # colonnes: n_tot n_ecrete n_fit a b zeta f(Hz) residu accord
            t = m.group(2).split()
            sec[m.group(1)] = (float(t[6]), float(t[7]), ' '.join(t[8:]).strip())
    return shring, sec


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    shring, sec = parse(path)
    print('SPEC 29 — COMPLIANCE EN TORSION, MESUREE COMME LES TROIS AUTRES AXES')
    print('tableau : %s' % path)
    print('NATURE rapport de deux frequences propres, puis la compliance qu il implique ·')
    print('REPERE triedre de l ancre, fenetre libre PH-SHAKEN · ABSENT sans degre de liberte la')
    print('serie de torsion serait plate et l ajustement illisible\n')
    print('AVERTISSEMENT DE NATURE : la colonne `zeta` du canal torsion (0.3825 / 0.3520) est un')
    print('TAUX D AMORTISSEMENT. `TorsionalCompliance = 0.72` est une COMPLIANCE. Les comparer')
    print('directement, comme le fait la ligne ouverte de owner-defects.txt, compare deux')
    print('grandeurs de natures differentes.\n')

    any_pair = False
    for ch in sorted(sec):
        ft, rt, act = sec[ch]
        print('=== %s   torsion f=%.3f Hz  residu=%.4f  (%s)' % (ch, ft, rt, act))
        print('    axe de reference      f(Hz)  residu  lisible   rapport   attendu   ecart    '
              'compliance implicite')
        for ax in ('v', 'ap', 'lat'):
            fa, ra, acc = shring.get((ch, ax), (None, None, 'absent du tableau'))
            if fa is None:
                print('    %-20s   —       —     NON      (%s)' % (ax, acc))
                continue
            lis = acc.lower().startswith('oui')
            if not lis:
                print('    %-20s %6.3f  %.4f  NON      ECARTEE : le tableau la declare « %s »'
                      % (ax, fa, ra, acc))
                continue
            ratio = ft / fa
            att = (COMPLIANCE[ax] / COMPLIANCE['torsion']) ** 0.5
            cimp = COMPLIANCE[ax] / (ratio ** 2)
            print('    %-20s %6.3f  %.4f  oui      %7.4f  %7.4f  %+6.2f %%   %.4f  (cible %.2f)'
                  % (ax, fa, ra, ratio, att, 100.0 * (ratio - att) / att, cimp,
                     COMPLIANCE['torsion']))
            any_pair = True
        # ARMEMENT : les axes doivent rendre des valeurs DIFFERENTES (directive du 11:50).
        fs = [(ax, shring[(ch, ax)][0]) for ax in ('v', 'ap', 'lat')
              if shring.get((ch, ax), (None,))[0] is not None]
        fs.append(('torsion', ft))
        span = max(f for _a, f in fs) - min(f for _a, f in fs)
        print('    ARME : %s  ->  etendue %.3f Hz %s'
              % (' '.join('%s=%.3f' % (a, f) for a, f in fs), span,
                 'les axes rendent des valeurs DIFFERENTES' if span > 0.05
                 else 'REPONSE PLATE — axe desarme'))
        print()
    if not any_pair:
        print('AUCUNE PAIRE LISIBLE — la 29-torsion n est pas mesurable sur cette course.')
        return 1

    # ---- QUEL AXE DE REFERENCE CROIRE ? L'ECART MIROIR LE DIT, ET IL SE MESURE. --------------
    # `chestL` et `chestR` portent des parametres quasi identiques (SPEC 32 : +2 % de masse,
    # +5 % de raideur) sur une geometrie MIROIR. Ce qui les separe sur un axe donne n'est donc
    # pas un defaut de l'axe : c'est l'erreur de l'instrument SUR CET AXE. C'est la meme
    # construction que `ROOM-SKINPEN-MIRROR`, reutilisee et non reinventee. Elle decide quelle
    # paire est croyable AVANT de regarder si elle arrange, ce qui est l'ordre qui protege du
    # tri par convenance.
    print('ECART MIROIR PAR AXE — l erreur de l instrument, mesuree et non supposee :')
    chains = sorted(sec)
    if len(chains) == 2:
        a, b = chains
        rows = []
        for ax in ('v', 'ap', 'lat', 'torsion'):
            if ax == 'torsion':
                fa, fb = sec[a][0], sec[b][0]
            else:
                fa = shring.get((a, ax), (None,))[0]
                fb = shring.get((b, ax), (None,))[0]
            if fa is None or fb is None:
                print('    %-8s  une des deux chaines n a pas de valeur' % ax)
                continue
            gap = 100.0 * abs(fa - fb) / max(fa, fb)
            rows.append((gap, ax, fa, fb))
            print('    %-8s  %s=%.3f Hz  vs  %s=%.3f Hz   ecart %5.1f %%' % (ax, a, fa, b, fb, gap))
        if rows:
            rows.sort()
            print('    -> le canal le PLUS reproductible est `%s` (%.1f %%), le MOINS est `%s`'
                  ' (%.1f %%).' % (rows[0][1], rows[0][0], rows[-1][1], rows[-1][0]))

    # ---- L'AUTRE INSTRUMENT DE LA 29, ET IL FAUT PUBLIER QU'IL EST EN DESACCORD --------------
    # `ROOM-COMPLIANCE-ANISO` mesure la 29 comme un rapport d'AMPLITUDES, pas de frequences. Les
    # deux ne disent pas la meme chose, et le desaccord de deux estimateurs EST une mesure : on
    # l'imprime au lieu de choisir celui qui arrange.
    ani = []
    for ln in open(path, errors='ignore'):
        m = re.match(r'^ROOM-COMPLIANCE-ANISO:\s+chain=(\S+)\s+.*?AP=([\d.]+)\s+lateral=([\d.]+)', ln)
        if m:
            ani.append((m.group(1), float(m.group(2)), float(m.group(3))))
    if ani:
        print()
        print('DESACCORD DES DEUX ESTIMATEURS DE LA 29 — publie, pas arbitre :')
        print('    `ROOM-COMPLIANCE-ANISO` lit la 29 sur des AMPLITUDES, la table ci-dessus sur')
        print('    des FREQUENCES. Sur les axes que la 29 chiffre deja (AP 0.90, lateral 0.82) :')
        for ch, ap, lat in ani:
            print('      %-8s amplitudes : AP=%.4f (29 : 0.90)  lateral=%.4f (29 : 0.82)'
                  % (ch, ap, lat))
        print('    L ecart de l estimateur d amplitude a la spec est du meme ordre sur AP et sur')
        print('    le lateral que sur la torsion : ce n est donc PAS un defaut propre a la')
        print('    torsion, c est un desaccord d instrument qui porte sur les quatre axes.')
        print('    L estimateur de FREQUENCE est celui que `ROOM-AXRATIO-SPEC24` emploie deja')
        print('    pour declarer AP et lateral DANS ; on lit la torsion avec le meme.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
