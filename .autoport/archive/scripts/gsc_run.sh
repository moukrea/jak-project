#!/usr/bin/env bash
# gsc_run.sh — MESURE sur le Redmi eae4df44 (SEUL appareil autorise).
# NATURE des grandeurs :
#   rss.txt      : VmRSS du processus en Ko (memoire physique residente), REPERE = le
#                  processus entier. Echantillonne toutes les ~0,5 s.
#   smaps-pic    : decomposition des mappings AU MAXIMUM de la course (run-as, donc
#                  lisible sans root sur un paquet debuggable).
#   logcat.txt   : journal du moteur (tags A5x-*), REPERE = le moteur.
# LIGNE DE BASE : la meme course, meme appareil, avant correctif.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
NAME=${NAME:?nom de course requis}
PKG=org.opengoal.gk.jak1
WATCH=${WATCH:-150}
SEQ_MENU=${SEQ_MENU:-0}     # 1 = pilote le menu pour lancer une partie
OUT=.autoport/logs/gsc/$NAME
mkdir -p "$OUT"
say(){ echo "[$(date +%H:%M:%S)] $*"; }
inj(){ timeout 15 $ADB -s "$S" shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }

timeout 30 $ADB -s "$S" shell devices >/dev/null 2>&1
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || { say "Redmi $S ABSENT"; exit 1; }

inj ""
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; sleep 1
WAKE=$(timeout 30 $ADB -s "$S" shell dumpsys power 2>/dev/null | grep -oE 'mWakefulness=[A-Za-z]+' | head -1 | tr -d '\r')
say "ecran: ${WAKE:-inconnu}"
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell cat /proc/meminfo > "$OUT/meminfo-avant.txt" 2>&1
timeout $((WATCH+90)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
T0=$(date +%s.%N)
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
say "lance ; ${WATCH}s d'echantillonnage (menu=$SEQ_MENU)"

if [ "$SEQ_MENU" = 1 ]; then
  press(){ inj "$1"; sleep 0.7; inj ""; sleep 1.3; }
  ( sleep "${MENU_AT:-40}"; press start; sleep 3; press x; sleep 4; press x; sleep 5; press x ) &
  SEQP=$!
fi

: > "$OUT/rss.txt"; PEAK=0; DEAD=""
for i in $(seq 1 $((WATCH*2))); do
  PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
  EL=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  if [ -z "$PID" ]; then
    echo "$EL MORT" >> "$OUT/rss.txt"; [ -z "$DEAD" ] && { DEAD="$EL"; say "PROCESSUS MORT a t=${EL}s"; }
  else
    RSS=$(timeout 10 $ADB -s "$S" shell cat /proc/$PID/status 2>/dev/null | grep -E '^VmRSS' | grep -oE '[0-9]+' | head -1)
    if [ -n "${RSS:-}" ]; then
      echo "$EL $RSS" >> "$OUT/rss.txt"
      if [ "$RSS" -gt "$PEAK" ]; then
        PEAK=$RSS
        timeout 25 $ADB -s "$S" exec-out run-as $PKG cat /proc/$PID/smaps > "$OUT/smaps-pic.txt.tmp" 2>/dev/null
        [ -s "$OUT/smaps-pic.txt.tmp" ] && mv "$OUT/smaps-pic.txt.tmp" "$OUT/smaps-pic.txt"
      fi
    fi
  fi
  sleep 0.5
done
[ "$SEQ_MENU" = 1 ] && { wait $SEQP 2>/dev/null; inj ""; }
kill $LOGPID 2>/dev/null
timeout 30 $ADB -s "$S" shell cat /proc/meminfo > "$OUT/meminfo-apres.txt" 2>&1
echo "$PEAK" > "$OUT/peak-rss-kb.txt"
say "maximum RSS = $PEAK Ko = $(awk -v p=$PEAK 'BEGIN{printf "%.0f", p/1024}') Mo ; mort=${DEAD:-non}"
say "journal : $OUT/"
