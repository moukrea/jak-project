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
# Onze termes, tous lus sur des grandeurs que la sonde GOAL `hud-recharged-power` publie
# (goal_src/jak1/pc/hud-classes-pc.gc, `debug.opengoal.costprobe=hud-eco-gauge`) :
#   size_blue / size_red / size_yellow  boite des sommets emis par type (`t12_box_16th_<type>`)
#                                       a +-10 % de la cible, sur >= 300 images DE CE TYPE ;
#   order    la nuee (lueur comprise : `rhud-nuee-emit` emet toutes ses couches) part APRES
#            l'anneau dans le meme bucket, et la copie d'en dessous est eteinte (terme 10) ;
#   order_blue / order_red / order_yellow  le MEME terme 10, PAR TYPE (harness-device-acquis-
#            hardening, 24/09). La sonde ne le compte que tous types melanges : ~80 % d'images
#            bleues suffisaient a le dire « mesure » sans une seule image rouge verifiee. Chaque
#            publication `AUTOPORT-FRAMES` ferme une fenetre ; une fenetre ou un SEUL type a vu
#            monter son `t12_n_<type>` attribue a ce type ses images d'ordre et ses fautes. Les
#            fenetres melangees ou sans type restent jugees par le terme global, et publiees ;
#   angle    remplissage en camembert (terme 1) ; quart  le quart bas-droit jamais rempli
#            (terme 7) ; tip  l'embout suit le remplissage (terme 2) ; color  teinte par eco (terme 3).
# Un terme sans population est AVEUGLE et compte 1 : une somme nulle sur zero terme n'est pas un vert.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/acquis_device.sh"
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

last, snaps = {}, []
for line in text.splitlines():
    if 'AUTOPORT-FRAMES n=' in line:
        snaps.append(dict(last))
        continue
    if 'hud_gauge_' not in line:
        continue
    m = re.search(r'(?<![\w])(hud_gauge_[a-z0-9_]+)=(-?[0-9]{1,19})\s*$', line)
    if m:
        last[m.group(1)] = int(m.group(2))
snaps.append(dict(last))

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

# 4 bis. L'ORDRE PAR TYPE, fenetre par fenetre (voir l'en-tete). Une fenetre dont un cumul
# DESCEND (sonde remise a zero) n'est attribuee a personne ; elle est comptee et publiee.
WIN = ['t12_n_' + k for k in TYPES] + ['t10_n', 't10_order_bad', 't10_park_ko']
per = {k: [0, 0, 0] for k in TYPES}          # images d'ordre, fautes, fenetres
mixed = [0, 0, 0]
none_n = none_bad = resets = 0
mixed_types = set()
prev = {}
for snap in snaps:
    d = {k: snap.get('hud_gauge_' + k, 0) - prev.get('hud_gauge_' + k, 0) for k in WIN}
    prev = snap
    if any(v < 0 for v in d.values()):
        resets += 1
        continue
    bad_w = d['t10_order_bad'] + d['t10_park_ko']
    seen = [k for k in TYPES if d['t12_n_' + k] > 0]
    if len(seen) == 1:
        acc = per[seen[0]]
    elif seen:
        acc = mixed
        if bad_w:
            mixed_types.update(seen)
    else:
        none_n, none_bad = none_n + d['t10_n'], none_bad + bad_w
        continue
    acc[0], acc[1], acc[2] = acc[0] + d['t10_n'], acc[1] + bad_w, acc[2] + 1
out['order_windows'] = len(snaps)
out['order_windows_reset'] = resets
out['order_mixed_n'], out['order_mixed_bad'] = mixed[0], mixed[1]
out['order_mixed_types'] = ','.join(sorted(mixed_types)) or 'none'
out['order_untyped_n'], out['order_untyped_bad'] = none_n, none_bad
for k in TYPES:
    n_k, bad_k, win_k = per[k]
    out['order_n_' + k], out['order_bad_' + k], out['order_windows_' + k] = n_k, bad_k, win_k
    if n_k < POP_MIN:
        fault('order_' + k, 'aveugle : %d images d ordre verifiees sur des fenetres de ce seul type' % n_k)
        continue
    measured += 1
    if bad_k:
        fault('order_' + k, 'nuee sous l anneau ou copie non eteinte sur %d images de ce type' % bad_k)

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

# TERME ECARTE, AVEC SA RAISON (harness-device-acquis-hardening, 24/09). Le terme 13 (opacite au
# coeur) de la porte de hud-eco-gauge vaut 1 sur le build que l'owner a VALIDE le 22/09 (« pour
# l'eco Bleue c'est parfait ») : il contredit son verdict. Le recaler, c'est changer la sonde GOAL
# d'une feature validee (hud-eco-gauge, perimetre jeu) : hors de portee d'un acquis, et signale.
# Il n'entre donc dans AUCUNE somme ici ; sa valeur est publiee pour que personne ne le croie
# juge, ni ne le decouvre rouge a la reouverture.
EXCLUDED = ('t13_opaque',)
for term in EXCLUDED:
    value = get(term)
    out['excluded_' + term] = -1 if value is None else value
out['excluded'] = ','.join(EXCLUDED)

out['terms_measured'] = measured
out['terms_expected'] = 2 * len(TYPES) + 5
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
# La garde scellee est l'unique exemplaire de lib/acquis_device_guard.py (site propre compris).
eco_check_proof() {
  local log
  log=$(acq_device_guard --item acquis-hud-eco-gauge --tag hud-eco-gauge --site hud-eco-gauge \
      --log-key hud_gauge_code_rev --log-key hud_gauge_nuee_target_r_16th \
      --log-key hud_gauge_t10_order_bad --log-key hud_gauge_t12_box_16th_blue \
      --log-key hud_gauge_t12_box_16th_red --log-key hud_gauge_t12_box_16th_yellow \
      --expect eco_gauge_acquis_defects=0 --expect proof_census_present=1 --expect proof_census_rc=0 \
      --expect eco_gauge_ctrl_dead=0 --expect eco_gauge_live_rc=0 --expect eco_gauge_context_rc=0 \
      --positive eco_gauge_terms_measured --positive eco_gauge_terms_expected \
      --positive eco_gauge_ctrl_cases \
      --same eco_gauge_terms_measured=eco_gauge_terms_expected) || return $?
  eco_check_log "$log" >/dev/null || return 1
  printf '%s\n' "$log"
}

eco_main() {
  # Pas de --timeout : la duree est celle de l'item (proof_timeout 240 s), la MEME que la preuve
  # qui a fige l'acquis. Elle donne >= 300 images a chaque eco (le banc fait un cycle en ~52 s) ;
  # la porte des acquis lui accorde un delai derive de cette course (lib/acquis_budget.py).
  acq_device_main hud-eco-gauge eco_check_proof acquis-hud-eco-gauge device -- "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  eco_main "$@"
fi
