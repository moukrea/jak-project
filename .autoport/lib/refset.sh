#!/usr/bin/env bash
# refset.sh — LE JEU D'IMAGES DE REFERENCE A DEUX BRANCHES (SPEC-refonte-lumiere.md §7.3).
#
# CE QUE C'EST. Une course x86 deterministe qui, depuis un point de reprise nomme, parcourt
# DEUX jeux (ORIGINE = `recharged_master` OFF, RECHARGED = master ON + prereglage fige) x HUIT
# creneaux horaires, et pour chacun relit le tampon de couleur a une resolution FIXE.
# LE NIVEAU EST CHARGE AVANT LE WARP, PAS PENDANT. Les defauts des deux crochets valent 900
# ticks tous les deux : le chargement de `village1` et le `(start 'play ...)` partaient donc
# ensemble, et le decor arrivait par morceaux PENDANT les premieres images de jeu. La camera,
# dont le point de repos depend du chemin, se posait alors a un endroit legerement different
# a chaque course. Mesure du 2026-09-06, deux rejeux dans des conditions IDENTIQUES :
# maxdiff 255, ~27000 pixels sur 57600, boite englobante = l'image entiere, alors que la
# position de Jak est bit-identique sur 900 images de logique. Ici : niveaux voulus a 600,
# warp a 2700 — les crochets `want` gardent leurs defauts (900 / 1800) et le monde a ~30 s
# pour etre complet quand Jak apparait. NE PAS avancer OG_WANT_LEVELS_DELAY : a 600 le
# niveau `title` est encore actif, le chargement de `beach` demarre par-dessus et gk tombe
# en core dump (mesure du 2026-09-06).
#   capture : ecrit les references dans .autoport/refset/{origine,recharged}/hHH.png
#   replay  : recompare et laisse le MOTEUR publier `refset_replay_maxdiff` / `refset_replay_diffpx`
#
# QUAND LE REJOUER. A la fermeture de CHAQUE item de la refonte de l'eclairage :
#     bash .autoport/lib/refset.sh replay      # doit finir sur maxdiff=0
# ORIGINE ne bouge JAMAIS. Si RECHARGED bouge, c'est l'item qui doit le declarer, et lui seul
# recapture le jeu RECHARGED apres que le superviseur a tranche.
#
# CE SCRIPT N'ECRIT AUCUN CHAMP DE PREUVE. La preuve de l'item `lighting-census` se produit par
# `.autoport/lib/proof_run.sh lighting-census x86`, qui pose le meme environnement (voir
# `proof_env` de l'item dans backlog.yaml) et moissonne les memes lignes. Ce script-ci sert a
# CAPTURER les references et a les rejouer hors d'une course de preuve.
#
# DETERMINISME — les quatre leviers, tous preexistants dans cet arbre :
#   OG_LEVEL_WARP / _POS          point de reprise nomme (kmachine.cpp:5660)
#   OG_PAD_REPLAY_REPLAY          ancre + graine d'alea fixe + pas de temps fixe (pad_replay.h)
#   surcharge d'heure du moteur   reposee a chaque image (refset.cpp -> pc_get_tod_hour)
#   capture a resolution interne  320x180, msaa 1 : la fenetre de la machine n'entre pas en jeu
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

MODE="${1:-replay}"
case "$MODE" in capture|replay) ;; *) echo "usage: $0 <capture|replay> [timeout_s]" >&2; exit 2 ;; esac
TIMEOUT="${2:-360}"

BIN=build/game/gk
[ -s "$BIN" ] || { echo "refset: $BIN absent — bâtis d'abord (cmake --build build --target gk -j)" >&2; exit 3; }

DEMO=.autoport/refset/neutral.inputs
if [ ! -s "$DEMO" ]; then
  python3 - "$DEMO" <<'PY'
import struct, sys
open(sys.argv[1], 'wb').write(b'OGPADRP1' + struct.pack('<IIII', 2, 6, 0x0AD12345, 0) +
                              struct.pack('<q', 0) + b'\0' * 32)
PY
fi

LOG=".autoport/refset/refset-$MODE.log"
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  for x in /run/user/"$(id -u)"/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
fi
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# La CAPTURE se fait recensement DESARME, le REJEU recensement ARME : `maxdiff == 0` prouve
# alors, litteralement, que l'instrument pose par cet item ne change aucun pixel.
ARMED=1; [ "$MODE" = capture ] && ARMED=0

echo "[refset] $MODE pendant ${TIMEOUT}s (census armed=$ARMED) -> $LOG" >&2
stdbuf -oL -eL env \
  OG_REFSET="$MODE" \
  OG_REFSET_DIR=.autoport/refset \
  OG_LEVEL_WARP=village1-hut \
  OG_LEVEL_WARP_POS="-116 14 40" \
  OG_WANT_LEVELS=village1,beach \
  OG_WANT_DISPLAY=beach,display \
  OG_PAD_REPLAY_REPLAY="$DEMO" \
  ${REFSET_TRACE:+OG_PAD_REPLAY_TRACE="$REFSET_TRACE"} \
  ${REFSET_SETTLE:+OG_REFSET_SETTLE="$REFSET_SETTLE"} \
  OG_PACE_MEASURE=1 \
  AUTOPORT_FEATURE=lighting-census \
  AUTOPORT_FEATURE_ARMED="$ARMED" \
  timeout -k 5 "$TIMEOUT" "$BIN" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1
rc=$?

echo "--- REFSET ---" >&2
grep -aE '^(REFSET|TOD-PIN|LEVEL-WARP|pad_replay)' "$LOG" | tail -40 >&2
echo "--- grandeurs ---" >&2
grep -aoE '^(refset|light_census|gpu_ms|gpu_timer)[A-Za-z0-9_]*=[^ ]*' "$LOG" | sort -u | tail -60 >&2

if [ "$MODE" = replay ]; then
  MD=$(grep -aoE '^refset_replay_maxdiff=[0-9]+' "$LOG" | tail -1 | cut -d= -f2)
  echo "[refset] refset_replay_maxdiff=${MD:-absent} (gk sorti en $rc)" >&2
  [ "${MD:-1}" = 0 ] || exit 1
fi
exit 0
