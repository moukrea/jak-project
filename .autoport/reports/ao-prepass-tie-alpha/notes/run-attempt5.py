"""Run one authorized leg; archive the producer's outputs without editing them."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

notes = Path(__file__).resolve().parent
root = notes.parents[3]
view, arm = sys.argv[1:]
assert view in ('village1-hut', 'village1-out', 'beach')
assert arm in ('reference', 'off', 'comparison')
ledger = notes / 'campaign-runs.jsonl'
entries = [json.loads(line) for line in ledger.read_text().splitlines()] if ledger.exists() else []
starts = [e for e in entries if e['event'] == 'start']
assert len(starts) < 9, 'Authorized campaign budget exhausted'
assert not any(e['view'] == view and e['arm'] == arm for e in starts), 'Leg already launched'
subprocess.run([sys.executable, str(notes / 'pin-attempt5.py'), view, arm], cwd=root, check=True)
number = len(starts) + 1
name = f'{number:02d}-{view}-{arm}'
archive = notes / 'campaign' / name
archive.mkdir(parents=True, exist_ok=False)

def record(event, **extra):
    entry = dict(event=event, number=number, view=view, arm=arm,
                 at=datetime.datetime.now(datetime.timezone.utc).isoformat(), **extra)
    with ledger.open('a') as out:
        out.write(json.dumps(entry) + '\n')
        out.flush()
        os.fsync(out.fileno())

timeout_s = 135 if view == 'beach' else 125
record('start', remaining=9-number, timeout_s=timeout_s)
command = ['bash', '.autoport/lib/proof_run.sh', 'ao-prepass-tie-alpha', 'device', '--timeout', str(timeout_s)]
suffix = '-off' if arm == 'off' else ''
if arm == 'off':
    command += ['--off']
with (archive / 'driver.log').open('w') as log:
    result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
report_dir = notes.parent
for part in ('.txt', '.seal', '-engine.log', '-run.txt', '-teardown-fin.txt', '-impossible.txt'):
    source = report_dir / ('proof' + suffix + part)
    if source.exists():
        shutil.copy2(source, archive / source.name)
fields = {}
proof = archive / ('proof' + suffix + '.txt')
if proof.exists():
    fields = dict(line.split('=', 1) for line in proof.read_text().splitlines() if '=' in line)
record('finish', exit_code=result.returncode,
       proof_sha256=hashlib.sha256(proof.read_bytes()).hexdigest() if proof.exists() else None,
       proof_run_id=fields.get('proof_run_id'), duration_s=fields.get('duration_s'),
       crash=fields.get('crash'), frames=fields.get('frames'))
wanted = (
    'crash', 'frames', 'duration_s', 'ao_probe_samples', 'ao_probe_compared',
    'ao_probe_baseline_saved', 'ao_geom_tie_absent_px', 'ao_geom_tie_cover_px',
    'ao_static_defects', 'ao_tie_color_reference_saved', 'ao_tie_color_measured',
    'ao_tie_color_missing', 'ao_tie_color_changed_px', 'ao_tie_color_tie_pixels',
    'ao_tie_prepass_defects',
)
print(json.dumps(dict(leg=name, exit_code=result.returncode, archive=str(archive),
                     measures={k: v for k, v in fields.items() if k in wanted}), indent=2))
sys.exit(result.returncode)
