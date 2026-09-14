#!/usr/bin/env bash
# DIRECTIVES v16b7fb9530 — acquis-perf-fbo-passes, course x86 SDR mise en cache.
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

fbo_check_cache() {
  python3 - "$1" "$ACQ_GK" "$ACQ_CACHE/perf-fbo-passes.stamp" "$ACQ_TTL" "${ACQ_GK_ARGS:---portable}" <<'PY'
import hashlib
import os
from pathlib import Path
import sys
import time

try:
    log, binary, stamp = map(Path, sys.argv[1:4])
    ttl = int(sys.argv[4])
    now = time.time_ns()
    log_time = log.stat().st_mtime_ns
    if not log.is_file() or log.stat().st_size == 0 or not os.access(binary, os.X_OK):
        raise ValueError('journal vide ou binaire indisponible')
    sha = hashlib.sha256(binary.read_bytes()).hexdigest()[:16]
    if stamp.read_text().strip() != sha + '|' + sys.argv[5] + '|OG_RECHARGED=0 OG_HDR=0 OG_HDR_OUT=0':
        raise ValueError('stamp/sha du binaire divergent')
    if ttl <= 0 or not 0 <= now - log_time < ttl * 10**9:
        raise ValueError('TTL du journal perime ou date future')
    if binary.stat().st_mtime_ns > log_time:
        raise ValueError('binaire plus recent que le journal')
    for root in ('game', 'common', 'android', 'goal_src'):
        for directory, _, files in os.walk(root, onerror=lambda exc: (_ for _ in ()).throw(exc)):
            for name in files:
                source = Path(directory) / name
                if source.suffix in {'.cpp', '.h', '.gc', '.vert', '.frag'} and source.stat().st_mtime_ns > log_time:
                    raise ValueError('source plus recente que le journal : ' + str(source))
except (OSError, ValueError) as exc:
    print('[acquis/perf-fbo-passes] NON PROUVE : ' + str(exc), file=sys.stderr)
    sys.exit(1)
PY
}

fbo_main() {
  # L'argument serial optionnel de l'orchestrateur est ignore : jambe x86 seulement.
  if [ "$#" -gt 1 ] || [[ "${1:-}" == --* ]]; then
    echo 'usage: perf-fbo-passes.sh [serial]' >&2
    return 1
  fi
  git rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
  local log
  log=$(acq_x86_log perf-fbo-passes 50 OG_RECHARGED=0 OG_HDR=0 OG_HDR_OUT=0) || {
    echo '[acquis/perf-fbo-passes] NON PROUVE : course x86 indisponible' >&2
    return 1
  }
  fbo_check_cache "$log" || return 1
  fbo_check_log "$log"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  fbo_main "$@"
fi
