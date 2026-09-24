#!/usr/bin/env bash
# census/harness-device-acquis-hardening.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint le journal de course.
#
# LA GRANDEUR : `device_acquis_defects` = somme de cinq termes, chacun LU SUR DU VIVANT puis
# CONTROLE (positif fabrique + negatif) :
#   1 guard   une seule garde scellee : aucun acquis ne la recopie, les acquis appareil l'appellent ;
#             les bancs pytest l'exercent (site vacant, sceau, serial, TTL...).
#   2 site    la garde, sur les VRAIES preuves des acquis appareil, lit la prise du site de la
#             feature gardee (> 0) ; `FEATURE acquis-... hits=` n'est que le compteur global.
#   3 budget  chaque acquis recoit max(plancher, course + marge) ; l'orchestrateur l'applique.
#   4 order   l'ordre des couches de la jauge est juge PAR TYPE sur le vrai journal ; une faute
#             semee dans une fenetre rouge du MEME journal est nommee `order_red`.
#   5 t13     le terme 13 est ecarte, publie, et une valeur semee ne change aucun verdict.
# INCONNU = DEFAUT : une cle absente, un controle qui ne mord pas, un negatif qui rougit comptent.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "device_acquis_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP=.autoport
D=${AUTOPORT_CENSUS_DIR:-$AP/reports/harness-device-acquis-hardening}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
LIVE_TTL=86400

# 1 + 3 + 4 + 5 : les bancs (controles positifs et negatifs fabriques).
timeout 400 python3 -m pytest -q -p no:cacheprovider \
  "$AP/tests/harness/test_acquis_device_hardening.py" \
  "$AP/tests/harness/test_acquis_perf_dma_chain_copies.py" > "$D/notes/bench.log" 2>&1
bench_rc=$?

# 2 : la garde commune sur les VRAIES preuves appareil. L'age n'est pas la question ici (la porte
# des acquis garde son TTL de 1800 s) ; sceau, binaire, sources et site le sont.
for spec in hud-eco-gauge perf-dma-chain-copies; do
  ACQ_CACHE_TTL=$LIVE_TTL bash -c '. "$1"; case "$2" in
      hud-eco-gauge) eco_check_proof ;; perf-dma-chain-copies) dma_check_proof ;; esac' \
    _ "$AP/acquis/$spec.sh" "$spec" > "$D/notes/live-$spec.out" 2> "$D/notes/live-$spec.err"
  echo "$?" > "$D/notes/live-$spec.rc"
done

python3 "$AP/lib/acquis_budget.py" > "$D/notes/budget.kv" 2> "$D/notes/budget.err"

python3 - "$D/notes" "$bench_rc" "$LIVE_TTL" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

notes, bench_rc, live_ttl = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
AP = Path('.autoport')
out, faults = [], []

def pub(key, value):
    out.append('%s=%s' % (key, value))

def fault(term, why):
    faults.append(term + ':' + why)

# ---------------------------------------------------------------- 1. garde commune
bench = (notes / 'bench.log').read_text(errors='replace')
m = re.search(r'(\d+) passed', bench)
passed = int(m.group(1)) if m else 0
failed = sum(int(x) for x in re.findall(r'(\d+) (?:failed|error)', bench))
pub('dah_bench_rc', bench_rc)
pub('dah_bench_passed', passed)
pub('dah_bench_failed', failed)
if bench_rc != 0 or failed or passed == 0:
    fault('guard', 'bancs rc=%d passed=%d failed=%d' % (bench_rc, passed, failed))
scripts = [p for p in sorted((AP / 'acquis').glob('*.sh')) if p.name != '_lib.sh']
# Acquis APPAREIL = celui qui juge une preuve SCELLEE d'une course `acquis-<x> device`. Un acquis
# qui sonde adb en direct (font-urbanist) n'a pas de preuve scellee a garder : compte a part.
device = [p for p in scripts if re.search(r'\bacquis-[a-z0-9-]+ device\b', p.read_text())]
live_adb = [p.stem for p in scripts if p not in device and re.search(r'\badb\b', p.read_text(), re.I)]
copies = sum(p.read_text().count('proof_binary_checked_before_measure') for p in scripts)
callers = [p.stem for p in device if 'acq_device_guard ' in p.read_text()]
pub('dah_acquis_total', len(scripts))
pub('dah_device_acquis', len(device))
pub('dah_device_acquis_list', ','.join(p.stem for p in device) or '-')
pub('dah_live_adb_acquis_list', ','.join(live_adb) or '-')
pub('dah_guard_copies_in_acquis', copies)
pub('dah_guard_callers', len(callers))
if not device or copies or len(callers) != len(device):
    fault('guard', 'appareil=%d copies=%d appelants=%d' % (len(device), copies, len(callers)))

# ---------------------------------------------------------------- 2. site propre, sur le vivant
pub('dah_live_ttl_s', live_ttl)
for p in device:
    name = p.stem
    rc = (notes / ('live-%s.rc' % name)).read_text().strip() if (notes / ('live-%s.rc' % name)).exists() else '?'
    err = (notes / ('live-%s.err' % name)).read_text(errors='replace') if (notes / ('live-%s.err' % name)).exists() else ''
    m = re.search(r'preuve admise : .* site=(\S+) prises=(\d+)', err)
    hits = int(m.group(2)) if m and m.group(1) == name else 0
    proof = (AP / 'reports' / ('acquis-' + name) / 'proof.txt')
    ptext = proof.read_text(errors='replace') if proof.exists() else ''
    g = re.search(r'^FEATURE acquis-%s armed=1 hits=(\d+)' % re.escape(name), ptext, re.M)
    key = name.replace('-', '_')
    pub('dah_live_rc_' + key, rc)
    pub('dah_site_hits_' + key, hits)
    pub('dah_feature_global_hits_' + key, g.group(1) if g else -1)
    if rc != '0' or hits <= 0:
        fault('site', '%s rc=%s prises=%d : %s' % (name, rc, hits, err.strip().splitlines()[-1:] or '-'))

# ---------------------------------------------------------------- 3. delai derive
budget = dict(l.split('=', 1) for l in (notes / 'budget.kv').read_text().splitlines() if '=' in l)
floor, margin = int(budget.get('acquis_budget_floor_s', -1)), int(budget.get('acquis_budget_margin_s', -1))
pub('dah_budget_floor_s', floor)
pub('dah_budget_margin_s', margin)
pub('dah_budget_scripts', budget.get('acquis_budget_scripts', -1))
if floor <= 0 or margin <= 0 or budget.get('acquis_budget_scripts') != str(len(scripts)):
    fault('budget', 'table des delais incomplete')
for p in device:
    key = re.sub(r'[^A-Za-z0-9_]', '_', p.stem)
    b = int(budget.get('acquis_budget_' + key, -1))
    course = int(budget.get('acquis_budget_%s_course' % key, -1))
    pub('dah_budget_' + key, b)
    pub('dah_budget_course_' + key, course)
    if course <= 0 or b < max(floor, course + margin):
        fault('budget', '%s delai=%d course=%d' % (p.stem, b, course))

# ---------------------------------------------------------------- 4 + 5. jauge : ordre par type, t13
engine = AP / 'reports/acquis-hud-eco-gauge/proof-engine.log'
text = engine.read_text(errors='replace') if engine.exists() else ''

def judge(body, tag):
    path = notes / ('eco-%s.log' % tag)
    path.write_text(body)
    run = subprocess.run(['bash', '-c', '. "$1"; eco_check_log "$2" x_', '_',
                          str(AP / 'acquis/hud-eco-gauge.sh'), str(path)],
                         capture_output=True, text=True, timeout=120)
    return run.returncode, dict(l.split('=', 1) for l in run.stdout.splitlines() if '=' in l)

live_rc, live = judge(text, 'live')
TYPES = ('blue', 'red', 'yellow')
pub('dah_order_live_rc', live_rc)
pub('dah_order_live_faulty', live.get('x_faulty', '?'))
typed = 0
for k in TYPES:
    n, bad = live.get('x_order_n_' + k, '-1'), live.get('x_order_bad_' + k, '-1')
    pub('dah_order_n_' + k, n)
    pub('dah_order_bad_' + k, bad)
    typed += int(int(n) >= 300 and bad == '0')
pub('dah_order_types_measured', typed)
pub('dah_order_mixed_n', live.get('x_order_mixed_n', -1))
pub('dah_order_untyped_n', live.get('x_order_untyped_n', -1))
if live_rc != 0 or typed != len(TYPES):
    fault('order', 'vivant rc=%d types mesures=%d/3' % (live_rc, typed))

# CONTROLE POSITIF sur le MEME journal : une faute d'ordre de plus a partir de la premiere
# fenetre ou SEUL le rouge a monte ET ou la sonde republie `t10_order_bad`.
lines = text.splitlines(keepends=True)
state, prev, start, target = {}, {}, 0, None
WIN = ['t12_n_' + k for k in TYPES] + ['t10_order_bad']
for i, line in enumerate(lines + ['AUTOPORT-FRAMES n=0\n']):
    if 'AUTOPORT-FRAMES n=' in line:
        d = {k: state.get(k, 0) - prev.get(k, 0) for k in WIN}
        seen = [k for k in TYPES if d['t12_n_' + k] > 0]
        has_line = any('hud_gauge_t10_order_bad=' in l for l in lines[start:i])
        if seen == ['red'] and has_line and target is None:
            target = start
        prev, start = dict(state), i + 1
        continue
    mm = re.search(r'(?<![\w])hud_gauge_([a-z0-9_]+)=(-?\d+)\s*$', line)
    if mm:
        state[mm.group(1)] = int(mm.group(2))
seeded = 0
if target is not None:
    for i in range(target, len(lines)):
        mm = re.search(r'((?<![\w])hud_gauge_t10_order_bad=)(-?\d+)(\s*)$', lines[i])
        if mm:
            lines[i] = lines[i][:mm.start()] + mm.group(1) + str(int(mm.group(2)) + 1) + mm.group(3)
            seeded += 1
pos_rc, pos = judge(''.join(lines), 'ctrl-order-red')
pos_named = set(pos.get('x_faulty', '').split(','))
bite_order = int(seeded > 0 and pos_rc == 1 and 'order_red' in pos_named
                 and not pos_named & {'order_blue', 'order_yellow'})
pub('dah_ctrl_order_red_seeded_lines', seeded)
pub('dah_ctrl_order_red_named', pos.get('x_faulty', '?'))
pub('dah_ctrl_order_red_bite', bite_order)
if not bite_order:
    fault('order', 'controle positif muet')

# 5. t13 ecarte : publie sur le vivant, et une valeur semee ne change RIEN au verdict.
t13_live = live.get('x_excluded_t13_opaque', '?')
pub('dah_t13_excluded', live.get('x_excluded', '?'))
pub('dah_t13_value_on_validated_build', t13_live)
seed = re.sub(r'((?<![\w])hud_gauge_t13_opaque=)-?\d+', r'\g<1>9', text)
neg_rc, neg = judge(seed, 'ctrl-t13')
inert = int(neg_rc == live_rc and neg.get('x_faulty') == live.get('x_faulty')
            and neg.get('x_excluded_t13_opaque') == '9' and seed != text)
pub('dah_ctrl_t13_inert', inert)
if live.get('x_excluded') != 't13_opaque' or t13_live in ('?', '-1') or not inert:
    fault('t13', 'exclusion absente, valeur non publiee ou terme encore juge')

for term in ('guard', 'site', 'budget', 'order', 't13'):
    pub('dah_term_' + term, sum(1 for f in faults if f.startswith(term + ':')))
pub('dah_terms', 5)
print('\n'.join(out))
for f in faults:
    print('[device-acquis] DEFAUT ' + f, file=sys.stderr)
print('device_acquis_defects=%d' % len(faults))
PY
