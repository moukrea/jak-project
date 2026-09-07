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
# LE MASTER EST POSE PAR LE LANCEUR, PAS PAR LE MOTEUR (item `refset-replay-stable`).
# `refset::enabled()` posait `OG_RECHARGED=0` a sa premiere execution, c'est-a-dire a la premiere
# image GOAL. Le fil de chargement, lui, avait deja choisi : mesure du 2026-09-06,
# `HD-MODELS fr3-select GAME: ENHANCED (external)` est journalise 3,9 s AVANT
# `[recharged-master] override -> 0`. Le niveau commun `GAME.fr3` — jamais evince, dessine dans
# les 16 etapes des DEUX jeux — partait donc en modeles HD alors que l'etape 1 veut le master
# ETEINT, et ce choix ne se refait jamais. Lequel des deux fils gagne depend de la charge de la
# machine : c'est une decision BINAIRE, globale a la course, qui explique un ecart bimodal.
# On la rend impossible au POINT DE PRODUCTION : la variable existe avant le premier octet
# execute. La premiere etape du plan est ORIGINE (master OFF), donc la valeur posee ici est
# exactement celle que le plan demande.
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
# LA TOURNEE COMPLETE DURE ~15 MIN, PAS 6. 26 vantages x 3 jeux, 174 etapes, et 26 arrivees qui
# paient chacune un chargement de niveau : 26*900 + 148*180 = 50040 frames de LOGIQUE, soit
# ~850 s a 60 img/s. Le defaut de 360 s coupait la course au 7e vantage, et une course coupee
# rend 254 — pas une mesure. `OG_REFSET_VANTAGES=legacy` (voir refset.cpp) restreint la tournee
# au vantage historique pour les items qui ont ete valides sur lui.
TIMEOUT="${2:-1500}"

BIN=build/game/gk
[ -s "$BIN" ] || { echo "refset: $BIN absent — bâtis d'abord (cmake --build build --target gk -j)" >&2; exit 3; }

# LE VERROU DE LIVRAISON, PRIS ICI ET PAS AILLEURS. Le 2026-09-07 a 08:33:17 une tournee de
# capture est morte en SIGSEGV a son 23e niveau : `link finish: cave-trap` puis un saut dans du
# code AArch64 execute par un `gk` x86. La cause est datee a la seconde — `build_arm64_full_
# consistent.sh:30` fait son `(make-group "iso")` ARM64 *dans* `out/jak1/iso`, le repertoire
# `-iso-data` de la course en cours, et ne restaure le x86 qu'a sa ligne 47. Le `ROB.DGO` lu par
# le `gk` contenait 20 prologues `stp x29,x30,[sp,#-16]!` ; celui d'aujourd'hui, reconstruit en
# x86, en contient zero. Ce n'etait pas un defaut de `robocave` : c'etait l'instrument reecrit
# sous la mesure. On rend la perte impossible au POINT DE PRODUCTION — le constructeur lit ce
# verrou (auto_build_apk.sh:331-349) et ne batit pas par-dessus — plutot que detectable apres
# coup. PID et `trap` obligatoires : un `touch` nu laisserait un verrou eternel si la course
# meurt, et le constructeur perime de toute facon un verrou dont le PID ne repond plus.
LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  holder=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK")
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    echo "refset: livraison en cours ($(cat "$LOCK")) — on ne mesure pas sous un constructeur" >&2
    exit 4
  fi
  echo "refset: verrou orphelin (pid=$holder mort) — on le remplace" >&2
fi
printf 'refset.sh %s pid=%s started=%s\n' "$MODE" "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

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

# LE PLAN FINIT AVANT LE TIMEOUT, ET IL FAUT EN PROFITER. Le moteur imprime `REFSET done` des
# que la derniere etape est consommee — apres avoir ecrit ses PNG, son registre de rejeux et
# TOUTES ses grandeurs (`publish_flaky` puis `publish_state`, refset.cpp:2031-2045). Mais rien
# n'arretait `gk` : mesure du 2026-09-07, la tournee de calibrage a fini son plan en 700 s et
# est restee a tourner dans le vide jusqu'a son timeout de 2400 s. Sur les six courses d'une
# sequence complete, c'etait deux heures de rien. On attend donc la LIGNE, pas l'horloge, et le
# timeout redevient ce qu'il doit etre : un filet, pas la duree de la course.
# `kill` PAR PID EXACT, jamais par motif (DIRECTIVES) : le PID est celui du `timeout`, qui
# transmet le signal a son `gk`.
echo "[refset] $MODE (plafond ${TIMEOUT}s, census armed=$ARMED) -> $LOG" >&2
stdbuf -oL -eL env \
  OG_REFSET="$MODE" \
  OG_REFSET_DIR=.autoport/refset \
  OG_RECHARGED=0 OG_RT_LIGHT=0 \
  OG_LEVEL_WARP=village1-hut \
  OG_LEVEL_WARP_POS="-116 14 40" \
  OG_WANT_LEVELS=village1,beach \
  OG_WANT_DISPLAY=beach,display \
  OG_PAD_REPLAY_REPLAY="$DEMO" \
  ${REFSET_TRACE:+OG_PAD_REPLAY_TRACE="$REFSET_TRACE"} \
  ${REFSET_SETTLE:+OG_REFSET_SETTLE="$REFSET_SETTLE"} \
  ${REFSET_LOAD_SETTLE:+OG_REFSET_LOAD_SETTLE="$REFSET_LOAD_SETTLE"} \
  ${REFSET_VANTAGES:+OG_REFSET_VANTAGES="$REFSET_VANTAGES"} \
  ${REFSET_PHASES:+OG_REFSET_PHASES="$REFSET_PHASES"} \
  ${REFSET_HOURS:+OG_REFSET_HOURS="$REFSET_HOURS"} \
  ${REFSET_CAM:+OG_REFSET_CAM="$REFSET_CAM"} \
  ${REFSET_CAM_OFF:+OG_REFSET_CAM_OFF="$REFSET_CAM_OFF"} \
  ${REFSET_PITCH_BY_HOUR:+OG_REFSET_PITCH_BY_HOUR="$REFSET_PITCH_BY_HOUR"} \
  ${REFSET_YAW_BY_HOUR:+OG_REFSET_YAW_BY_HOUR="$REFSET_YAW_BY_HOUR"} \
  ${REFSET_CAM_BY_HOUR:+OG_REFSET_CAM_BY_HOUR="$REFSET_CAM_BY_HOUR"} \
  OG_PACE_MEASURE=1 \
  AUTOPORT_FEATURE=lighting-census \
  AUTOPORT_FEATURE_ARMED="$ARMED" \
  timeout -k 5 "$TIMEOUT" "$BIN" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
while kill -0 "$GKPID" 2>/dev/null; do
  if grep -aq '^REFSET done ' "$LOG" 2>/dev/null; then
    sleep 5                      # le temps que le dernier octet parte du tampon
    echo "[refset] plan termine — on arrete gk (pid=$GKPID)" >&2
    kill "$GKPID" 2>/dev/null
    break
  fi
  sleep 3
done
wait "$GKPID"; rc=$?
# `REFSET done` present = le plan est alle au bout ; le code de sortie du `kill` ne dit rien.
grep -aq '^REFSET done ' "$LOG" 2>/dev/null && rc=0

echo "--- REFSET ---" >&2
grep -aE '^(REFSET|TOD-PIN|LEVEL-WARP|pad_replay)' "$LOG" | tail -40 >&2
echo "--- grandeurs ---" >&2
grep -aoE '^(refset|light_census|gpu_ms|gpu_timer)[A-Za-z0-9_]*=[^ ]*' "$LOG" | sort -u | tail -80 >&2
echo "--- couverture ---" >&2
grep -aoE '^refset_(levels|views|shot_views|sky_views|interior_views|levels_missing|levels_playable|probe_frames)[A-Za-z0-9_]*=[^ ]*' "$LOG" | sort -u >&2
grep -aoE '^refset_levels(_list|_missing_list)=[^ ]*' "$LOG" | sort -u >&2
echo "--- ciel par creneau ---" >&2
grep -aoE '^refset_(bgh_[a-z0-9_]+|sky_[a-z_]*)=[^ ]*' "$LOG" | sort -u >&2
grep -aoE '^refset_cam_[a-z]+=[0-9]+' "$LOG" | sort -u >&2

if [ "$MODE" = replay ]; then
  MD=$(grep -aoE '^refset_replay_maxdiff=[0-9]+' "$LOG" | tail -1 | cut -d= -f2)
  echo "[refset] refset_replay_maxdiff=${MD:-absent} (gk sorti en $rc)" >&2
  [ "${MD:-1}" = 0 ] || exit 1
fi
exit 0
