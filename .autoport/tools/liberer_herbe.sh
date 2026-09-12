#!/usr/bin/env bash
# Leve le verrou de phase 3 sur la campagne herbe.
# A LANCER UNIQUEMENT sur instruction explicite de l'owner : sa consigne de mission dit
# qu'aucune implementation ne commence avant un feu vert separe de la validation du plan.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import sys; sys.path.insert(0,'.autoport')
from lib import backlog as B
bl=B.load()
ids=['grass-baseline-cost','grass-dead-tail','grass-chunk-cull','grass-surface-truth',
     'grass-overlay-meshes','grass-edge-truth','grass-path-transitions','grass-clumps',
     'grass-blade-variants','grass-shading','grass-wind','grass-wind-exposure',
     'grass-biome-profiles','grass-edge-falloff','grass-interaction-direction',
     'grass-lod-popin','grass-levels','recharged-grass-wear']
n=0
for i in ids:
    it=bl.get(i)
    if it is None or it.get('status')!='blocked':
        print('saute', i, it.get('status') if it else 'ABSENT')
        continue
    bl.set_status(i,'open', block_reason=None)
    n+=1
    print('ouvert', i)
print('%d item(s) rendus a la file' % n)
PY
