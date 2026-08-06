#!/usr/bin/env python3
"""Cycle-4 DATA pass over recharged_assets/physics_chains.txt.

Everything here is a runtime-read parameter: this script needs no build of any kind, and the
device picks it up from the EXTERNAL override pack. Five mechanical rules, each tied to one
owner complaint from the 14:45 verdict:

  R1  MIRRORED COLLIDER MASKS. Every model with L/R leg or arm capsules listed the OPPOSITE
      side's cloth chain (Lthigh -> kneeflapR, Rthigh -> kneeflapL, ...). A pant flap was
      therefore tested against the leg it never touches and free to sink into its own. jak-hd
      is the one model authored with BOTH chains on BOTH capsules, so that is the shape every
      other model is brought to. Adding a chain to a capsule can only ever push it out of a
      volume it had no business being inside.
  R2  LEG CLOTH VS ITS OWN LEGS. eichar/jak2/jakp declare pantsL/pantsR and mask them to the
      torso only — the thigh cones list the jacket and nothing else. Owner V: the jacket over
      the trousers still clips.
  R3  hang= COVERAGE. Owner R: "as-tu defini un haut et un bas". Gravity is world-space and
      proven so, but a chain's REST direction was still purely the animator's, which is why
      Gol's sleeve points forward. hang= blends the rest pose toward world DOWN. Conservative
      per category, and never applied where it is already authored.
  R4  MAIA'S HAIR IS NOT TESTED AT ITS ROOT. colskip=2 exempts the first two links from the
      push-out AND from the residual audit — so the two links nearest her skull could sit
      inside her head while the audit read resid=0. That is one of the three causes the owner
      listed for U, and it is the one the data can answer: colskip 2 -> 1.
  R5  CLOTH THICKNESS. The chains the owner sees clipping end their frames at a clearance of
      -0.03 units: the solver puts the BONE exactly on the capsule surface, and the mesh
      welded to that bone then hangs through it. radius= is the chain's own thickness in the
      contact test, so it is what buys a visible gap.
"""
import re, sys, collections

PATH = 'recharged_assets/physics_chains.txt'

# R3 categories: (regex on chain name, hang value). First match wins; conservative by design —
# an ear that droops fully is as wrong as a sleeve that points forward.
HANG = [
    (r'hair|mane|ponytail|braid|bang|fringe|strand|coiffe|tress', 0.35),
    (r'beard|goatee|moustache|whisker|bouc',                       0.35),
    (r'cape|cloak|sleeve|cuff|robe|skirt|apron|sash|scarf|tabard', 0.40),
    (r'shirt|pant|cloth|coat|jacket|hem|flap|tunic|loin|kilt|collar', 0.30),
    (r'strap|lanier|sangle|thong|cord|rope|pouch|satchel|bag|'
     r'pendant|necklace|amulet|buckle|ring|tassel',                0.25),
    (r'chest|boob|bood|breast|bust',                               0.25),
    (r'belly|gut|paunch|ventre|stomach',                           0.20),
    (r'butt|glute|rear|fesse|hip',                                 0.20),
    (r'tail|queue',                                                0.20),
    (r'hat|cap\b|brim|feather|plume|horn|antenna|bun|log',         0.15),
    (r'ear|oreille',                                               0.12),
]

lines = open(PATH, errors='ignore').read().split('\n')

# ---- pass 1: index models, chains, capsules ----------------------------------------------
model = None
chains_of = collections.defaultdict(list)      # model -> [chain name]
chain_line = {}                                # (model, chain) -> line idx
cap_lines = collections.defaultdict(list)      # model -> [line idx]
for i, l in enumerate(lines):
    m = re.match(r'\[model\s+([^\]]+)\]', l)
    if m:
        model = m.group(1).split()[0]
        continue
    if l.startswith('chain ') and model:
        n = l.split()[1]
        chains_of[model].append(n)
        chain_line[(model, n)] = i
    elif l.startswith('capsule ') and model:
        cap_lines[model].append(i)

stats = collections.Counter()
hang_by_cat = collections.Counter()

# ---- R1 + R2: collider masks -------------------------------------------------------------
LEGCAP = re.compile(r'^capsule\s+\S*(thigh|knee|ankle|shin|calf|foot)', re.I)
for mdl, caps in cap_lines.items():
    have = set(chains_of[mdl])
    for i in caps:
        l = lines[i]
        mm = re.search(r'chains=(\S+)', l)
        if not mm:
            continue
        cur = mm.group(1).split(',')
        new = list(cur)
        # R1: whatever side a capsule names, its mirror chain rides along
        for c in cur:
            for a, b in (('L', 'R'), ('R', 'L')):
                if c.endswith(a) and (c[:-1] + b) in have and (c[:-1] + b) not in new:
                    new.append(c[:-1] + b)
                    stats['R1 mirror-chain added'] += 1
        # R2: leg cloth belongs on the leg cones
        if LEGCAP.match(l):
            for c in have:
                if re.match(r'pants?[LR]?$', c) and c not in new:
                    new.append(c)
                    stats['R2 leg cloth masked to its own leg'] += 1
        if new != cur:
            lines[i] = l.replace('chains=' + mm.group(1), 'chains=' + ','.join(new))

# ---- R3: hang= coverage ------------------------------------------------------------------
for (mdl, cn), i in chain_line.items():
    l = lines[i]
    if 'hang=' in l:
        continue
    low = cn.lower()
    for rx, v in HANG:
        if re.search(rx, low):
            lines[i] = l.rstrip() + f' hang={v}'
            stats['R3 hang= added'] += 1
            hang_by_cat[rx.split('|')[0]] += 1
            break

# ---- R4: Maia's hair root joins the collision set ----------------------------------------
for mdl in ('evilsis-lod0',):
    for cn in chains_of[mdl]:
        if re.search(r'hair|ponytail', cn, re.I):
            i = chain_line[(mdl, cn)]
            if 'colskip=2' in lines[i]:
                lines[i] = lines[i].replace('colskip=2', 'colskip=1')
                stats['R4 Maia hair colskip 2->1'] += 1

# ---- R5: cloth thickness where the measured clearance was ~0 -----------------------------
R5 = {('jak-hd', 'shirtL'): 150, ('jak-hd', 'shirtR'): 150,
      ('eichar-lod0', 'shirtL'): 150, ('eichar-lod0', 'shirtR'): 150,
      ('eichar-lod0', 'pantsL'): 110, ('eichar-lod0', 'pantsR'): 110,
      ('dax-hd', 'flapL'): 60, ('dax-hd', 'flapR'): 60,
      ('sidekick-lod0', 'flapL'): 60, ('sidekick-lod0', 'flapR'): 60}
for k, r in R5.items():
    i = chain_line.get(k)
    if i is None:
        print(f'  note: {k} not present, skipped')
        continue
    lines[i] = re.sub(r'radius=\d+', f'radius={r}', lines[i], count=1)
    stats['R5 cloth thickness raised'] += 1

open(PATH, 'w').write('\n'.join(lines))
for k, v in sorted(stats.items()):
    print(f'  {k}: {v}')
print('  hang= by category:', dict(hang_by_cat))
