#!/usr/bin/env bash
# La preuve recueille ce banc et la lecture de SA course, sans second lancement du jeu.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
D=${AUTOPORT_CENSUS_DIR:-.autoport/reports/acquis-perf-fbo-passes}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
D=$(cd "$D" && pwd) || exit 1
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
arm=""
[ "${AUTOPORT_CENSUS_ARMED:-1}" != 0 ] || arm=-off
ENGINE=$(python3 .autoport/lib/impossible.py name engine "$arm") || exit 1

# La fonction est celle de la garde livree ; proof_run epingle deja l'identite
# et la fraicheur de ce journal avant de lancer le recensement.
. .autoport/acquis/perf-fbo-passes.sh
fbo_check_log "$D/$ENGINE" > "$D/notes/fbo-live.log" 2>&1
live_rc=$?
cat "$D/notes/fbo-live.log" >&2

# Chemins explicites : les fixtures font elles aussi partie du verdict epingle.
sources=(.autoport/tests/harness/conftest.py .autoport/tests/harness/bench_env.py)
for source in "${sources[@]}"; do [ -f "$source" ] || exit 1; done
xml="$D/notes/fbo-acquis.xml"
rm -f "$xml"
python3 -m pytest .autoport/tests/harness/test_acquis_perf_fbo_passes.py \
  -q -p no:cacheprovider --junitxml="$xml" > "$D/notes/fbo-acquis.log" 2>&1
bench_rc=$?
python3 - "$xml" "$bench_rc" "$live_rc" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    cases = ET.parse(sys.argv[1]).findall('.//testcase')
except (OSError, ET.ParseError):
    cases = []
failed = sum(any(c.find(tag) is not None for tag in ('failure', 'error', 'skipped'))
             for c in cases)
bench_rc, live_rc = map(int, sys.argv[2:])
defects = failed + int(not cases) + int(bench_rc != 0) + int(live_rc != 0)
print(f'fbo_acquis_defects={defects}')
print(f'fbo_acquis_cases={len(cases)}')
print(f'fbo_acquis_passed={len(cases) - failed}')
print(f'fbo_acquis_failed={failed}')
print(f'fbo_acquis_bench_rc={bench_rc}')
print(f'fbo_acquis_live_rc={live_rc}')
PY
