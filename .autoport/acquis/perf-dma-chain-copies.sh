#!/usr/bin/env bash
# DIRECTIVES vf72d3bd470 — acquis Android, sourceable sans acquisition.
# Le census fournit son propre journal ; seule dma_main peut appeler proof_run.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/acquis_device.sh"
dma_check_log() {
  python3 - "${1:-}" <<'PY'
import re
import sys
from pathlib import Path

def fail(message):
    print('[acquis/perf-dma-chain-copies] NON PROUVE : ' + message, file=sys.stderr)
    sys.exit(1)

try:
    text = Path(sys.argv[1]).read_text(errors='replace')
except OSError as exc:
    fail('journal indisponible : ' + str(exc))
if re.search(r'fatal signal|(?:caught|received|killed by|terminated by)[^\r\n]*SIG(?:SEGV|ILL|ABRT|BUS|FPE)|^\s*SIG(?:SEGV|ILL|ABRT|BUS|FPE)\b|segmentation fault|illegal instruction|core dumped|assertion.*failed|terminate called|AddressSanitizer', text, re.I | re.M):
    fail('crash connu dans le journal')
if re.search(r'A42-CHAIN-PRECOPY[^\r\n]*\bskip\b|A37-CHAIN-LOOP|A37-BUCKET-MALFORMED', text, re.I):
    fail('chaine rejetee ou boucle DMA dans le journal')
keys = ('dma_chain_walks_per_frame', 'dma_chain_walks_total',
        'dma_chain_frames_measured', 'dma_chain_attempts_measured',
        'dma_chain_diagnostics', 'dma_chain_rejected',
        'dma_chain_bytes_copied', 'dma_chain_copy_mode')
values = {key: [] for key in keys}
for line in text.splitlines():
    if 'dma_chain_' not in line:
        continue
    for key in keys:
        if key not in line:
            continue
        for match in re.finditer(r'(?<![\w])' + key + r'\b', line):
            suffix = line[match.end():]
            if not re.fullmatch(r'=[0-9]{1,20}\s*', suffix):
                fail('nombre malforme : ' + key + suffix)
            value = int(suffix[1:].strip())
            if value > 2**64 - 1:
                fail('depassement u64 : ' + key)
            values[key].append(value)
for key, found in values.items():
    if not found:
        fail('cle absente : ' + key)
# autoport_proof reemet une table dont les cles sont mises a jour separement.
# Pas d'equations entre publications intermediaires ni de monotonie des moyennes.
for key in keys[:4]:
    if any(b < a for a, b in zip(values[key], values[key][1:])):
        fail('cumul decroissant : ' + key)
for key in ('dma_chain_diagnostics', 'dma_chain_rejected'):
    if any(values[key]):
        fail('defaut mesure : ' + key + '=' + str(max(values[key])))
if max(values[keys[0]]) > 2 or values[keys[0]][-1] != 2:
    fail('maximum de parcours attendu : 2')
for key in ('dma_chain_frames_measured', 'dma_chain_attempts_measured', 'dma_chain_bytes_copied'):
    if values[key][-1] <= 0:
        fail('population vide : ' + key)
# Une fenetre de demarrage sans copie peut publier 0 ; le mode final doit etre 1.
if any(v not in (0, 1) for v in values['dma_chain_copy_mode']) or values['dma_chain_copy_mode'][-1] != 1:
    fail('mode copie final attendu : 1')
frames = values['dma_chain_frames_measured'][-1]
if values['dma_chain_walks_total'][-1] != 2 * frames or values['dma_chain_attempts_measured'][-1] != frames:
    fail('cumuls finaux incoherents : attendu deux parcours et une tentative par image')
print('[acquis/perf-dma-chain-copies] TENU : ' + ' '.join(
    key + '=' + str(values[key][-1]) for key in keys))
PY
}

# 2 = preuve absente/perimee/invalide ; 1 = defaut mesure, sans reacquisition.
# La garde scellee est l'unique exemplaire de lib/acquis_device_guard.py (site propre compris).
dma_check_proof() {
  local log
  log=$(acq_device_guard --item acquis-perf-dma-chain-copies --tag perf-dma-chain-copies \
      --site perf-dma-chain-copies \
      --log-key dma_chain_walks_per_frame --log-key dma_chain_walks_total \
      --log-key dma_chain_frames_measured --log-key dma_chain_attempts_measured \
      --log-key dma_chain_diagnostics --log-key dma_chain_rejected \
      --log-key dma_chain_bytes_copied --log-key dma_chain_copy_mode \
      --expect dma_acquis_defects=0 --expect proof_census_present=1 --expect proof_census_rc=0 \
      --expect dma_acquis_failed=0 --expect dma_acquis_bench_rc=0 --expect dma_acquis_live_rc=0 \
      --expect dma_acquis_context_rc=0 \
      --positive proof_census_keys --positive dma_acquis_cases --positive dma_acquis_passed \
      --same dma_acquis_passed=dma_acquis_cases) || return $?
  dma_check_log "$log" >&2 || return 1
  printf '%s\n' "$log"
}

dma_main() {
  acq_device_main perf-dma-chain-copies dma_check_proof \
    acquis-perf-dma-chain-copies device --timeout 60 -- "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  dma_main "$@"
fi
