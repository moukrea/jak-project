#!/usr/bin/env bash
# DIRECTIVES v900d5673aa — acquis de la jauge d'eco : juge la course USB courante, puis prouve
# que le juge DISTINGUE en rejouant le MEME journal avec un defaut seme a chaque fois.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
D=${AUTOPORT_CENSUS_DIR:-.autoport/reports/acquis-hud-eco-gauge}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
D=$(cd "$D" && pwd) || exit 1
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
arm=""
[ "${AUTOPORT_CENSUS_ARMED:-1}" != 0 ] || arm=-off
ENGINE=$(python3 .autoport/lib/impossible.py name engine "$arm") || exit 1

# proof_run fournit ce journal avant de composer/sceller la preuve ; aucune acquisition imbriquee.
. .autoport/acquis/hud-eco-gauge.sh
eco_check_log "$D/$ENGINE" eco_gauge_ > "$D/notes/eco-live.kv" 2> "$D/notes/eco-live.log"
live_rc=$?
cat "$D/notes/eco-live.log" >&2
context_rc=1
if [ "${AUTOPORT_CENSUS_ID:-}" = acquis-hud-eco-gauge ] &&
   [ "${AUTOPORT_CENSUS_ARMED:-}" = 1 ] &&
   grep -qx 'zf_context_mode=device' "${AUTOPORT_CENSUS_CONTEXT:-/dev/null}"; then
  context_rc=0
fi

# CONTROLES SEMES. Chaque cas reecrit TOUTES les occurrences d'une cle du journal vivant dans
# une copie jetable, rejoue le juge, et doit rougir en AJOUTANT exactement le terme seme :
#   size_<type> : la boite du type ramenee a 377/16, la taille de l'essai 17 que l'owner a
#                 refusee (« au moins deux fois plus grosses ») ; les deux autres types intacts ;
#   order       : une image ou la nuee part AVANT l'anneau ;
#   blind_red   : la population rouge effacee — le juge doit dire « aveugle », pas « tenu ».
# Un controle qui ne mord pas compte 1 dans eco_gauge_acquis_defects : un juge qui ne distingue
# rien ne protege rien.
python3 - "$D/$ENGINE" "$D/notes" "$live_rc" "$context_rc" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

log, notes, live_rc, context_rc = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
live = {}
for line in (notes / 'eco-live.kv').read_text().splitlines():
    key, _, value = line.partition('=')
    live[key] = value
try:
    text = log.read_text(errors='replace')
except OSError:
    text = ''

def seed(key, value):
    pattern = re.compile(r'(?<![\w])(' + key + r')=-?[0-9]+(\s*)$', re.M)
    if value is None:
        return re.subn(r'^.*(?<![\w])' + key + r'=.*\n?', '', text, flags=re.M)
    return pattern.subn(lambda m: m.group(1) + '=' + str(value) + m.group(2), text)

cases = [('size_' + k, 'hud_gauge_t12_box_16th_' + k, 377, 'size_' + k) for k in ('blue', 'red', 'yellow')]
cases += [('order', 'hud_gauge_t10_order_bad', 1, 'order'),
          ('blind_red', 'hud_gauge_t12_n_red', None, 'size_red')]
out, dead = [], 0
for name, key, value, want in cases:
    seeded, hits = seed(key, value)
    path = notes / ('eco-ctrl-' + name + '.log')
    path.write_text(seeded)
    run = subprocess.run(['bash', '-c', '. .autoport/acquis/hud-eco-gauge.sh; eco_check_log "$1" x_', '_', str(path)],
                         capture_output=True, text=True)
    got = dict(l.partition('=')[::2] for l in run.stdout.splitlines() if '=' in l)
    faulty = got.get('x_faulty', '?')
    # Le terme seme doit APPARAITRE, et lui seul : la difference avec le verdict vivant isole la
    # discrimination de l'etat du build. Un terme deja rouge en vrai ne peut pas prouver qu'il mord.
    added = set(faulty.split(',')) - set(live.get('eco_gauge_faulty', '').split(','))
    bite = int(hits > 0 and run.returncode == 1 and added == {want})
    dead += 1 - bite
    shown = {'size_blue': 'x_box_16th_blue', 'size_red': 'x_box_16th_red',
             'size_yellow': 'x_box_16th_yellow', 'order': 'x_order_bad', 'blind_red': 'x_n_red'}[name]
    out += ['eco_gauge_ctrl_%s_seeded_lines=%d' % (name, hits),
            'eco_gauge_ctrl_%s_value=%s' % (name, got.get(shown, '?')),
            'eco_gauge_ctrl_%s_rc=%d' % (name, run.returncode),
            'eco_gauge_ctrl_%s_named=%s' % (name, faulty),
            'eco_gauge_ctrl_%s_terms_measured=%s' % (name, got.get('x_terms_measured', '?')),
            'eco_gauge_ctrl_%s_bite=%d' % (name, bite)]
    (notes / ('eco-ctrl-' + name + '.stderr')).write_text(run.stderr)

live_bad = int(live.get('eco_gauge_check_defects', '1') or 1) if live_rc in (0, 1) else 1
defects = live_bad + dead + int(context_rc != 0)
for key, value in live.items():
    print(key + '=' + value)
print('\n'.join(out))
print('eco_gauge_ctrl_cases=%d' % len(cases))
print('eco_gauge_ctrl_dead=%d' % dead)
print('eco_gauge_live_rc=%d' % live_rc)
print('eco_gauge_context_rc=%d' % context_rc)
print('eco_gauge_acquis_defects=%d' % defects)
PY
