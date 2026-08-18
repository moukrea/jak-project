#!/usr/bin/env python3
"""probe_stock_breast_channels.py — LES ANIMATIONS D'ORIGINE PILOTENT-ELLES SA POITRINE ?

Ce script ne modifie rien. Il lit les glb decompiles des art-groups `assistant*` de jak1 et repond
a une question que la salle declare tranchee et qu'aucune mesure n'a jamais posee aux DONNEES.

POURQUOI IL EXISTE (cycle 30). La salle publie `ROOM-AUTHORED: chains=0` et
`ROOM-AUTHORED-FREE: chestL/chestR frames pilotees=0`, et la gate ANIM du validateur PASSE sur ce
zero. Or `recharged_assets/hd_anim/keira-hd-k2e.json` dit que `lBoob` (k=45) et `rBoob` (k=44) ont
un PILOTE jak1 reel et HOMONYME — `e=78 lBoob`, `e=79 rBoob`, mode 0 (world-delta) depuis le
cycle 24. En mode 0 la pose d'auteur du joint HD vaut `inv(Bind_hd[k]) . Bind_drv[e] . A_drv[e]`
(jak-hd.gc:505) : elle suit le joint DRIVER et NE PASSE PLUS par son parent HD. Si les animations
d'origine font varier le canal local de `lBoob`/`rBoob`, alors :
  * sa SPEC 5 et l'ordre de l'owner du 2026-08-11 donnent la priorite a l'animation sur ces os ;
  * et le ressort de materiau du moteur, qui vise `attache + R_ancre . u_capture . bl`
    (jak-hd-physics.gc:2686, direction relevee UNE fois et gelee), tire vers une pose que
    l'animateur a quittee — un ecart permanent que ni la raideur ni un limiteur ne peut fermer.

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  une VARIATION de canal local : la rotation/translation propre de l'os change-t-elle au
          cours de l'animation ? Un booleen par (animation, os), avec l'amplitude a cote.
  REPERE  le canal LOCAL du joint tel qu'il sort des donnees d'animation (la piste glTF qui vise ce
          noeud), jamais son deplacement monde — SPEC 5 : « un os qui bouge parce que son parent
          bouge n'est PAS pilote par l'animation ».
  ABSENT  aucune piste ne vise l'os, ou la piste existe et ses valeurs sont constantes.
  TEMOIN INTERNE : les memes mesures sur `head`, `neck`, `chest`, dont on sait qu'ils sont animes.
          Si le lecteur les declarait constants, c'est LUI qui serait casse.

USAGE : python3 .autoport/probe_stock_breast_channels.py
"""
import glob
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)

from probe_stock_ear_channels import read_glb, accessor, spread   # noqa: E402

BREAST = ('lBoob', 'rBoob')
WITNESS = ('head', 'neck', 'chest')
EPS = 1e-6


def main():
    paths = sorted(set(glob.glob(os.path.join(REPO, 'decompiler_out/jak1/levels/*/assistant*-lod0.glb'))))
    if not paths:
        print('aucun glb assistant trouve')
        return 1
    print("LES ANIMATIONS D'ORIGINE PILOTENT-ELLES `lBoob` / `rBoob` ?")
    print('NATURE variation de canal LOCAL · REPERE la piste glTF qui vise le noeud · '
          'ABSENT aucune piste, ou piste constante')
    print('TEMOIN head/neck/chest — des os dont on sait qu\'ils sont animes\n')
    rows = []
    tot = 0
    driven = 0
    for p in paths:
        js, bufs = read_glb(p)
        names = [n.get('name', '?') for n in js.get('nodes', [])]
        present = set(names)
        for an in js.get('animations', []):
            tot += 1
            per = {}
            for ch in an.get('channels', []):
                t = ch.get('target', {})
                nd, path = t.get('node'), t.get('path')
                if nd is None or nd >= len(names):
                    continue
                s = spread(accessor(js, bufs, an['samplers'][ch['sampler']]['output']))
                per.setdefault(names[nd], {})[path] = s
            b = {k: (per.get(k, {}) if k in present else None) for k in BREAST}
            w = {k: per.get(k, {}).get('rotation') for k in WITNESS if k in present}
            drv = [k for k, v in b.items()
                   if v is not None and max([x for x in v.values()] or [0.0]) > EPS]
            if drv:
                driven += 1
            rows.append((os.path.basename(p), an.get('name', '?'), b, w, drv))
    for f, aname, b, w, drv in rows:
        bs = []
        for k in BREAST:
            v = b[k]
            if v is None:
                bs.append('%s=ABSENT' % k)
            else:
                bs.append('%s[rot=%s tr=%s]' % (
                    k,
                    '-' if 'rotation' not in v else '%.6f' % v['rotation'],
                    '-' if 'translation' not in v else '%.6f' % v['translation']))
        ws = ' '.join('%s=%s' % (k, ('-' if v is None else '%.6f' % v)) for k, v in w.items())
        print('%-26s %-34s %s  TEMOIN[%s]%s'
              % (f[:26], aname[:34], ' '.join(bs), ws, '  <== PILOTEE' if drv else ''))
    print('')
    print('%d animation(s) lues dans %d art-group(s).' % (tot, len(paths)))
    print('%d animation(s) font varier un canal local de `lBoob` ou `rBoob`.' % driven)
    # L'AMPLITUDE, EN DEGRES — parce qu'un ecart de composante de quaternion ne se compare a rien.
    # C'est ce nombre-la qui dit si l'intention d'auteur est visible et ce que la physique lui prend.
    print('')
    print('AMPLITUDE ANGULAIRE la ou le canal varie (angle entre la rotation locale la plus')
    print('eloignee et la premiere image de la piste) — ABSENT 0.000 deg :')
    def qang(a, b):
        d = abs(float(np.dot(a, b)))
        return 2.0 * np.degrees(np.arccos(min(1.0, max(-1.0, d))))
    for p2 in paths:
        js, bufs = read_glb(p2)
        nm = [n.get('name', '?') for n in js.get('nodes', [])]
        for an in js.get('animations', []):
            for ch in an.get('channels', []):
                t = ch.get('target', {})
                nd = t.get('node')
                if nd is None or nd >= len(nm):
                    continue
                if nm[nd] not in BREAST or t.get('path') != 'rotation':
                    continue
                vals = np.asarray(accessor(js, bufs, an['samplers'][ch['sampler']]['output']),
                                  dtype=float)
                if vals.ndim == 1:
                    vals = vals.reshape(-1, 4)
                ref = vals[0] / np.linalg.norm(vals[0])
                mx = max(qang(ref, v / np.linalg.norm(v)) for v in vals)
                if mx > 0.01:
                    print('  %-36s %-6s %d images  MAX %6.3f deg'
                          % (an.get('name', '?')[:36], nm[nd], len(vals), mx))
    wit = sum(1 for r in rows if any(v is not None and v > EPS for v in r[3].values()))
    print('TEMOIN : %d/%d animations font varier un os de corps connu (head/neck/chest).' % (wit, tot))
    if wit == 0:
        print('LE TEMOIN EST MUET — le lecteur est casse, aucun zero ci-dessus ne vaut rien.')
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
