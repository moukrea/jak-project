#!/usr/bin/env bash
# gsc_newgame.sh — REPRODUIRE LE DEFAUT DE L'OWNER : « ca crash quand je charge
# la partie ». On pilote le menu sans les mains (propriete debug.opengoal.cpad_inject),
# on echantillonne le RSS, et on note si le processus MEURT.
# NATURE : RSS du processus (Ko, VmRSS) + vie/mort du pid. REPERE : le processus.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=${S:?}; NAME=${NAME:?}; PKG=org.opengoal.gk.jak1
WAIT_TITLE=${WAIT_TITLE:-40}; WATCH=${WATCH:-110}
OUT=.autoport/logs/gsc/$NAME; mkdir -p "$OUT"
say(){ echo "[$(date +%H:%M:%S)] $*"; }
inj(){ timeout 15 $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }

inj ""
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; sleep 1
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout $((WAIT_TITLE+WATCH+90)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
T0=$(date +%s.%N)
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
say "attente ${WAIT_TITLE}s de l'ecran-titre"
sleep "$WAIT_TITLE"

: > "$OUT/rss.txt"; PEAK=0; DEAD=""
press(){ say "  bouton '$1'"; inj "$1"; sleep 0.7; inj ""; sleep 1.3; }
# Sequence menu : START pour sortir du titre, puis X pour valider l'entree en surbrillance.
( sleep 2;  press start
  sleep 3;  press x
  sleep 4;  press x
  sleep 5;  press x ) &
SEQ=$!

for i in $(seq 1 $((WATCH*2))); do
  PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
  EL=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  if [ -z "$PID" ]; then
    echo "$EL MORT" >> "$OUT/rss.txt"; [ -z "$DEAD" ] && { DEAD="$EL"; say "PROCESSUS MORT a t=${EL}s"; }
  else
    RSS=$(timeout 10 $ADB -s "$S" shell cat /proc/$PID/status 2>/dev/null | grep -E '^VmRSS' | grep -oE '[0-9]+' | head -1)
    [ -n "${RSS:-}" ] && { echo "$EL $RSS" >> "$OUT/rss.txt"
      [ "$RSS" -gt "$PEAK" ] && { PEAK=$RSS; timeout 25 $ADB -s "$S" exec-out run-as $PKG cat /proc/$PID/smaps > "$OUT/smaps-pic.txt" 2>/dev/null; }; }
  fi
  sleep 0.5
done
wait $SEQ 2>/dev/null; kill $LOGPID 2>/dev/null; inj ""
echo "$PEAK" > "$OUT/peak-rss-kb.txt"
say "pic RSS = $PEAK Ko = $(awk -v p=$PEAK 'BEGIN{printf "%.0f", p/1024}') Mo ; mort=${DEAD:-non}"
say "morts: $(grep -c MORT "$OUT/rss.txt") echantillons ; niveaux: $(grep -c 'A51-FR3' "$OUT/logcat.txt")"
