#!/usr/bin/env bash
# DIRECTIVES v900d5673aa — acquis Android de la jauge d'eco rechargee, sourceable sans acquisition.
# Le census fournit son propre journal ; seule eco_main peut appeler proof_run.
#
# CE QUI EST FIGE — le build que l'owner a VALIDE le 22/09 a 23:23 (« pour l'eco Bleue c'est
# parfait ») est celui publie a 23:10 depuis e4f7e2ba32, CGO rebatis par `make-group iso :force` :
# il porte l'essai 18 de hud-eco-gauge (d7abe36ba7), cible de la nuee RHUD_NUEE_TARGET_R = 47,20
# unites de canevas = 755/16. Les 377/16 de l'essai 17 sont la taille que l'owner avait REFUSEE
# a 19:41 (« au moins deux fois plus grosses ») : figer 377 protegerait l'etat rejete.
#
# Huit termes, tous lus sur des grandeurs que la sonde GOAL `hud-recharged-power` publie
# (goal_src/jak1/pc/hud-classes-pc.gc, `debug.opengoal.costprobe=hud-eco-gauge`) :
#   size_blue / size_red / size_yellow  boite des sommets emis par type (`t12_box_16th_<type>`)
#                                       a +-10 % de la cible, sur >= 300 images DE CE TYPE ;
#   order    la nuee (lueur comprise : `rhud-nuee-emit` emet toutes ses couches) part APRES
#            l'anneau dans le meme bucket, et la copie d'en dessous est eteinte (terme 10) ;
#   angle    remplissage en camembert (terme 1) ; quart  le quart bas-droit jamais rempli
#            (terme 7) ; tip  l'embout suit le remplissage (terme 2) ; color  teinte par eco (terme 3).
# Un terme sans population est AVEUGLE et compte 1 : une somme nulle sur zero terme n'est pas un vert.
eco_check_log() {
  python3 - "${1:-}" "${2:-eco_gauge_}" <<'PY'
import re
import sys
from pathlib import Path

TAG = '[acquis/hud-eco-gauge]'
TARGET_16TH = 755        # 47,20 x 16 : cible du build valide (essai 18)
SIZE_TOL_16TH = 75       # 10 % de la cible. Le 2 % d'abord pose (tire de l'essai 17, a la
                         # moitie de l'echelle) rougissait le build VALIDE lui-meme : appareil
                         # 23/09, jaune 771/16 pour 755 (+2,1 %) — un MAXIMUM sur ~1 900 images.
                         # 10 % attrape toutes les regressions visees : retour a 377 (-50 %),
                         # types sans mise a l'echelle commune (bruts 392/1170/5545, x3 a x14).
CODE_REV_MIN = 18        # sonde de l'essai 18 : la premiere qui mesure le build valide
POP_MIN = 300            # RHUD_GB_MIN, le plancher de population de la sonde elle-meme
TYPES = ('blue', 'red', 'yellow')
path, prefix = sys.argv[1], sys.argv[2]

try:
    text = Path(path).read_text(errors='replace')
except OSError as exc:
    print(TAG + ' NON PROUVE : journal indisponible : ' + str(exc), file=sys.stderr)
    sys.exit(2)

last = {}
for line in text.splitlines():
    if 'hud_gauge_' not in line:
        continue
    m = re.search(r'(?<![\w])(hud_gauge_[a-z0-9_]+)=(-?[0-9]{1,19})\s*$', line)
    if m:
        last[m.group(1)] = int(m.group(2))

def get(key):
    return last.get('hud_gauge_' + key)

faults, measured, out = [], 0, {}

def fault(name, why):
    faults.append(name)
    print(TAG + ' PLUS TENU : ' + name + ' : ' + why, file=sys.stderr)

if re.search(r'fatal signal|(?:caught|received|killed by|terminated by)[^\r\n]*SIG(?:SEGV|ILL|ABRT|BUS|FPE)|^\s*SIG(?:SEGV|ILL|ABRT|BUS|FPE)\b|segmentation fault|illegal instruction|core dumped|assertion.*failed|terminate called|AddressSanitizer', text, re.I | re.M):
    fault('crash', 'crash connu dans le journal')

rev, target = get('code_rev'), get('nuee_target_r_16th')
out['code_rev'] = -1 if rev is None else rev
out['target_16th'] = -1 if target is None else target
out['target_want_16th'] = TARGET_16TH
out['size_tol_16th'] = SIZE_TOL_16TH
if rev is None or rev < CODE_REV_MIN:
    fault('code_rev', 'sonde absente ou anterieure au build valide (%s < %d)' % (rev, CODE_REV_MIN))
if target != TARGET_16TH:
    fault('target', 'cible publiee %s/16, validee %d/16' % (target, TARGET_16TH))

# 1-3. LA TAILLE, TYPE PAR TYPE, contre la cible figee (et non contre la cible publiee).
for k in TYPES:
    n, box = get('t12_n_' + k), get('t12_box_16th_' + k)
    out['n_' + k] = -1 if n is None else n
    out['box_16th_' + k] = -1 if box is None else box
    if n is None or box is None or n < POP_MIN:
        fault('size_' + k, 'aveugle : %s images de ce type, boite %s' % (n, box))
        continue
    measured += 1
    out['dev_permille_' + k] = (box - TARGET_16TH) * 1000 // TARGET_16TH
    if abs(box - TARGET_16TH) > SIZE_TOL_16TH:
        fault('size_' + k, 'boite %d/16 pour une cible de %d+-%d' % (box, TARGET_16TH, SIZE_TOL_16TH))

# 4. L'ORDRE DES COUCHES : la nuee par-dessus l'anneau, la copie d'en dessous eteinte.
n, cover, bad, park = (get(k) for k in ('t10_n', 't10_cover', 't10_order_bad', 't10_park_ko'))
out['order_n'], out['order_cover'] = (-1 if v is None else v for v in (n, cover))
out['order_bad'], out['order_park_ko'] = (-1 if v is None else v for v in (bad, park))
if None in (n, cover, bad, park) or n < POP_MIN or cover < POP_MIN:
    fault('order', 'aveugle : n=%s recouvrement=%s' % (n, cover))
else:
    measured += 1
    if bad or park:
        fault('order', 'nuee sous l anneau sur %d images, copie non eteinte sur %d' % (bad, park))

# 5-8. Termes de la sonde : leur valeur vaut deja 1 quand ils sont aveugles ; la population est
# relue quand meme, pour ne pas croire la sonde sur parole.
for name, term, pops in (('angle', 't1_angle', ('t1_n',)),
                         ('quart', 't7_quart', ('t7_n', 't7_base_ctrl')),
                         ('tip', 't2_tip', ('t2_n',)),
                         ('color', 't3_color', ('t3_n',))):
    value, ns = get(term), [get(p) for p in pops]
    out[name + '_term'] = -1 if value is None else value
    out[name + '_n'] = -1 if ns[0] is None else ns[0]
    if value is None or any(v is None or v < POP_MIN for v in ns):
        fault(name, 'aveugle : %s=%s populations=%s' % (term, value, ns))
        continue
    measured += 1
    if value != 0:
        fault(name, '%s=%d' % (term, value))

out['terms_measured'] = measured
out['terms_expected'] = len(TYPES) + 5
out['check_defects'] = len(faults)
out['faulty'] = ','.join(faults) or 'none'
for key, value in out.items():
    print(prefix + key + '=' + str(value))
if faults:
    sys.exit(1)
print(TAG + ' TENU : ' + ' '.join('%s=%s' % kv for kv in out.items()), file=sys.stderr)
PY
}

# 2 = preuve absente/perimee/invalide ; 1 = defaut mesure, sans reacquisition.
eco_check_proof() {
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

item = 'acquis-hud-eco-gauge'
directory = Path('.autoport/reports') / item
proof, log, seal = (directory / arm_name(kind) for kind in ('proof', 'engine', 'seal'))
data = {}

def reject(message, code=2):
    print(f'[acquis/hud-eco-gauge] NON PROUVE : {proof} '
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
    for key in ('hud_gauge_code_rev', 'hud_gauge_nuee_target_r_16th', 'hud_gauge_t10_order_bad',
                'hud_gauge_t12_box_16th_blue', 'hud_gauge_t12_box_16th_red',
                'hud_gauge_t12_box_16th_yellow'):
        matches = re.findall(r'(?<![\w])' + key + r'=([^\r\n]*)', text)
        if not matches or matches[-1].strip() != data.get(key):
            raise ValueError('journal/preuve divergent : ' + key)
except (OSError, ValueError, subprocess.CalledProcessError) as exc:
    reject(str(exc))

if data.get('crash') != '0' or not re.fullmatch(r'[0-9]{1,20}', data.get('frames', '')) or not 0 < int(data['frames']) <= 2**64 - 1:
    reject('crash ou population frames invalide', 1)
for key, expected in (('eco_gauge_acquis_defects', '0'), ('proof_census_present', '1'),
                      ('proof_census_rc', '0'), ('eco_gauge_ctrl_dead', '0'),
                      ('eco_gauge_live_rc', '0'), ('eco_gauge_context_rc', '0')):
    if data.get(key) != expected:
        reject('recensement refuse : ' + key + '=' + data.get(key, '?'), 1)
for key in ('eco_gauge_terms_measured', 'eco_gauge_terms_expected', 'eco_gauge_ctrl_cases'):
    if not re.fullmatch(r'[1-9][0-9]{0,5}', data.get(key, '')):
        reject('population du recensement invalide : ' + key, 1)
if data['eco_gauge_terms_measured'] != data['eco_gauge_terms_expected']:
    reject('terme(s) aveugle(s) : terms_measured != terms_expected', 1)
print(f'[acquis/hud-eco-gauge] preuve admise : {proof} '
      f'run_id={data["proof_run_id"]}', file=sys.stderr)
print(log)
PYPROOF
  ) && status=0 || status=$?
  [ "$status" = 0 ] || return "$status"
  eco_check_log "$log" >/dev/null || return 1
  printf '%s\n' "$log"
}

eco_main() {
  if [ "$#" -gt 1 ] || [[ "${1:-}" == --* ]]; then
    echo 'usage: hud-eco-gauge.sh [serial]' >&2
    return 1
  fi
  local root log status
  local ANDROID_SERIAL="${1:-${ANDROID_SERIAL:-}}"
  export ANDROID_SERIAL
  if [[ "$ANDROID_SERIAL" == *:* || "$ANDROID_SERIAL" == *_adb-tls-* || "$ANDROID_SERIAL" =~ [[:space:]] || "$ANDROID_SERIAL" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo '[acquis/hud-eco-gauge] NON PROUVE : serial USB requis' >&2
    return 1
  fi
  root=$(git rev-parse --show-toplevel) || return 1
  cd "$root" || return 1
  log=$(eco_check_proof) && status=0 || status=$?
  if [ "$status" = 2 ]; then
    # Pas de --timeout : la duree est celle de l'item (proof_timeout 240 s), la MEME que la preuve
    # qui a fige l'acquis. Elle donne >= 300 images a chaque eco (le banc fait un cycle en ~52 s)
    # et tient sous les 600 s que la porte des acquis accorde a un script.
    bash .autoport/lib/proof_run.sh acquis-hud-eco-gauge device || {
      echo '[acquis/hud-eco-gauge] NON PROUVE : course proof_run echouee' >&2
      return 1
    }
    log=$(eco_check_proof) || return 1
  elif [ "$status" != 0 ]; then
    return 1
  fi
  printf '[acquis/hud-eco-gauge] TENU : %s\n' "$log"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  eco_main "$@"
fi
