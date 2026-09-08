"""Compare existing official captures; diagnostic regions do not qualify the owner's ground case."""
from pathlib import Path
import hashlib
import json
import statistics
import sys

root = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(root / '.autoport/lib'))
import hdr_batches as hdr

notes = Path(__file__).parent
before = root / '.autoport/reports/lighting-hdr/batches/essai43-coverage/20260908T161000-76323'
after = Path(sys.argv[1])
regions = {'whole_image': None, 'left_path_diagnostic': [0, 137, 35, 152],
           'entrance_lower_diagnostic': [82, 119, 153, 148]}
result = {'DIRECTIVES': 'v3909a9767c', 'purpose': 'before/after rendering diagnostic, not proof.txt or owner-case qualification',
          'limitation': 'rectangles locate visible ground/path/entrance for comparison; the particular small owner-reported patches are not identified',
          'runs': {}}
for name, batch in [('before43', before), ('after43_render', after)]:
    manifest = json.loads((batch / 'manifest.json').read_text())
    assert all(hdr.sha(batch / p) == sha for p, sha in manifest['files'].items())
    pixels = json.loads((batch / 'pixels.json').read_text())['images']
    run = {'manifest': str(batch / 'manifest.json'), 'manifest_sha256': hdr.sha(batch / 'manifest.json'), 'regions': []}
    for hour in [0, 12, 18]:
        for region, rect in regions.items():
            row = {'hour': hour, 'region': region, 'roi_exclusive': rect, 'arms': {}}
            for arm in ['recharged', 'origine-lumiere']:
                paths = [f'captures/{arm}/village1-out-h{hour:02d}{suffix}.png' for suffix in ['', '-t01']]
                assert all(p in pixels for p in paths), paths
                values = [pixels[p]['stats'] if rect is None else hdr.measure(batch / p, rect) for p in paths]
                fields = ['luma', 'detail', 'flat', 'saturation', 'white', 'nearwhite', 'clipped', 'pixels']
                means = {k: statistics.mean(v[k] for v in values) for k in fields}
                means['violet_270_330_fraction'] = statistics.mean((v['hue_bins'][9] + v['hue_bins'][10]) / v['pixels'] for v in values)
                row['arms'][arm] = {'images': [{'path': p, 'sha256': hdr.sha(batch / p)} for p in paths], 'mean': means}
            row['on_minus_off'] = {k: row['arms']['recharged']['mean'][k] - row['arms']['origine-lumiere']['mean'][k] for k in row['arms']['recharged']['mean']}
            run['regions'].append(row)
    result['runs'][name] = run
(notes / 'ground-comparison.json').write_text(json.dumps(result, indent=2) + '\n')
for name, run in result['runs'].items():
    for row in run['regions']:
        print(name, row['hour'], row['region'], json.dumps(row['on_minus_off']))
