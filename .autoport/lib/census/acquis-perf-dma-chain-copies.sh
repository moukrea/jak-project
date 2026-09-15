#!/usr/bin/env bash
# DIRECTIVES vf72d3bd470 — banc isole et compteurs de la course USB courante.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
D=${AUTOPORT_CENSUS_DIR:-.autoport/reports/acquis-perf-dma-chain-copies}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
D=$(cd "$D" && pwd) || exit 1
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
arm=""
[ "${AUTOPORT_CENSUS_ARMED:-1}" != 0 ] || arm=-off
ENGINE=$(python3 .autoport/lib/impossible.py name engine "$arm") || exit 1

# proof_run fournit ce journal avant de composer/sceller la preuve. La garde
# autonome controle ensuite le paquet scelle ; ici aucune acquisition imbriquee.
. .autoport/acquis/perf-dma-chain-copies.sh
dma_check_log "$D/$ENGINE" > "$D/notes/dma-live.log" 2>&1
live_rc=$?
cat "$D/notes/dma-live.log" >&2
context_rc=1
if [ "${AUTOPORT_CENSUS_ID:-}" = acquis-perf-dma-chain-copies ] &&
   [ "${AUTOPORT_CENSUS_ARMED:-}" = 1 ] &&
   grep -qx 'zf_context_mode=device' "${AUTOPORT_CENSUS_CONTEXT:-/dev/null}"; then
  context_rc=0
fi

# Ces citations font entrer les fixtures dans l'empreinte du verdict.
sources=(.autoport/tests/harness/conftest.py .autoport/tests/harness/bench_env.py)
for source in "${sources[@]}"; do [ -f "$source" ] || exit 1; done
xml="$D/notes/dma-acquis.xml"
rm -f "$xml"
python3 -m pytest .autoport/tests/harness/test_acquis_perf_dma_chain_copies.py \
  -q -p no:cacheprovider --junitxml="$xml" > "$D/notes/dma-acquis.log" 2>&1
bench_rc=$?
python3 - "$xml" "$bench_rc" "$live_rc" "$context_rc" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    cases = ET.parse(sys.argv[1]).findall('.//testcase')
except (OSError, ET.ParseError):
    cases = []
failed = sum(any(c.find(tag) is not None for tag in ('failure', 'error', 'skipped'))
             for c in cases)
bench_rc, live_rc, context_rc = map(int, sys.argv[2:])
defects = failed + int(not cases) + int(bench_rc != 0) + int(live_rc != 0) + int(context_rc != 0)
print(f'dma_acquis_defects={defects}')
print(f'dma_acquis_cases={len(cases)}')
print(f'dma_acquis_passed={len(cases) - failed}')
print(f'dma_acquis_failed={failed}')
print(f'dma_acquis_bench_rc={bench_rc}')
print(f'dma_acquis_live_rc={live_rc}')
print(f'dma_acquis_context_rc={context_rc}')
PY
