#!/usr/bin/env python3
"""Gcutscene-npc-flicker — agrege les lignes du recensement d'une ou plusieurs courses.

Une ligne NPCFLICK est publiee a la FIN d'une scene ; NPCFLICK-P est un instantane periodique
(une course bornee en temps peut couper une cinematique en cours). Pour chaque (scene, pnj) on
garde la ligne FINALE si elle existe, sinon le dernier instantane — et on dit laquelle.
"""
import re, sys, glob, collections

def kv(line):
    return dict(re.findall(r'(\w+)=([^\s]+)', line))

rows = {}   # (leg, scene, pnj) -> (final?, dict)
for path in sys.argv[1:]:
    leg = 'hd1' if '-hd1-' in path else ('hd0' if '-hd0-' in path else '?')
    for line in open(path, errors='replace'):
        if line.startswith('NPCFLICK ') or line.startswith('NPCFLICK-P '):
            final = line.startswith('NPCFLICK ')
            d = kv(line)
            key = (leg, d.get('scene'), d.get('pnj'))
            prev = rows.get(key)
            if prev is None or (final and not prev[0]) or (final == prev[0]):
                rows[key] = (final, d)

REASONS = ['mort', 'hidden', 'noanim', 'culled', 'supprime', 'modele_absent', 'niveau', 'clone']
# Les causes GATEES : rien dans le jeu n'a demande que l'acteur disparaisse. `culled` (hors du
# frustum, decide par GOAL) et `hidden` (pose explicitement par le jeu) sont publiees et jamais
# gatees — sinon toute cinematique qui coupe d'un cadrage a l'autre passerait au rouge.
DEFAUTS = ['mort', 'noanim', 'supprime', 'modele_absent', 'niveau', 'clone']
tot = collections.Counter()
scenes = collections.defaultdict(set)
print(f"{'jambe':5} {'scene':28} {'pnj':26} {'cyc':>4} {'hd':>2} {'blk':>4} "
      + ' '.join(f'{r[:6]:>7}' for r in REASONS) + f" {'trou':>5} {'img':>6} {'dess':>6} src")
for (leg, scene, pnj), (final, d) in sorted(rows.items()):
    if scene in ('hors-cinematique',):
        continue
    # Format NEUF (il porte `longues=`) : le champ `cycles=` EST deja le compte gate, et
    # `by_reason` compte tous les episodes >= seuil, `longues` comprises — les sommer
    # re-comptabiliserait une absence de 29 s comme un clignotement. Format ANCIEN : on
    # recompose depuis les causes, parce que son `cycles=` incluait `culled`.
    cyc = int(d['cycles']) if 'longues' in d else sum(int(d.get(r, 0)) for r in DEFAUTS)
    scenes[leg].add(scene)
    tot[(leg, 'cycles')] += cyc
    tot[(leg, 'blinks')] += int(d.get('blinks', 0))
    for r in REASONS:
        tot[(leg, r)] += int(d.get(r, 0))
    tot[(leg, 'pnj')] += 1
    print(f"{leg:5} {scene:28} {pnj:26} {cyc:4d} {d.get('hd','?'):>2} {d.get('blinks','?'):>4} "
          + ' '.join(f"{d.get(r,'?'):>7}" for r in REASONS)
          + f" {d.get('trou_max','?'):>5} {d.get('images','?'):>6} {d.get('dessine','?'):>6} "
          + ('fin' if final else 'inst'))
print()
npcok_scenes = set()
npcok_pnj = 0
npcok_cycles = 0
for leg in sorted(scenes):
    print(f"[{leg}] scenes={len(scenes[leg])} pnj_suivis={tot[(leg,'pnj')]} "
          f"cycles_defaut={tot[(leg,'cycles')]} blinks={tot[(leg,'blinks')]} "
          + ' '.join(f"{r}={tot[(leg,r)]}" for r in REASONS))
    print(f"      scenes: {sorted(scenes[leg])}")
    npcok_scenes |= {sc for sc in scenes[leg] if sc != 'flux-non-arme'}
    npcok_pnj += tot[(leg, 'pnj')]
    npcok_cycles += tot[(leg, 'cycles')]
print()
print(f"NPCOK scenes={len(npcok_scenes)} pnj_suivis={npcok_pnj} cycles={npcok_cycles}")
