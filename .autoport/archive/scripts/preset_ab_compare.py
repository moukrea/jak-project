#!/usr/bin/env python3
"""preset_ab_compare.py — LES DEUX CONTROLES DU CANAL DE PRESET, SUR DES TRACES.

  CONTROLE NEGATIF  (--mode ident)  : le fichier porte les MEMES nombres que les constantes qu'il
      remplace, donc cabler le canal doit etre INERTE. On compare tous les enregistrements `PHYS*`
      des deux courses, sauf les `PHYSPSET*` qui n'existaient pas avant. Une seule ligne differente
      et le cablage n'est pas inerte : il a change le solveur en pretendant ne rien changer.

  CONTROLE POSITIF  (--mode effet)  : on remplace le seul bloc `pk` par celui de MAIA et rien
      d'autre. Le comportement doit changer, DANS LE SENS que ses ecarts prescrivent. Une reponse
      identique voudrait dire que le moteur fait semblant de lire le preset.

Ce que le second compare, `PHYSSHAPE c=<chaine> a=<anim> d=<pilotage> sx= sy= sz=` :
  NATURE  : trois facteurs d'echelle, sans dimension (1.0 = la forme du modele).
  REPERE  : le triedre de la section 7 de l'ancre (X lateral sortant, Y haut du torse, Z avant).
  HORS DEFAUT : les deux courses rendent la meme valeur quand le preset ne change rien.
"""
import argparse
import re
import sys
from collections import defaultdict


def phys_records(path, drop=('PHYSPSET',)):
    out = []
    with open(path, errors='ignore') as f:
        for ln in f:
            ln = ln.rstrip('\n')
            i = ln.find('PHYS')
            if i < 0:
                continue
            rec = ln[i:]
            if not re.match(r'^PHYS[A-Z0-9-]', rec):
                continue
            if any(rec.startswith(d) for d in drop):
                continue
            out.append(rec)
    return out


def shapes(path):
    d = {}
    with open(path, errors='ignore') as f:
        for ln in f:
            m = re.search(r'PHYSSHAPE c=(\d+) a=(\d+) d=(\d+) sx=([-0-9.]+) sy=([-0-9.]+) sz=([-0-9.]+)', ln)
            if m:
                d[(m.group(1), m.group(2), m.group(3))] = tuple(float(m.group(i)) for i in (4, 5, 6))
    return d


def secs(path):
    d = defaultdict(list)
    with open(path, errors='ignore') as f:
        for ln in f:
            m = re.search(r'PHYSSEC c=(\d+) f=\d+ s=([-0-9.]+)', ln)
            if m:
                d[m.group(1)].append(abs(float(m.group(2))))
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('a')
    ap.add_argument('b')
    ap.add_argument('--mode', default='ident', choices=('ident', 'effet'))
    args = ap.parse_args()

    if args.mode == 'ident':
        A, B = phys_records(args.a), phys_records(args.b)
        print('enregistrements PHYS* (hors PHYSPSET) : A=%d  B=%d' % (len(A), len(B)))
        if len(A) != len(B):
            print('DIFFERENT: les deux courses ne publient pas le meme NOMBRE de mesures')
        n = 0
        shown = 0
        for i in range(min(len(A), len(B))):
            if A[i] != B[i]:
                n += 1
                if shown < 8:
                    print('  ligne %d\n    A: %s\n    B: %s' % (i, A[i][:150], B[i][:150]))
                    shown += 1
        print('lignes differentes : %d / %d' % (n, min(len(A), len(B))))
        print('VERDICT: %s' % ('INERTE — le cablage n\'a rien change au solveur'
                               if n == 0 and len(A) == len(B) else
                               'NON INERTE — le cablage a change le solveur'))
        return 0 if (n == 0 and len(A) == len(B)) else 1

    SA, SB = shapes(args.a), shapes(args.b)
    com = sorted(set(SA) & set(SB))
    print('cellules PHYSSHAPE communes : %d (A=%d, B=%d)' % (len(com), len(SA), len(SB)))
    if not com:
        print('AUCUNE cellule commune — rien a comparer')
        return 1
    ident = sum(1 for k in com if SA[k] == SB[k])
    print('cellules IDENTIQUES au bit : %d / %d (%.1f %%)' % (ident, len(com), 100.0 * ident / len(com)))
    for ax, idx in (('sx (lateral)', 0), ('sy (vertical)', 1), ('sz (projection)', 2)):
        dv = [SB[k][idx] - SA[k][idx] for k in com]
        up = sum(1 for x in dv if x > 1e-9)
        dn = sum(1 for x in dv if x < -1e-9)
        mx = max(dv, key=abs) if dv else 0.0
        print('  %-16s  A p50=%.4f  B p50=%.4f  ecart max %+0.5f  (B>A: %d, B<A: %d, egales: %d)'
              % (ax, sorted(SA[k][idx] for k in com)[len(com) // 2],
                 sorted(SB[k][idx] for k in com)[len(com) // 2], mx, up, dn, len(com) - up - dn))
    # --- le balayage d'ORIENTATION, la ou la forme est le plus sollicitee -----------------------
    def dfma(path):
        d = {}
        with open(path, errors='ignore') as f:
            for ln in f:
                m = re.match(r'PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-0-9.]+) m1=([-0-9.]+) m2=([-0-9.]+)', ln)
                if m:
                    d[(m.group(1), m.group(2), m.group(3))] = tuple(float(m.group(i)) for i in (4, 5, 6))
        return d
    DA, DB = dfma(args.a), dfma(args.b)
    ck = sorted(set(DA) & set(DB))
    if ck:
        cells = sorted({(c, i) for c, i, _r in ck})
        chg = 0
        print('PHYSDFMA : %d cellules (chaine, orientation)' % len(cells))
        for c, i in cells:
            da = [DA[(c, i, str(r))][r] for r in range(3) if (c, i, str(r)) in DA]
            db = [DB[(c, i, str(r))][r] for r in range(3) if (c, i, str(r)) in DB]
            if len(da) < 3 or len(db) < 3:
                continue
            if any(abs(x - y) > 1e-6 for x, y in zip(da, db)):
                chg += 1
            print('  c=%s i=%s  diag A (%.4f %.4f %.4f)  B (%.4f %.4f %.4f)  ecart %%'
                  ' (%+.1f %+.1f %+.1f)'
                  % (c, i, da[0], da[1], da[2], db[0], db[1], db[2],
                     100.0 * (db[0] / da[0] - 1.0), 100.0 * (db[1] / da[1] - 1.0),
                     100.0 * (db[2] / da[2] - 1.0)))
        print('  cellules dont la diagonale CHANGE : %d / %d' % (chg, len(cells)))

    QA, QB = secs(args.a), secs(args.b)
    for c in sorted(set(QA) & set(QB)):
        a, b = QA[c], QB[c]
        print('  PHYSSEC c=%s  |s| max A=%.6f  B=%.6f  (x%.3f)  n=%d/%d'
              % (c, max(a), max(b), (max(b) / max(a)) if max(a) > 0 else 0.0, len(a), len(b)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
