#!/usr/bin/env bash
# Le producteur de preuve recueille ces mesures ; aucun champ de proof.txt n'est ecrit ici.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, '.autoport/lib')
import suite_gate

# Chemins explicites pour l'epinglage des sources du verdict, imports compris.
sources = ['.autoport/lib/suite_gate.py',
           '.autoport/orchestrator.py',
           '.autoport/tests/harness/test_close_gate_tmp.py',
           '.autoport/tests/harness/test_suite_tmp.py',
           '.autoport/tests/harness/test_pin_props.py',
           '.autoport/tests/harness/conftest.py',
           '.autoport/tests/harness/bench_env.py']
notes = Path('.autoport/reports/harness-suite-temporary-files-outside-quota/notes')
notes.mkdir(parents=True, exist_ok=True)
xml = notes.resolve() / 'suite-junit.xml'
xml.unlink(missing_ok=True)
# Le contrat exige de resister a cet heritage, y compris dans les rejeux imbriques.
os.environ['TMPDIR'] = '/tmp'
rc, seconds, timed_out = suite_gate._run_pytest(
    str(Path.cwd()), '.autoport/tests/harness', str(xml), 360)
results = suite_gate.read_junit(str(xml)) or {}
failed = sum(v[0] in ('failure', 'error') for v in results.values())
skipped = sum(v[0] == 'skipped' for v in results.values())
tmp_tests = [n for n, v in results.items()
             if '/test_suite_tmp.py::' in n and v[0] == 'passed']
pin_tests = [n for n, v in results.items()
             if '/test_pin_props.py::' in n and v[0] == 'passed']
acquis_tests = [n for n, v in results.items()
               if '/test_close_gate_tmp.py::' in n and v[0] == 'passed']
paths, refusals = [], []
acquis_paths, acquis_refusals, acquis_rotations, acquis_reds = [], [], [], []
if xml.exists():
    for prop in ET.parse(xml).iter('property'):
        if prop.get('name') == 'created_paths':
            paths.extend(p for row in json.loads(prop.get('value')) for p in row)
        elif prop.get('name') == 'worktree':
            paths.append(prop.get('value'))
        elif prop.get('name') == 'infrastructure_refusal':
            refusals.append(prop.get('value'))
        elif prop.get('name') == 'acquis_created_paths':
            acquis_paths.extend(json.loads(prop.get('value')))
        elif prop.get('name') == 'acquis_unavailable_refusal':
            acquis_refusals.append(prop.get('value'))
        elif prop.get('name') == 'acquis_rotation':
            acquis_rotations.append(prop.get('value'))
        elif prop.get('name') == 'acquis_red_refusal':
            acquis_reds.append(prop.get('value'))
outside = sum(not Path(p).resolve().is_relative_to('/tmp') for p in paths)
acquis_outside = sum(not Path(p).resolve().is_relative_to('/tmp') for p in acquis_paths)
defects = (failed + skipped + int(rc != 0) + timed_out
           + int(len(results) < 600) + int(len(tmp_tests) != 11)
           + int(len(pin_tests) != 12) + int(len(paths) != 21)
           + int(outside != len(paths)) + int(len(refusals) != 2)
           + int(len(acquis_tests) != 12) + int(len(acquis_paths) != 66)
           + int(acquis_outside != len(acquis_paths))
           + int(len(acquis_refusals) != 2) + int(len(acquis_rotations) != 8)
           + int(len(acquis_reds) != 2))
for key, value in {
    'suite_tmp_defects': defects,
    'suite_tmp_bench_passed': len(tmp_tests),
    'suite_tmp_paths_created': len(paths),
    'suite_tmp_paths_outside_quota': outside,
    'suite_tmp_unavailable_refused': len(refusals),
    'suite_tmp_pin_props_passed': len(pin_tests),
    'suite_tmp_full_collected': len(results),
    'suite_tmp_full_failed': failed,
    'suite_tmp_full_skipped': skipped,
    'suite_tmp_full_rc': rc,
    'suite_tmp_full_seconds': round(seconds, 2),
    'suite_tmp_full_timed_out': timed_out,
    'suite_tmp_acquis_bench_passed': len(acquis_tests),
    'suite_tmp_acquis_paths_created': len(acquis_paths),
    'suite_tmp_acquis_paths_outside_quota': acquis_outside,
    'suite_tmp_acquis_unavailable_refused': len(acquis_refusals),
    'suite_tmp_acquis_rotation_checked': len(acquis_rotations),
    'suite_tmp_acquis_red_refused': len(acquis_reds),
    'suite_tmp_orchestrator_sha': hashlib.sha256(Path(sources[1]).read_bytes()).hexdigest(),
}.items():
    print(f'{key}={value}')
PY
