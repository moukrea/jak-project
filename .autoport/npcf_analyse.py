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
        # Sur l'appareil, chaque ligne porte le prefixe logcat (`... I GK_STDOUT: `) : on
        # cherche le marqueur PARTOUT dans la ligne, pas seulement en debut.
        i = line.find('NPCFLICK ')
        j = line.find('NPCFLICK-P ')
        if i < 0 and j < 0:
            continue
        if j >= 0 and (i < 0 or j < i):
            line = line[j:]
            final = False
        else:
            line = line[i:]
            final = True
        if True:
            d = kv(line)
            key = (leg, d.get('scene'), d.get('pnj'))
            prev = rows.get(key)
            if prev is None or (final and not prev[0]) or (final == prev[0]):
                rows[key] = (final, d)

REASONS = ['mort', 'hidden', 'noanim', 'culled', 'supprime', 'modele_absent', 'niveau', 'clone',
           'nodraw', 'cull_aveugle', 'matrice_invalide']
# Cycle 3 : `matrice_invalide` = le paquet a ete DESSINE avec des matrices d'os invalides (NaN,
# os a des kilometres, matrice nulle) — rien de visible a l'ecran. L'angle mort « dessine mais
# invisible » des deux premiers cycles. Un journal anterieur au cycle 3 ne porte pas ce champ et
# publie `?`, jamais 0.
# Les causes GATEES : rien dans le jeu n'a demande que l'acteur disparaisse. `culled` et `hidden`
# sont publiees et jamais gatees — sinon toute cinematique qui coupe d'un cadrage a l'autre
# passerait au rouge.
# Gcutscene-npc-flicker-2 : `culled` etait un FOURRE-TOUT non gate qui portait 100 % des episodes
# des sept courses du cycle 1. Il en a ete extrait deux etats qui sont, eux, des defauts :
#   `cull_aveugle` was-drawn a 0 alors qu'un test INDEPENDANT de position dit l'acteur DANS le champ
#   `nodraw`       was-drawn a 1 — GOAL a soumis — et rien n'a ete dessine, sans explication
# `culled` ne garde donc que les episodes ou les DEUX sources de position s'accordent sur
# « hors champ » : c'est ce qui le rend falsifiable au lieu d'etre un residu.
DEFAUTS = ['mort', 'noanim', 'supprime', 'modele_absent', 'niveau', 'clone', 'nodraw',
           'cull_aveugle', 'matrice_invalide']
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
        # UN CHAMP ABSENT N'EST PAS UN ZERO. Les journaux du cycle 1 ne portent ni `nodraw=` ni
        # `cull_aveugle=` : publier 0 pour eux ferait passer « cette course ne pouvait pas le
        # mesurer » pour « cette course a mesure zero ». On compte les lignes qui portent
        # reellement le champ, et l'agregat ecrit `?` quand aucune ne le porte.
        if r in d:
            tot[(leg, r)] += int(d[r])
            tot[(leg, r + '#')] += 1
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
          + ' '.join(f"{r}={tot[(leg,r)] if tot[(leg,r+'#')] else '?'}" for r in REASONS))
    print(f"      scenes: {sorted(scenes[leg])}")
    npcok_scenes |= {sc for sc in scenes[leg] if sc != 'flux-non-arme'}
    npcok_pnj += tot[(leg, 'pnj')]
    npcok_cycles += tot[(leg, 'cycles')]
# Cycle 3 : la PLATEFORME vient des lignes elles-memes (`plateforme=` est ecrit par le code du
# moteur, `ro.product.brand` sur Android, `x86` sur bureau), jamais devinee depuis un nom de
# fichier. L'agregat les liste toutes, et un journal anterieur au cycle 3 rend `?`.
plateformes = sorted({d.get('plateforme', '?') for (_, sc, _), (_, d) in rows.items()
                      if sc not in ('hors-cinematique', 'flux-non-arme')})
print()
print(f"NPCOK scenes={len(npcok_scenes)} pnj_suivis={npcok_pnj} cycles={npcok_cycles} "
      f"plateforme={','.join(plateformes) if plateformes else '?'}")
