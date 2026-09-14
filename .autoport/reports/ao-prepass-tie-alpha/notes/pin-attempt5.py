"""Pin this authorized campaign through the backlog, never through host setprop."""
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(root / '.autoport/lib'))
import backlog

view, arm = sys.argv[1:]
positions = {
    'village1-hut': ('village1-hut', '-116 14 40'),
    'village1-out': ('village1-hut', '-126 46 212'),
    'beach': ('beach-start', None),
}
assert view in positions and arm in ('reference', 'off', 'comparison')
b = backlog.load()
item = b.get('ao-prepass-tie-alpha')
props = [p for p in item['proof_props'] if not (
    p.startswith('debug.opengoal.ao.tie.') or
    p.startswith('debug.opengoal.level.warp=') or
    p.startswith('debug.opengoal.level.warp.pos='))]
warp, position = positions[view]
props += [f'debug.opengoal.level.warp={warp}']
if position is not None:
    props += [f'debug.opengoal.level.warp.pos={position}']
props += [
    'debug.opengoal.ao.tie.campaign=tie-alpha-20260914-attempt5',
    f'debug.opengoal.ao.tie.view={view}',
    f'debug.opengoal.ao.tie.reference={int(arm == "reference")}',
]
b.set_status(item['id'], item['status'], proof_props=props)
print(f'pinned view={view} arm={arm} props={len(props)}')
