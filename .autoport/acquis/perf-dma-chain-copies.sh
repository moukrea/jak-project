#!/usr/bin/env bash
# DIRECTIVES vf72d3bd470 — acquis Android, sourceable sans acquisition.
# Le census fournit son propre journal ; seule dma_main peut appeler proof_run.
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
dma_check_proof() {
  local log status
  log=$(python3 - "${ACQ_CACHE_TTL:-1800}" <<'PYPROOF'
import datetime
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, '.autoport/lib')
from impossible import arm_name

item = 'acquis-perf-dma-chain-copies'
directory = Path('.autoport/reports') / item
proof, log, seal = (directory / arm_name(kind) for kind in ('proof', 'engine', 'seal'))
data = {}

def reject(message, code=2):
    print(f'[acquis/perf-dma-chain-copies] NON PROUVE : {proof} '
          f'run_id={data.get("proof_run_id", "?")} : {message}', file=sys.stderr)
    sys.exit(code)

def read_fields(text):
    fields = {}
    for line in text.splitlines():
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        if not re.fullmatch(r'[A-Za-z0-9_]+', key):
            continue
        if key in fields:
            raise ValueError('cle dupliquee : ' + key)
        fields[key] = value
    return fields

def verdict_sources(mode, *args):
    return subprocess.check_output(
        ['bash', '.autoport/lib/verdict_sources.sh', item, mode, *map(str, args)],
        text=True).strip()

try:
    raw = proof.read_bytes()
    proof_text = raw.decode()
    data = read_fields(proof_text)
    sealed = read_fields(seal.read_text())
    digest = hashlib.sha256(raw).hexdigest()
    if any(sealed.get(key) != digest for key in ('seal_sha', 'exit_sha')) or any(
            sealed.get(key) != str(len(raw)) for key in ('seal_bytes', 'exit_bytes')):
        raise ValueError('preuve incomplete ou sceau divergent')
    binary = Path('build-android/lib/arm64-v8a/libgk.so')
    if data.get('source') != 'device' or data.get('binary') != str(binary):
        raise ValueError('source/binaire Android attendu')
    binary_bytes = binary.read_bytes()
    if data.get('sha') != hashlib.sha256(binary_bytes).hexdigest()[:16]:
        raise ValueError('sha binaire divergent')
    md5 = hashlib.md5(binary_bytes).hexdigest()
    if any(data.get(key) != md5 for key in (
            'local_lib_md5', 'device_lib_md5', 'proof_binary_local_md5', 'proof_binary_device_md5')):
        raise ValueError('md5 local/appareil ou garde binaire divergent')
    serial = data.get('serial', '')
    if (not serial or re.search(r'[:\s]|_adb-tls-|(?:\d{1,3}\.){3}\d{1,3}', serial, re.I)
            or any(data.get(key) != serial for key in ('device_serial', 'proof_binary_serial'))):
        raise ValueError('identite USB absente, interdite ou divergente')
    model = data.get('device_model', '')
    if not model or 'shield' in model.lower():
        raise ValueError('modele absent ou SHIELD interdit')
    if (data.get('proof_binary_gate_ran') != '1'
            or data.get('proof_binary_checked_before_measure') != '1'
            or data.get('proof_binary_rc') != '0'):
        raise ValueError('garde binaire non verifiee avant mesure')
    if not data.get('proof_run_id', '').strip():
        raise ValueError('run_id absent')
    features = re.findall(r'^FEATURE ' + re.escape(item) + r' armed=([01]) hits=([0-9]+)(?: .*)?$', proof_text, re.M)
    if len(features) != 1 or features[0][0] != '1' or int(features[0][1]) > 2**64 - 1:
        raise ValueError('FEATURE propre a cet item absente, ambigue ou desarmee')
    ttl = int(sys.argv[1])
    started = data.get('started_at', '')
    if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z', started):
        raise ValueError('started_at malforme')
    start = datetime.datetime.fromisoformat(started.replace('Z', '+00:00')).timestamp()
    now = time.time()
    if ttl <= 0 or not 0 <= now - start < ttl:
        raise ValueError('TTL invalide, course perimee ou future')
    if binary.stat().st_mtime > start:
        raise ValueError('binaire plus recent que le debut de course')
    for root in ('game', 'common', 'android', 'goal_src'):
        for directory_name, _, names in os.walk(root, onerror=lambda exc: (_ for _ in ()).throw(exc)):
            for name in names:
                source = Path(directory_name) / name
                if source.suffix in {'.cpp', '.h', '.gc', '.vert', '.frag'} and source.stat().st_mtime > start:
                    raise ValueError('source plus recente que le debut de course : ' + str(source))
    if not log.is_file() or log.stat().st_size == 0 or not start <= log.stat().st_mtime <= proof.stat().st_mtime <= seal.stat().st_mtime <= now:
        raise ValueError('journal vide ou dates journal/preuve/sceau incoherentes')
    for field, mode in (('verdict_sources_sha', 'sha'), ('verdict_sources_count', 'count'),
                        ('verdict_criterion_sha', 'criterion_sha'), ('verdict_acquis_sha', 'acquis_sha'),
                        ('verdict_acquis_count', 'acquis_count')):
        expected = verdict_sources(mode)
        if not expected or data.get(field) != expected:
            raise ValueError('sources de verdict divergentes : ' + field)
    newer = verdict_sources('newer', proof)
    if newer:
        raise ValueError('sources de verdict plus recentes : ' + newer.replace('\n', ','))
    text = log.read_text(errors='replace')
    for key in ('dma_chain_walks_per_frame', 'dma_chain_walks_total',
                'dma_chain_frames_measured', 'dma_chain_attempts_measured',
                'dma_chain_diagnostics', 'dma_chain_rejected',
                'dma_chain_bytes_copied', 'dma_chain_copy_mode'):
        matches = re.findall(r'(?<![\w])' + key + r'\b=([^\r\n]*)', text)
        if not matches or matches[-1].strip() != data.get(key):
            raise ValueError('journal/preuve divergent : ' + key)
except (OSError, ValueError, subprocess.CalledProcessError) as exc:
    reject(str(exc))

if data.get('crash') != '0' or not re.fullmatch(r'[0-9]{1,20}', data.get('frames', '')) or not 0 < int(data['frames']) <= 2**64 - 1:
    reject('crash ou population frames invalide', 1)
for key, expected in (('dma_acquis_defects', '0'), ('proof_census_present', '1'),
                      ('proof_census_rc', '0'), ('dma_acquis_failed', '0'),
                      ('dma_acquis_bench_rc', '0'), ('dma_acquis_live_rc', '0'),
                      ('dma_acquis_context_rc', '0')):
    if data.get(key) != expected:
        reject('recensement refuse : ' + key, 1)
for key in ('proof_census_keys', 'dma_acquis_cases', 'dma_acquis_passed'):
    value = data.get(key, '')
    if not re.fullmatch(r'[0-9]{1,20}', value) or not 0 < int(value) <= 2**64 - 1:
        reject('population du recensement invalide : ' + key, 1)
if int(data['dma_acquis_passed']) != int(data['dma_acquis_cases']):
    reject('recensement incomplet : passed != cases', 1)
print(f'[acquis/perf-dma-chain-copies] preuve admise : {proof} '
      f'run_id={data["proof_run_id"]}', file=sys.stderr)
print(log)
PYPROOF
  ) && status=0 || status=$?
  [ "$status" = 0 ] || return "$status"
  dma_check_log "$log" >&2 || return 1
  printf '%s\n' "$log"
}

dma_main() {
  if [ "$#" -gt 1 ] || [[ "${1:-}" == --* ]]; then
    echo 'usage: perf-dma-chain-copies.sh [serial]' >&2
    return 1
  fi
  local root log status
  local ANDROID_SERIAL="${1:-${ANDROID_SERIAL:-}}"
  export ANDROID_SERIAL
  if [[ "$ANDROID_SERIAL" == *:* || "$ANDROID_SERIAL" == *_adb-tls-* || "$ANDROID_SERIAL" =~ [[:space:]] || "$ANDROID_SERIAL" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo '[acquis/perf-dma-chain-copies] NON PROUVE : serial USB requis' >&2
    return 1
  fi
  root=$(git rev-parse --show-toplevel) || return 1
  cd "$root" || return 1
  log=$(dma_check_proof) && status=0 || status=$?
  if [ "$status" = 2 ]; then
    bash .autoport/lib/proof_run.sh acquis-perf-dma-chain-copies device --timeout 60 || {
      echo '[acquis/perf-dma-chain-copies] NON PROUVE : course proof_run echouee' >&2
      return 1
    }
    log=$(dma_check_proof) || return 1
  elif [ "$status" != 0 ]; then
    return 1
  fi
  printf '[acquis/perf-dma-chain-copies] TENU : %s\n' "$log"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  dma_main "$@"
fi
