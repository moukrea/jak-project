#!/usr/bin/env bash
# gfr_x86_leg.sh — Gfont-regression, jambe x86 : QUELLE POLICE EST LIEE, POUR QUELLES CHAINES.
#
#   usage : gfr_x86_leg.sh <tag> <mode>
#     mode = defaut      : settings.ini tel quel (toutes les portes a #t)
#            portes-off  : recharged-master? = #f, recharged-textures? = #f, load-custom-assets? = #t
#                          ET un PNG joueur gamefontnew/ascii.24lo.png (l'atlas D'ORIGINE) pose dans
#                          custom_assets/jak1/texture_replacements — les trois masques a la fois
#
# Ce que la jambe publie (dans $OUT/x86-<tag>.log) :
#   FONTTEX upload ...   ce que le chargeur a televerse pour chaque page de police, et sa source
#   FONTTEX bind ...     ce que le DESSIN DIRECT a lie pour tbp 0xe0000 (petite) / 0xe6000 (grande)
#   FONT-STR large=..    chaque chaine que draw-string a dessinee, avec la police choisie (trace
#                        armee depuis le listener, bornee a 400 appels, deux fois : titre + menu)
#
# Le menu s'ouvre par `process-spawn progress` depuis le listener : `activate-progress` sort sur
# `(progress-allowed?)` = #f dans une course de mesure (memoire reference_open_jak1_menu...).
# Pas de `(build-game)` : gk boote sur les CGO de out/jak1/iso deja construits par make-group.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG=${1:?tag}; MODE=${2:-defaut}
OUT=.autoport/reports/Gfont-regression; mkdir -p "$OUT"
GOALC=build/goalc/goalc; GK=build/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gfr-iso
LOG="$OUT/x86-$TAG.log"; GCLOG="$OUT/x86-$TAG-goalc.log"
: > "$LOG"; : > "$GCLOG"
say(){ echo "$(date +%H:%M:%S) $*"; }

SETTINGS=build/game/OpenGOAL/jak1/settings/settings.ini
USERDIR=custom_assets/jak1/texture_replacements
cp -a "$SETTINGS" "$SETTINGS.gfr-bak"
restore(){
  [ -f "$SETTINGS.gfr-bak" ] && mv -f "$SETTINGS.gfr-bak" "$SETTINGS"
  rm -rf "$USERDIR/gamefontnew"
}
cleanup(){
  exec 3>&- 2>/dev/null || true
  [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  rm -f "${FIFO:-/nonexistent}"
  restore
}
trap cleanup EXIT

case "$MODE" in
  defaut) ;;
  portes-off)
    sed -i -e 's/^recharged-master? = .*/recharged-master? = #f/' \
           -e 's/^recharged-textures? = .*/recharged-textures? = #f/' \
           -e 's/^load-custom-assets? = .*/load-custom-assets? = #t/' "$SETTINGS"
    mkdir -p "$USERDIR/gamefontnew"
    cp extracted_textures/jak1/gamefontnew/ascii.24lo.png "$USERDIR/gamefontnew/ascii.24lo.png"
    ;;
  *) echo "mode inconnu $MODE"; exit 2;;
esac
say "mode=$MODE settings: $(grep -E '^(recharged-master|recharged-textures|load-custom-assets)' "$SETTINGS" | tr '\n' ' ')"
say "user gamefontnew: $(ls "$USERDIR/gamefontnew" 2>/dev/null | tr '\n' ' ')"

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11

rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"; cp -a --reflink=auto "$ISO" "$SNAP"
say "copie privee de l'iso : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12) FONT-STR=$(grep -a -c FONT-STR "$SNAP/GAME.CGO")"

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 120); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 30
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies, FONTTEX: $(grep -ac '^FONTTEX' "$LOG")"

timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
# le listener ne connait les symboles du jeu qu'apres avoir compile le projet (gk, lui, boote sur
# la copie privee de l'iso : build-game ne le touche pas — c'est juste ce qui apprend les symboles)
echo '(build-game)' >&3
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 3
# titre : « Appuie sur start ... » + FPS
echo '(set! *font-str-trace* 200)' >&3
sleep 6
# menu : le processus `progress` est cree directement (activate-progress sort sur
# progress-allowed? = #f dans une course de mesure), puis on ENTRE dans trois pages profondes par
# sa propre methode `enter!` — chaque rangee visible passe par draw-string, dans les deux polices.
echo '(set! *progress-process* (process-spawn progress :to *dproc* :stack *progress-stack-top*))' >&3
sleep 5
echo '(set! *font-str-trace* 300)' >&3
sleep 4
for scr in settings-title settings graphic-settings sound-settings game-settings; do
  echo "(enter! (-> *progress-process* 0) (progress-screen $scr) 0)" >&3
  sleep 4
  echo '(set! *font-str-trace* 400)' >&3
  sleep 5
done
echo '(format 0 "FONT-PROBE master=~A textures=~A custom=~A~%" (-> *pc-settings* recharged-master?) (-> *pc-settings* recharged-textures?) (-> *pc-settings* load-custom-assets?))' >&3
sleep 3
say "FONT-STR: $(grep -ac '^FONT-STR' "$LOG") lignes, FONTTEX bind: $(grep -ac '^FONTTEX bind' "$LOG")"
grep -a '^FONTTEX\|^FONT-PROBE\|custom texture replacement.*gamefont\|FONTTEX' "$LOG" | sort -u
