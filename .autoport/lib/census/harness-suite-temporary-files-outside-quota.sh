#!/usr/bin/env bash
# Le producteur de preuve recueille ces mesures ; aucun champ de proof.txt n'est ecrit ici.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
python3 - <<'PY'
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, '.autoport/lib')
import suite_gate

# Chemins explicites pour l'epinglage des sources du verdict, imports compris.
sources = ['.autoport/lib/suite_gate.py',
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
paths, refusals = [], []
if xml.exists():
    for prop in ET.parse(xml).iter('property'):
        if prop.get('name') == 'created_paths':
            paths.extend(p for row in json.loads(prop.get('value')) for p in row)
        elif prop.get('name') == 'worktree':
            paths.append(prop.get('value'))
        elif prop.get('name') == 'infrastructure_refusal':
            refusals.append(prop.get('value'))
outside = sum(not Path(p).resolve().is_relative_to('/tmp') for p in paths)
defects = (failed + skipped + int(rc != 0) + timed_out
           + int(len(results) < 600) + int(len(tmp_tests) != 11)
           + int(len(pin_tests) != 12) + int(len(paths) != 21)
           + int(outside != len(paths)) + int(len(refusals) != 2))
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
}.items():
    print(f'{key}={value}')
PY
