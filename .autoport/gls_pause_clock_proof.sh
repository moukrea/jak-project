#!/usr/bin/env bash
# Gloading-screen (owner 2026-08-29, retour n.2 et n.4) — POURQUOI L'HORLOGE A CHANGE, MESURE.
#
# L'ecran de chargement lisait `(current-time)` = `(-> *display* base-frame-counter)`. Son unique
# site d'increment (engine/draw/drawable.gc:1013-1014) est sous `(when (not (paused?)))`, et
# `paused?` (main.gc:608) est vrai des que le menu est ouvert — donc pendant le chargement d'une
# partie lance depuis ce menu. Deux consequences a l'ecran : la silhouette EXACTEMENT figee, et le
# seuil de 0,5 s jamais franchi (donc pas de contenu du tout, ce que l'owner a signale au n.2).
#
# CE SCRIPT NE RAISONNE PAS, IL MESURE. Il pose `*master-mode*` a 'menu pendant quelques secondes
# et publie les DEUX horloges avant / pendant / apres. Attendu : `base` INCHANGE pendant la pause
# (le defaut), `integ` qui avance de ~60 par seconde (le correctif). Puis les deux repartent.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
LOG="$OUT/pause-clock.log"; GCLOG="$OUT/pause-clock-goalc.log"; : > "$LOG"; : > "$GCLOG"
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | python3 -u -c 'import sys,time
t0=time.time()
for l in sys.stdin:
    sys.stdout.write("%9.3f %s" % (time.time()-t0, l))' >> "$LOG" &
PIPEPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null; kill "$PIPEPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 120); do grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && break; sleep 1; done
sleep 3
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 15); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener non connecte"; exit 1; }

P='(format 0 "PAUSECTRL etape=~A mode=~A pause=~A base=~D integ=~D~%"'
echo "$P \"avant\" *master-mode* (paused?) (current-time) (loading-screen-clock))" >&3
sleep 1
echo '(set! *master-mode* (quote menu))' >&3
echo "$P \"pause-debut\" *master-mode* (paused?) (current-time) (loading-screen-clock))" >&3
sleep 5
echo "$P \"pause-fin\" *master-mode* (paused?) (current-time) (loading-screen-clock))" >&3
echo '(set! *master-mode* (quote game))' >&3
sleep 5
echo "$P \"apres\" *master-mode* (paused?) (current-time) (loading-screen-clock))" >&3
sleep 2
exec 3>&-
sleep 2
echo "---- PAUSECTRL ----"
grep -a "PAUSECTRL" "$LOG"
