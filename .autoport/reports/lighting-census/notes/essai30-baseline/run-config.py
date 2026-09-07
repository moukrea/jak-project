"""Select/restore only this arm's runtime proof_env under the backlog's own lock."""
import json
import os
from pathlib import Path
import sys
root = Path(os.environ['ARM_ROOT'])
sys.path.insert(0, str(root / '.autoport/lib'))
import backlog
path = root / '.autoport/backlog.yaml'
saved = Path(os.environ['ARM_SAVED_ENV'])
with backlog._Lock(path):
    doc = backlog._read(path)
    item = next(it for it in doc['items'] if it['id'] == 'lighting-census')
    if sys.argv[1] == 'select':
        before = item.get('proof_env', [])
        replacements = {
            'OG_REFSET': 'capture',
            'OG_REFSET_DIR': os.environ['ARM_CAPTURE_DIR'],
            'OG_PAD_REPLAY_REPLAY': str(root / '.autoport/refset/neutral.inputs'),
        }
        after = [entry for entry in before if entry.split('=', 1)[0] not in replacements]
        after += [f'{key}={value}' for key, value in replacements.items()]
        with saved.open('x') as out:
            json.dump({'before': before, 'during': after}, out, indent=2)
        item['proof_env'] = after
    else:
        if not saved.exists():
            sys.exit(0)
        state = json.loads(saved.read_text())
        if item.get('proof_env', []) != state['during']:
            raise SystemExit('proof_env changed concurrently; refusing to overwrite another writer')
        item['proof_env'] = state['before']
    backlog._atomic_write(path, backlog._dump(doc))
    print(f'proof_env_{sys.argv[1]}=lighting-census arm={os.environ["ARM_NAME"]}')
