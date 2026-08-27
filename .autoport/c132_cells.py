#!/usr/bin/env python3
"""c132_cells.py — extrait d'un tableau de course les cellules que le lot d'ancrage peut deplacer,
et rien d'autre. Sert a comparer DEUX tableaux sans lire 4 900 lignes a l'oeil.

Ce qu'il sort, et pourquoi celles-la :
  * `ROOM-SPEC1011-LIVREE`  — la LONGUEUR livree a la peau : la clause PORTEUSE de §11, celle qui
    est AU-DESSUS aujourd'hui ; son verdict est rendu sur les DECILES (drapeau LEN_VERDICT_DECILES) ;
  * `ROOM-SPEC10`           — le deplacement de COM de §11 et la migration sortante de §10 ;
  * `DISCRIMINANT`          — recalcule ICI a partir des lignes `row `, parce que la gate vit dans
    le validateur et pas dans le tableau : `(max - min) / max` des `tipvar` par pilotage, seuil 25 %.
    C'est elle qui a arrete les lots des cycles 122 et 128, les deux fois sur chestR ;
  * `ROOM-IDLE`             — la garde de §2/§9 : elle doit rester a 0.000.

Usage : python3 .autoport/c132_cells.py <tableau.txt> [<tableau-reference.txt>]
"""
import collections
import re
import sys

KEYS = ('ROOM-SPEC1011-LIVREE', 'ROOM-SPEC10:', 'ROOM-IDLE', 'ROOM-SPEC11')


def discriminant(path):
    per = collections.defaultdict(dict)
    for ln in open(path, errors='replace'):
        if not ln.startswith('row '):
            continue
        c = re.search(r'chain=(\S+)', ln)
        d = re.search(r'drive=(\S+)', ln)
        t = re.search(r'tipvar=([0-9.]+)', ln)
        if not (c and d and t):
            continue
        k, v = c.group(1), float(t.group(1))
        per[k][d.group(1)] = max(per[k].get(d.group(1), 0.0), v)
    out = {}
    for k, dd in per.items():
        hi, lo = max(dd.values()), min(dd.values())
        out[k] = (100.0 * (hi - lo) / hi, dict(dd))
    return out


def cells(path):
    return [ln.rstrip('\n') for ln in open(path, errors='replace')
            if any(k in ln for k in KEYS)]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    a = sys.argv[1]
    print('=== DISCRIMINANT (recalcule sur les lignes `row `, seuil 25 pct) — %s' % a)
    for k, (sp, dd) in sorted(discriminant(a).items()):
        flag = 'OK' if sp >= 25.0 else '**ECHEC**'
        print('  %-7s spread=%6.2f %%  %s   %s' % (
            k, sp, flag, ' '.join('%s=%.4f' % kv for kv in sorted(dd.items()))))
    if len(sys.argv) > 2:
        b = sys.argv[2]
        print('=== DISCRIMINANT — reference %s' % b)
        for k, (sp, dd) in sorted(discriminant(b).items()):
            print('  %-7s spread=%6.2f %%' % (k, sp))
        ca, cb = cells(a), cells(b)
        print('=== CELLULES §10/§11/IDLE : %d lignes ici, %d dans la reference' % (len(ca), len(cb)))
        sa, sb = set(ca), set(cb)
        print('--- lignes qui ONT CHANGE (presentes ici, absentes de la reference) ---')
        for ln in ca:
            if ln not in sb:
                print('  ' + ln[:220])
    else:
        for ln in cells(a):
            print('  ' + ln[:220])
    return 0


if __name__ == '__main__':
    sys.exit(main())
