from pathlib import Path
import hashlib
import json
import statistics
import sys

root = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(root / '.autoport/lib'))
import hdr_batches as hdr

notes = Path(__file__).resolve().parent
runs = {'delivered41': notes.parent / 'essai41/portal96', 'neutral43': notes / 'hut-neutral'}
result = {'DIRECTIVES': 'v8aed688f73', 'purpose': 'diagnostic BAKED-MODULATION, not delivered settings or game validation',
          'limitation': 'lower-image rectangle is not semantic attribution of the outdoor ground reported by the owner', 'runs': {}}
for label, directory in runs.items():
    batch = root / (directory / 'batch-path.txt').read_text().strip()
    manifest = json.loads((batch / 'manifest.json').read_text())
    assert all(hdr.sha(batch / p) == digest for p, digest in manifest['files'].items())
    groups = json.loads((directory / 'native-summary.json').read_text())['groups']
    before = {row['arm']: row['mean_rgba'] for row in groups
              if row['case'] == 'warp-gate' and row['stage'] == 'before_world_sprites'}
    row = {'manifest': str(batch / 'manifest.json'), 'manifest_sha256': hdr.sha(batch / 'manifest.json'),
           'native_summary_sha256': hdr.sha(directory / 'native-summary.json'),
           'before_sprites_rgb': before,
           'before_sprites_on_off_ratio': [before['recharged'][i] / before['origine-lumiere'][i] for i in range(3)],
           'regions': {}}
    pixels = json.loads((batch / 'pixels.json').read_text())['images']
    for region, rect in [('whole_image', None), ('lower_image', [0, 120, 320, 180])]:
        arms = {}
        for arm in ['recharged', 'origine-lumiere']:
            paths = sorted(p for p in pixels if p.startswith('captures/' + arm + '/'))
            assert len(paths) == 2
            values = [pixels[p]['stats'] if rect is None else hdr.measure(batch / p, rect) for p in paths]
            arms[arm] = {'images': [{'path': p, 'sha256': hdr.sha(batch / p)} for p in paths],
                         'mean': {k: statistics.mean(v[k] for v in values) for k in
                                  ['luma', 'detail', 'flat', 'saturation', 'white', 'nearwhite', 'clipped']}}
        row['regions'][region] = {'roi_exclusive': rect, 'arms': arms}
    result['runs'][label] = row
(notes / 'modulation-comparison.json').write_text(json.dumps(result, indent=2) + '\n')
for label, row in result['runs'].items():
    print(label, 'before_sprites_on_off_ratio', row['before_sprites_on_off_ratio'])
    for region, value in row['regions'].items():
        print(region, {arm: data['mean'] for arm, data in value['arms'].items()})
