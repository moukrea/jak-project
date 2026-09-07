"""Compare the two existing pad traces and sample-option logs; no proof fields written."""
from collections import Counter
import hashlib
from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parent


def snapshots(arm):
    blocks = {}
    block = None
    for line in (root / arm / 'pad-state.trace').read_text().splitlines():
        label, frame, *data = line.split()
        if label == 'POSTLOAD-BEGIN':
            assert block is None
            absolute = struct.unpack('<q', bytes.fromhex(''.join(data)))[0]
            assert absolute not in blocks
            block = []
        elif label == 'POSTLOAD-END':
            assert block is not None
            assert struct.unpack('<q', bytes.fromhex(''.join(data)))[0] == absolute
            blocks[absolute] = block
            block = None
        elif block is not None:
            block.append((label, bytes.fromhex(''.join(data))))
    assert block is None
    assert set(blocks) == {2281, 2282}, set(blocks)
    return blocks


def describe(value):
    if len(value) <= 24:
        return value.hex()
    return f'bytes={len(value)} sha256={hashlib.sha256(value).hexdigest()}'


arms = {arm: snapshots(arm) for arm in ('baseline', 'candidate')}
for lf in (2281, 2282):
    left, right = (arms[a][lf] for a in arms)
    print(f'POSTLOAD lf={lf} records_baseline={len(left)} records_candidate={len(right)}')
    assert [r[0] for r in left] == [r[0] for r in right], 'record layouts differ'
    differences = [(i, tag, a, b) for i, ((tag, a), (_, b)) in enumerate(zip(left, right)) if a != b]
    print(f'POSTLOAD lf={lf} differing_records={len(differences)} by_tag={dict(Counter(d[1] for d in differences))}')
    for i, tag, a, b in differences[:30]:
        print(f'DIFF lf={lf} record={i} tag={tag} baseline={describe(a)} candidate={describe(b)}')
        if len(a) == len(b):
            print(f'DIFF byte_offsets={[j for j in range(len(a)) if a[j] != b[j]][:40]}')
    print(f'RNG lf={lf} ' + ' '.join(f'{tag}_equal={a == b}' for (tag, a), (_, b) in zip(left, right)
                                  if tag in ('goal-vu-R', '*knuth-rand-state*', '*random-generator*',
                                             'native-pc-rng', 'native-mips-rng', 'native-mips-R')))
    for tag, value in left:
        if tag.startswith('pc-settings-'):
            print(f'GOALCONFIG lf={lf} {tag}={describe(value)}')

configs = {}
for arm in arms:
    config = {}
    for line in (root / arm / 'runtime-extract.log').read_text().splitlines():
        match = re.search(r'REFSET render-config case=(\S+) chain_lf=(\d+) (\S+)=(\S+)', line)
        if match:
            case, lf, field, value = match.groups()
            key = (case, int(lf), field)
            assert key not in config
            config[key] = value
    assert config
    configs[arm] = config
left, right = configs.values()
keys = sorted(set(left) | set(right))
differences = [key for key in keys if left.get(key) != right.get(key)]
print(f'RENDERCONFIG baseline_fields={len(left)} candidate_fields={len(right)} differing_fields={len(differences)}')
for key in differences:
    print(f'RENDERCONFIG DIFF {key} baseline={left.get(key)} candidate={right.get(key)}')
for key in keys:
    print(f'RENDERCONFIG {key} baseline={left.get(key)} candidate={right.get(key)}')
print('Limites : observations CPU après dispatch ; contrôles/poses articulées/états privés non exhaustifs. Aucune qualification pixel.')
