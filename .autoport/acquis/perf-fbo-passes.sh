#!/usr/bin/env bash
# DIRECTIVES v16b7fb9530 — acquis-perf-fbo-passes, preuve proof_run x86 SDR reutilisable.
# Sourceable sans acquisition. Le census appelle fbo_check_log sur SA course proof_run,
# dont il garantit l'identite/fraicheur ; cette fonction ne juge que les compteurs.
fbo_check_log() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

def fail(message):
    print('[acquis/perf-fbo-passes] NON PROUVE : ' + message, file=sys.stderr)
    sys.exit(1)

try:
    text = Path(sys.argv[1]).read_text(errors='replace')
except OSError as exc:
    fail('journal indisponible : ' + str(exc))
if re.search(r'SIG(?:SEGV|ILL|ABRT|BUS|FPE)|segmentation fault|illegal instruction|core dumped|fatal signal|assertion.*failed|assertion failed|terminate called|AddressSanitizer', text, re.I):
    fail('crash connu dans le journal')
keys = ('fb_extra_passes_per_frame', 'fb_frames_measured',
        'fb_ui_direct_frames', 'fb_pass_ends_no_invalidate_max', 'fb_ui_direct_blocked')
values = {key: [] for key in keys}
for line in text.splitlines():
    for key in keys:
        # Cherche l'etiquette apres les prefixes temps/logcat, mais exige toute la valeur.
        match = re.search(r'(?<![\w])' + key + r'\b(.*)$', line)
        if not match:
            continue
        suffix = match[1]
        if not suffix.startswith('='):
            fail('valeur malformee : ' + key)
        value = suffix[1:].strip()
        if key != 'fb_ui_direct_blocked':
            if not re.fullmatch(r'[0-9]{1,20}', value) or int(value) > 2**64 - 1:
                fail('nombre malforme : ' + key + '=' + value)
            value = int(value)
        values[key].append(value)
for key, found in values.items():
    if not found:
        fail('cle absente : ' + key)
reasons = set(values['fb_ui_direct_blocked'])
known = {'-', 'no-split', 'disarmed', 'hdr-chain', 'hdr-output', 'refset', 'msaa', 'no-window-depth'}
if reasons - known:
    fail('repli inconnu : ' + ','.join(sorted(reasons - known)))
if 'disarmed' in reasons:
    fail('repli disarmed : correctif desarme')
for key in ('fb_extra_passes_per_frame', 'fb_pass_ends_no_invalidate_max'):
    if max(values[key]) != 0:
        fail(key + '=' + str(max(values[key])))
for key in ('fb_frames_measured', 'fb_ui_direct_frames'):
    if values[key][-1] <= 0:
        fail('population vide : ' + key + '; replis=' + ','.join(sorted(reasons)))
print('[acquis/perf-fbo-passes] TENU : ' + ' '.join(
    key + '=' + str(values[key][-1]) for key in keys[:-1]) +
    '; replis=' + ','.join(sorted(reasons)))
PY
}

# 2 = acquisition absente/perimee ; 1 = verdict moteur refuse, sans nouvelle course.
fbo_check_proof() {
  python3 - "${ACQ_CACHE_TTL:-1800}" <<'PYPROOF'
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

item = 'acquis-perf-fbo-passes'
directory = Path('.autoport/reports') / item
proof, log, seal = (directory / arm_name(kind) for kind in ('proof', 'engine', 'seal'))
data = {}

def reject(message, code=2):
    print(f'[acquis/perf-fbo-passes] NON PROUVE : {proof} '
          f'run_id={data.get("proof_run_id", "?")} : {message}', file=sys.stderr)
    sys.exit(code)

def read_fields(text):
    fields = {}
    for line in text.splitlines():
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        # FEATURE lines are not metadata. Repeated metadata is ambiguous.
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
    data = read_fields(raw.decode())
    sealed = read_fields(seal.read_text())
    digest = hashlib.sha256(raw).hexdigest()
    if any(sealed.get(key) != digest for key in ('seal_sha', 'exit_sha')) or any(
            sealed.get(key) != str(len(raw)) for key in ('seal_bytes', 'exit_bytes')):
        raise ValueError('preuve incomplete ou sceau divergent')
    binary = Path('build/game/gk')
    if data.get('source') != 'x86' or data.get('binary') != str(binary):
        raise ValueError('source/binaire attendu : x86 build/game/gk')
    if not os.access(binary, os.X_OK) or data.get('sha') != hashlib.sha256(binary.read_bytes()).hexdigest()[:16]:
        raise ValueError('binaire absent ou sha divergent')
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
    if not log.is_file() or log.stat().st_size == 0 or not start <= log.stat().st_mtime <= proof.stat().st_mtime <= now:
        raise ValueError('journal vide ou dates journal/preuve incoherentes')
    if data.get('verdict_sources_sha') != verdict_sources('sha'):
        raise ValueError('empreinte des sources de verdict divergente')
    newer = verdict_sources('newer', proof)
    if newer:
        raise ValueError('sources de verdict plus recentes : ' + newer.replace('\n', ','))
    text = log.read_text(errors='replace')
    for key in ('fb_extra_passes_per_frame', 'fb_frames_measured', 'fb_ui_direct_frames',
                'fb_pass_ends_no_invalidate_max', 'fb_ui_direct_blocked'):
        matches = re.findall(r'(?<![\w])' + key + r'\b=([^\r\n]*)', text)
        if not matches or matches[-1].strip() != data.get(key):
            raise ValueError('journal/preuve divergent : ' + key)
except (OSError, ValueError, subprocess.CalledProcessError) as exc:
    reject(str(exc))

if data.get('proof_env_proc_read') != '1' or any(
        data.get('proof_env_proc_obs_' + key) != '0' for key in ('OG_RECHARGED', 'OG_HDR', 'OG_HDR_OUT')):
    reject('regime SDR non observe dans le processus', 1)
if data.get('crash') != '0' or not re.fullmatch(r'[0-9]+', data.get('frames', '')) or int(data['frames']) <= 0:
    reject('crash ou population frames invalide', 1)
print(f'[acquis/perf-fbo-passes] preuve admise : {proof} '
      f'run_id={data.get("proof_run_id", "?")}', file=sys.stderr)
print(log)
PYPROOF
}

fbo_main() {
  # L'argument serial optionnel de l'orchestrateur est ignore : jambe x86 seulement.
  if [ "$#" -gt 1 ] || [[ "${1:-}" == --* ]]; then
    echo 'usage: perf-fbo-passes.sh [serial]' >&2
    return 1
  fi
  local root log status
  root=$(git rev-parse --show-toplevel) || return 1
  cd "$root" || return 1
  log=$(fbo_check_proof) && status=0 || status=$?
  if [ "$status" = 2 ]; then
    bash .autoport/lib/proof_run.sh acquis-perf-fbo-passes x86 --timeout 60 || {
      echo '[acquis/perf-fbo-passes] NON PROUVE : course proof_run echouee' >&2
      return 1
    }
    log=$(fbo_check_proof) || return 1
  elif [ "$status" != 0 ]; then
    return 1
  fi
  fbo_check_log "$log"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  fbo_main "$@"
fi
