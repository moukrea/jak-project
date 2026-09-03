#!/usr/bin/env python3
"""probe_stock_ear_channels.py — LES ANIMATIONS D'ORIGINE PILOTENT-ELLES LES OREILLES DE KEIRA ?

Ce script ne modifie rien. Il lit les glb decompiles des SIX art-groups de Keira et repond a la
question que le tableau de la salle declare lui-meme ne pas pouvoir trancher.

POURQUOI IL EXISTE. `ROOM-AUTHORED-FREE` publie `earL/earR frames pilotees=0`, et publie aussi
l'honnetete de ce zero : « STRUCTUREL, pas controle [...] le controler vraiment demanderait de lire
les canaux des 31 animations dans les donnees d'art-group, pas la course ». C'est exactement ce que
fait ce fichier.

L'ENJEU N'EST PAS COSMETIQUE. `keira-hd-k2e.json` montre que les oreilles HD ont un pilote jak1
REEL (`lEara -> lEar1`, `lEarb -> lEar2`, mode 1 ; `rEara/rEarb -> rEar1/rEar2`, mode 3), la ou les
meches n'en ont aucun (`Lbanga : e=None, tier4 ancestor fallback, would glue to head`). Une oreille
PEUT donc etre pilotee par l'animation d'origine. Deux lectures possibles, opposees :
  * les animations ne touchent jamais ces os -> la physique a la main a juste titre, le zero est vrai ;
  * les animations les touchent -> le detecteur de la salle est aveugle, et nous ECRASONS une
    intention d'auteur, ce que la SPEC 5 interdit. C'est mot pour mot l'inquietude de l'owner :
    « les oreilles, je ne sais pas si c'est la physique ou les animations d'origine ».

LES TROIS QUESTIONS DE LA SPEC 7 :
  NATURE  une VARIATION de canal local : est-ce que la rotation/translation propre de l'os change au
          cours de l'animation ? Ce n'est ni une amplitude ni une distance — c'est un booleen par
          (animation, os), avec l'amplitude publiee a cote pour qu'on puisse juger.
  REPERE  le canal LOCAL du joint tel qu'il sort des donnees d'animation (glTF : la piste qui vise
          ce noeud), jamais son deplacement dans le monde. SPEC 5 : « un os qui bouge parce que son
          parent bouge n'est PAS pilote par l'animation ».
  ABSENT  aucune piste ne vise l'os, ou la piste existe mais ses valeurs sont constantes.

TEMOIN INTERNE (le controle positif que la nature statique du fichier permet) : les memes mesures
sur `head`, `neck`, `chest` — des os dont on sait qu'ils sont animes. Si le lecteur les declarait
constants, c'est le lecteur qui serait casse et aucun de ses zeros ne vaudrait rien.
"""
import base64
import glob
import json
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
EAR = ('lEar1', 'lEar2', 'rEar1', 'rEar2')
WITNESS = ('head', 'neck', 'chest', 'upper_body')
# une piste dont l'amplitude reste sous ce seuil est traitee comme constante (bruit de
# quantification du decompilateur), en unites du canal (quaternion sans dimension, translation en m)
EPS = 1e-6


def read_glb(path):
    """-> (json, [buffer0, buffer1, ...]).

    CE GLB A PLUSIEURS CENTAINES DE BUFFERS, et c'est ce qui a casse la premiere version de ce
    fichier. Seul le buffer 0 vit dans le chunk BIN ; tous les autres sont des `data:` URI. La
    premiere version lisait TOUS les bufferViews dans le chunk BIN : comme les bufferViews
    d'animation ont tous `byteOffset=0`, chaque accesseur relisait les MEMES premiers octets, et la
    mesure rendait le meme triple pour `head`, `chest` et les quatre os d'oreille. Un chiffre
    identique pour une oreille et pour un buste ne mesure rien (SPEC 7 : « une mesure doit
    DISCRIMINER »), et la conclusion qu'il donnait — « les 31 animations pilotent les oreilles » —
    etait fausse. On resout donc CHAQUE buffer, et le temoin interne ci-dessous existe pour que
    cette panne ne puisse pas repasser inapercue."""
    d = open(path, 'rb').read()
    ln = struct.unpack('<I', d[12:16])[0]
    js = json.loads(d[20:20 + ln])
    binc = d[20 + ln + 8:20 + ln + 8 + struct.unpack('<I', d[20 + ln:20 + ln + 4])[0]]
    bufs = []
    for b in js.get('buffers', []):
        uri = b.get('uri')
        if uri is None:
            bufs.append(binc)
        elif uri.startswith('data:'):
            bufs.append(base64.b64decode(uri.split(',', 1)[1]))
        else:
            p = os.path.join(os.path.dirname(path), uri)
            bufs.append(open(p, 'rb').read() if os.path.exists(p) else b'')
    return js, bufs


def accessor(js, bufs, i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    buf = bufs[bv.get('buffer', 0)]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    n = a['count']
    ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    ctype = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}[a['componentType']]
    need = n * ncomp * ctype[1]
    raw = buf[off:off + need]
    if len(raw) < need:
        return []
    vals = struct.unpack('<' + ctype[0] * (n * ncomp), raw)
    return [vals[k * ncomp:(k + 1) * ncomp] for k in range(n)]


def spread(vals):
    """Amplitude max composante par composante — 0 si la piste ne bouge pas."""
    if not vals:
        return 0.0
    ncomp = len(vals[0])
    return max((max(v[c] for v in vals) - min(v[c] for v in vals)) for c in range(ncomp))


def main():
    paths = sorted(set(glob.glob(os.path.join(REPO, 'decompiler_out/jak1/levels/*/assistant*-lod0.glb'))))
    if not paths:
        print('aucun glb assistant trouve')
        return 1
    print('LES ANIMATIONS D\'ORIGINE PILOTENT-ELLES LES OREILLES ?')
    print('NATURE variation de canal LOCAL · REPERE la piste glTF qui vise le noeud · '
          'ABSENT aucune piste, ou piste constante')
    print('')
    tot_anim = 0
    ear_driven = 0
    rows = []
    for p in paths:
        js, bufs = read_glb(p)
        names = [n.get('name', '?') for n in js.get('nodes', [])]
        present = set(names)
        for an in js.get('animations', []):
            tot_anim += 1
            aname = an.get('name', '?')
            # SEPARE PAR CANAL. `rotation` est le canal qui dit « l'animateur a manipule cet os »
            # (SPEC 5). Melanger les trois canaux dans un `max`, comme le faisait la premiere
            # version, laisse la piste la plus bruyante decider pour toutes.
            per = {}
            for ch in an.get('channels', []):
                t = ch.get('target', {})
                nd, path = t.get('node'), t.get('path')
                if nd is None or nd >= len(names):
                    continue
                s = spread(accessor(js, bufs, an['samplers'][ch['sampler']]['output']))
                per.setdefault(names[nd], {})[path] = s
            e = {k: (per.get(k, {}).get('rotation') if k in present else None) for k in EAR}
            w = {k: per.get(k, {}).get('rotation') for k in WITNESS if k in present}
            drv = [k for k, v in e.items() if v is not None and v > EPS]
            if drv:
                ear_driven += 1
            rows.append((os.path.basename(p), aname, e, w, drv))
    for f, aname, e, w, drv in rows:
        es = ' '.join('%s=%s' % (k, ('-' if v is None else '%.6f' % v)) for k, v in e.items())
        ws = ' '.join('%s=%s' % (k, ('-' if v is None else '%.6f' % v)) for k, v in w.items())
        print('%-30s %-30s OREILLES[%s]  TEMOIN[%s]%s'
              % (f[:30], aname[:30], es, ws, '  <== PILOTEE' if drv else ''))
    print('')
    print('%d animation(s) lues dans %d art-group(s).' % (tot_anim, len(paths)))
    print('%d animation(s) font varier la ROTATION d\'au moins un os d\'oreille.' % ear_driven)
    wit = [r for r in rows if any(v is not None and v > EPS for v in r[3].values())]
    print('TEMOIN : %d/%d animations font varier un os de corps connu (head/neck/chest).'
          % (len(wit), len(rows)))
    if not wit:
        print('  AUCUN temoin ne varie => le LECTEUR est casse, aucun zero ci-dessus ne vaut rien.')
        return 1
    # ---- GARDE DE DISCRIMINATION -------------------------------------------------------------
    # La premiere version rendait EXACTEMENT la meme valeur pour une oreille et pour un buste
    # (tous les bufferViews relus au meme endroit). Une mesure qui ne distingue pas deux os
    # differents ne peut rien conclure, et elle avait produit un faux « 31/31 pilotees ».
    # La panne est donc transformee en gate : elle ne peut plus passer inapercue.
    ident = 0
    for f, aname, e, w, drv in rows:
        wv = [v for v in w.values() if v is not None]
        ev = [v for v in e.values() if v is not None]
        if wv and ev and len(set('%.9f' % x for x in wv + ev)) == 1:
            ident += 1
    if ident:
        print('')
        print('MESURE REJETEE : sur %d/%d animations, les oreilles et les temoins rendent la MEME'
              ' valeur au milliardieme.' % (ident, len(rows)))
        print('  Deux os differents ne peuvent pas avoir la meme amplitude par hasard : le lecteur')
        print('  relit le meme buffer. Aucune conclusion ci-dessus ne vaut, ni un zero ni un un.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
