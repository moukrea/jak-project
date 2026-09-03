#!/usr/bin/env python3
"""c114_ladder.py — L'ECHELLE A VARIABLE UNIQUE DE `HardMaxApexDisplacement`.

DIRECTIVES vd9e8b66782 · phase Grecharged-secondary-motion · poitrine de Keira seule.

CE QU'IL COMPARE. Plusieurs courses de la MEME salle, dont les fichiers de chaines ne different
que par la ligne `pk HardMaxApexDisplacement` (verifie par `diff` avant les courses : 2 lignes sur
380). Chaque barreau publie les memes grandeurs, cote a cote, avec le barreau de reference.

LES GRANDEURS, ET LEUR NATURE / REPERE / LECTURE HORS DEFAUT :
  `ahard`   la valeur LUE par le moteur (PHYSPSETE). Sans dimension (fraction de B0). Repere :
            aucun, c'est un scalaire du fichier. Hors defaut : elle EGALE ce que le fichier porte.
            Si elle ne bouge pas quand le fichier bouge, le canal n'existe pas et rien d'autre
            dans ce tableau n'a de sens.
  `st6`     l'etage 6 du septuplet `PHYSSTGT` : |p_rlk - pose d'auteur| / B0 apres la fermeture de
            frame (cap-e22 + peau). NATURE : une LONGUEUR rapportee a B0 (SPEC 6). REPERE : le
            monde, contre la pose d'AUTEUR de la meme frame. Hors defaut : 0.0000.
  `apex`    `PHYSAPEX apex=` : le deplacement du centroide de la region d'apex, en B0.
  `amp`     `PHYSROW amp=` : le mouvement de pointe par ligne du tableau, unites moteur.
  `twsat`   `PHYSREST2 twsat=` : frames ou la saturation douce de la TORSION (38) a mordu. Un
            COMPTE, cumule. Hors defaut : 0 si la borne ne mord jamais.

CE QU'IL NE DIT PAS : rien sur la conformite de la 22. Il dit si le bouton est branche et dans
quel sens il tourne. L'avancement se lit dans SPEC-COVERAGE.md.
"""
import re
import sys
from collections import defaultdict


def read(path):
    d = {'ahard': {}, 'st6': {}, 'apex': [], 'amp': [], 'twsat': [], 'nrec': 0, 'recs': []}
    with open(path, errors='ignore') as f:
        for ln in f:
            # `[HD-PHYS] PHYSPSETE ...` : le PREMIER « PHYS » est celui de la banniere, pas celui
            # de l'enregistrement. Chercher naivement le premier rendait `PHYS] PHYSPSETE ...`, que
            # le filtre rejetait — et la valeur LUE PAR LE MOTEUR, la seule qui prouve que le
            # bouton a tourne, sortait `nan`. Corrige : on saute le prefixe s'il y en a un.
            ln = ln.replace('[HD-PHYS] ', '').replace('[PHYS-ROOM] ', '')
            i = ln.find('PHYS')
            if i < 0:
                continue
            rec = ln[i:].rstrip('\n')
            if not re.match(r'^PHYS[A-Z0-9-]', rec):
                continue
            if not rec.startswith('PHYSPSET'):
                d['recs'].append(rec)
            m = re.match(r'PHYSPSETE c=(\d+) .*ahard=([-0-9.]+)', rec)
            if m:
                d['ahard'][m.group(1)] = float(m.group(2))
            m = re.match(r'PHYSSTGT tag=(\S+) c=(\d+) st=6 jt=([-0-9.]+)', rec)
            if m:
                d['st6'][(m.group(1), m.group(2))] = float(m.group(3))
            m = re.match(r'PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-0-9.]+)', rec)
            if m:
                d['apex'].append(((m.group(1), m.group(2), m.group(3)), float(m.group(4))))
            m = re.match(r'PHYSROW k=(\d+) amp=([-0-9.]+)', rec)
            if m:
                d['amp'].append((m.group(1), float(m.group(2))))
            m = re.match(r'PHYSREST2 a=(\d+) d=(\d+) .*twsat=([-0-9.]+)', rec)
            if m:
                d['twsat'].append(((m.group(1), m.group(2)), float(m.group(3))))
    d['nrec'] = len(d['recs'])
    return d


def p50(v):
    v = sorted(v)
    return v[len(v) // 2] if v else float('nan')


def main():
    if len(sys.argv) < 3 or len(sys.argv) % 2 == 0:
        print('usage: c114_ladder.py <label> <trace> [<label> <trace> ...]  (le 1er = reference)')
        return 2
    args = sys.argv[1:]
    runs = [(args[i], args[i + 1]) for i in range(0, len(args), 2)]
    D = [(lab, read(p), p) for lab, p in runs]
    ref_lab, ref, _ = D[0]

    print('=== BARREAU DE REFERENCE : %s ===' % ref_lab)
    print()
    print('%-10s %-8s %-8s %-10s %-9s %-9s %-9s %-9s' %
          ('barreau', 'ahard_L', 'ahard_R', 'lignes!=', 'apex p50', 'apex max', 'amp p50', 'twsat!=0'))
    for lab, d, _ in D:
        if d['nrec'] != ref['nrec']:
            diff = 'N=%d' % d['nrec']
        else:
            diff = str(sum(1 for a, b in zip(ref['recs'], d['recs']) if a != b))
        av = [v for _, v in d['apex']]
        am = [v for _, v in d['amp']]
        tw = sum(1 for _, v in d['twsat'] if v != 0.0)
        print('%-10s %-8.4f %-8.4f %-10s %-9.4f %-9.4f %-9.2f %-9d' %
              (lab, d['ahard'].get('0', float('nan')), d['ahard'].get('1', float('nan')),
               diff, p50(av), max(av) if av else float('nan'), p50(am), tw))

    print()
    print('--- etage 6 du septuplet, par jambe (PHYSSTGT st=6, longueur / B0, repere monde vs pose d auteur)')
    tags = sorted({t for _, d, _ in D for t in d['st6']})
    hdr = '%-22s' % 'jambe / chaine'
    for lab, _, _ in D:
        hdr += ' %-10s' % lab
    print(hdr)
    for t in tags:
        row = '%-22s' % ('%s c=%s' % t)
        for lab, d, _ in D:
            v = d['st6'].get(t)
            row += ' %-10s' % ('%.4f' % v if v is not None else '—')
        print(row)

    print()
    print('--- ou le mouvement a bouge : PHYSROW amp, par ligne, contre la reference')
    for lab, d, _ in D[1:]:
        ra = dict(ref['amp'])
        up = dn = eq = 0
        worst = (0.0, None)
        for k, v in d['amp']:
            if k not in ra:
                continue
            dv = v - ra[k]
            if dv > 1e-6:
                up += 1
            elif dv < -1e-6:
                dn += 1
            else:
                eq += 1
            if abs(dv) > abs(worst[0]):
                worst = (dv, k)
        print('  %-10s  monte %-4d  baisse %-4d  egales %-4d   ecart max %+0.4f (k=%s)'
              % (lab, up, dn, eq, worst[0], worst[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
