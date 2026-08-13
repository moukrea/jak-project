#!/usr/bin/env python3
"""Décide si le build publié vaut le temps de l'owner, et le dit en français clair.

L'owner : « dis moi quand j'ai un truc à vérifier ». Un APK part tout seul toutes les ~30 min ;
la quasi-totalité ne change RIEN de ce qu'il peut percevoir. Le signaler à chaque fois, c'est du
bruit, et le bruit finit par se faire ignorer -- donc on ne le prévient que quand une grandeur
qu'il peut VOIR a bougé, et on lui dit laquelle et sur quel défaut ouvert.

Empreinte perceptible = ce qui pilote ce que son oeil reçoit :
  - les paramètres physiques livrés par chaîne (raideur/amortissement/gravité/masse)
  - la couverture de peau du mesh LIVRÉ (la géométrie réellement entraînée)
  - le tag du build (pour qu'il sache quoi tester)

Sortie : une ligne sur stdout SI ça vaut le coup, rien sinon. Silencieux = rien de neuf.
"""
import json, os, re, subprocess, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAMP = os.path.join(ROOT, '.autoport', '.last_owner_notify.json')
CHAINS = os.path.join(ROOT, 'recharged_assets', 'physics_chains.txt')
REPORTS = os.path.join(ROOT, '.autoport', 'reports', 'Grecharged-secondary-motion')
PUSHLOG = os.path.join(ROOT, '.autoport', 'logs', 'auto_push_builds.txt')

# quelle chaîne concerne quel défaut ouvert -- pour lui dire QUOI regarder, pas « va tester »
DEFECT_OF = [
    (r'^(backhair|lmidhair|rmidhair)$',      'hair-anchored-geo', 'les grosses mèches (géométrie figée)'),
    (r'^(lbang|rbang)$',                     'hair-fine-grav',    'les mèches fines'),
    (r'^(backhair|lmidhair|rmidhair|lbang|rbang)$', 'hair-pudding', 'le ballottement des cheveux'),
    (r'pantflap',                            'pant-calf',         'le bas du pantacourt'),
    (r'goggle|visor',                        'goggles-bottom',    'le bas des lunettes'),
    (r'chest|breast|boob',                   'flesh-jelly',       'la poitrine'),
]

PARAMS = ('stiffness', 'damping', 'gravity', 'mass', 'maxangle', 'couple')


def chain_params():
    """Les paramètres livrés, par chaîne. C'est la donnée que le moteur relit à chaud."""
    out = {}
    if not os.path.exists(CHAINS):
        return out
    for line in open(CHAINS, encoding='utf-8', errors='replace'):
        if not line.startswith('chain '):
            continue
        toks = line.split()
        name = toks[1]
        vals = {}
        for t in toks[2:]:
            if '=' in t:
                k, v = t.split('=', 1)
                if k in PARAMS:
                    try:
                        vals[k] = float(v)
                    except ValueError:
                        pass
        out[name] = vals
    return out


def shipped_coverage():
    """Couverture de peau du mesh LIVRÉ -- la mesure la plus récente qui existe."""
    cov = {}
    files = sorted(glob.glob(os.path.join(REPORTS, '**', '*.txt'), recursive=True),
                   key=lambda p: os.path.getmtime(p), reverse=True)
    pat = re.compile(r'ROOM-SKINCOV-SHIPPED:\s+chain=(\S+)\s+cov=([0-9.]+)')
    for f in files[:40]:
        try:
            txt = open(f, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        here = {}
        for m in pat.finditer(txt):
            here[m.group(1)] = float(m.group(2))   # dans un fichier, la DERNIÈRE mesure gagne
        for k, v in here.items():
            cov.setdefault(k, v)                   # entre fichiers, le PLUS RÉCENT gagne
    return cov


def build_tag():
    if not os.path.exists(PUSHLOG):
        return None, None
    last = None
    for line in open(PUSHLOG, encoding='utf-8', errors='replace'):
        if 'PUSHED' in line:
            last = line.strip()
    if not last:
        return None, None
    m = re.search(r'apk=(\S+)', last)
    t = re.match(r'(\d\d:\d\d)', last)
    return (m.group(1) if m else None), (t.group(1) if t else None)


def defects_for(chain):
    hits = []
    for pat, key, human in DEFECT_OF:
        if re.search(pat, chain):
            hits.append((key, human))
    return hits


def main():
    apk, when = build_tag()
    if not apk:
        return 0

    now = {'apk': apk, 'params': chain_params(), 'cov': shipped_coverage()}
    prev = {}
    if os.path.exists(STAMP):
        try:
            prev = json.load(open(STAMP, encoding='utf-8'))
        except (OSError, ValueError):
            prev = {}

    if prev.get('apk') == apk:
        return 0                      # déjà signalé ce build

    if not prev:                      # première pose du jalon : on n'alerte pas, on enregistre
        json.dump(now, open(STAMP, 'w', encoding='utf-8'))
        return 0

    touched = {}                      # défaut -> raisons concrètes et chiffrées

    for name, vals in now['params'].items():
        old = prev.get('params', {}).get(name, {})
        for k, v in vals.items():
            o = old.get(k)
            if o is None or abs(v - o) < 1e-4:
                continue
            for key, human in defects_for(name):
                touched.setdefault(key, {'human': human, 'why': []})
                touched[key]['why'].append(f'{name} {k} {o:g}→{v:g}')

    for name, v in now['cov'].items():
        o = prev.get('cov', {}).get(name)
        if o is None or abs(v - o) < 0.03:      # sous 3 pts, son oeil ne le verra pas
            continue
        for key, human in defects_for(name):
            if key != 'hair-pudding':           # la couverture ne dit rien du ballottement
                touched.setdefault(key, {'human': human, 'why': []})
                touched[key]['why'].append(f'{name} géométrie entraînée {o:.0%}→{v:.0%}')

    json.dump(now, open(STAMP, 'w', encoding='utf-8'))

    if not touched:
        return 0                      # build publié, mais rien de perceptible : on se tait

    zones = sorted({d['human'] for d in touched.values()})
    why = '; '.join(sorted({w for d in touched.values() for w in d['why']})[:4])
    print(f"A TESTER {apk} ({when}) — à regarder : {', '.join(zones)}. Ce qui a bougé : {why}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
