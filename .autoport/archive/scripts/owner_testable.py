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
    (r'^(backhair|lmidhair|rmidhair)$',      'hair-anchored-geo', 'la nuque et les grosses mèches'),
    (r'^(lbang|rbang)$',                     'hair-fine-grav',    'les mèches fines'),
    (r'^(backhair|lmidhair|rmidhair|lbang|rbang)$', 'hair-pudding', 'le ballottement des cheveux'),
    (r'pantflap',                            'pant-calf',         'le bas du pantacourt'),
    (r'goggle|visor',                        'goggles-bottom',    'le bas des lunettes'),
    (r'chest|breast|boob',                   'flesh-jelly',       'la poitrine'),
]

# `shell` et `radii` pilotent ce que l'owner VOIT autant que la raideur : le correctif du
# pantacourt du 2026-08-13 16:48 etait un `shell=0`, et le declencheur l'a manque -- il a
# annonce les cheveux (revenus a leur valeur d'avant) au lieu du seul vrai changement.
PARAMS = ('stiffness', 'damping', 'gravity', 'mass', 'maxangle', 'couple', 'shell', 'radius')


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


def solver_fingerprint():
    """Empreinte du CODE du solveur, pas seulement de ses reglages.

    2026-08-19 : le build de 21:46 a change le comportement de fond en comble -- la reponse cessait
    d'etre identique quel que soit le mouvement -- et ce declencheur est reste MUET, parce qu'il ne
    regardait que les parametres livres et la couverture de peau. Un correctif dans le solveur ne
    touche aucun des deux. Un declencheur aveugle au code est aveugle a la moitie de ce que
    l'owner peut voir.
    """
    import hashlib
    h = hashlib.sha256()
    for rel in ('goal_src/jak1/pc/jak-hd-physics.gc',):
        try:
            with open(os.path.join(ROOT, rel), 'rb') as f:
                h.update(f.read())
        except OSError:
            return None
    return h.hexdigest()[:12]


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

    now = {'apk': apk, 'params': chain_params(), 'cov': shipped_coverage(),
           'solver': solver_fingerprint()}
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
            # 2026-08-23 : seuil RELATIF, pas absolu. Le 08:44 cette ligne a fait crier
            # « A TESTER » pour un amortissement passant de 0,1753 a 0,1752 — **0,06 %**, tres en
            # dessous de tout ce qu'un oeil peut voir, mais au-dessus d'un seuil absolu de 1e-4.
            # Un ecart perceptible est une FRACTION de la valeur, jamais une quantite fixe :
            # 0,0001 sur un amortissement de 0,17 n'est pas la meme chose que sur un rayon de 655.
            if o is None:
                continue
            if abs(v - o) <= 0.02 * max(abs(o), abs(v), 1e-9):
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

    # LE CODE DU SOLVEUR A CHANGE -- mais l'empreinte ne sait pas distinguer un correctif de
    # COMPORTEMENT d'un ajout de SONDE. Le 2026-08-20 a 00:33 elle a crie « A TESTER » pour un
    # commit qui n'ajoutait que des compteurs de mesure : rien de perceptible. Alerter l'owner
    # a chaque commit d'instrumentation, c'est le dresser a ignorer l'alerte -- exactement ce que
    # ce script existe pour eviter. Le changement de code sort donc sur une ligne VERIF, destinee
    # au superviseur qui lit le diff, et ne declenche JAMAIS a lui seul un « A TESTER ».
    code_changed = bool(now.get('solver') and prev.get('solver')
                        and now['solver'] != prev['solver'])

    json.dump(now, open(STAMP, 'w', encoding='utf-8'))

    if not touched:
        if code_changed:
            print("VERIF %s (%s) — le code du solveur a change sans qu'aucun reglage ne bouge."
                  " Lire le diff : si c'est du COMPORTEMENT, l'annoncer a la main ; si ce sont des"
                  " SONDES, se taire." % (apk, when))
        return 0                      # build publié, mais rien de perceptible : on se tait

    zones = sorted({d['human'] for d in touched.values()})
    why = '; '.join(sorted({w for d in touched.values() for w in d['why']})[:4])
    print(f"A TESTER {apk} ({when}) — à regarder : {', '.join(zones)}. Ce qui a bougé : {why}")
    if code_changed:
        print("  (le code du solveur a aussi change : lire le diff avant de decrire l'effet)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
