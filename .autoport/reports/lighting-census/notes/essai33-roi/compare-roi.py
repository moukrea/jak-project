"""Analyse hors ligne du diagnostic existant ; aucun champ proof.txt produit."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent
arms = {}
for arm in ('baseline', 'candidate'):
    rows = []
    for line in (root / arm / 'runtime-extract.log').read_text().splitlines():
        if 'REFSET-ROI ' in line:
            raw = line[line.index('REFSET-ROI '):]
            fields = dict(re.findall(r'(\w+)=(.*?)(?= \w+=|$)', raw))
            rows.append((fields, raw))
    arms[arm] = rows
left, right = arms.values()
print(f'ROI records baseline={len(left)} candidate={len(right)}')
assert len(left) == len(right) and left
identity = ('type', 'capture', 'id', 'name', 'hash', 'first_index', 'texture')
shape = ('dims', 'bpp', 'viewport', 'rgb_units')
first = None
for i, ((a, raw_a), (b, raw_b)) in enumerate(zip(left, right)):
    assert all(a.get(k) == b.get(k) for k in identity), (i, raw_a, raw_b)
    assert all(a.get(k) == b.get(k) for k in shape), (i, raw_a, raw_b)
    if a['type'] == 'model':
        continue
    before_equal = a.get('rgb_before_hash') == b.get('rgb_before_hash')
    after_equal = a.get('rgb_after_hash') == b.get('rgb_after_hash')
    if not before_equal or not after_equal:
        if first is None:
            first = i
            print(f'FIRST_DIVERGENT row={i} before_equal={before_equal} after_equal={after_equal}')
        if a['type'] == 'bucket' or before_equal:
            print(f'BASELINE row={i} {raw_a}')
            print(f'CANDIDATE row={i} {raw_b}')
print(f'ROI first_divergent_row={first}')
print('Limites : RGB du seul rectangle sélectionné ; pas de profondeur/poses/uniformes ; absence erreur GL non attestée.')
