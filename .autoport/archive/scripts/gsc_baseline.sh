#!/usr/bin/env bash
# gsc_baseline.sh — phase Gappareil de test-load-and-crash : MESURE DE REFERENCE sur un
# appareil, sans reconstruire quoi que ce soit. Publie :
#   - le journal complet du demarrage (tags A5x-*),
#   - une serie RSS echantillonnee (regime + pic),
#   - le smaps du pic, pour nommer les gros blocs anonymes.
# NATURE des grandeurs : RSS = memoire physique residente du processus, en Ko,
# lue dans /proc/<pid>/status (VmRSS). REPERE : le processus entier, pas un
# sous-systeme. LIGNE DE BASE : le meme script sur le meme appareil avant
# correctif.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=${S:?serial requis}
NAME=${NAME:?nom de course requis}
PKG=org.opengoal.gk.jak1
WATCH=${WATCH:-150}
OUT=.autoport/logs/gsc/$NAME
mkdir -p "$OUT"
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "=== $NAME sur $S ==="
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
# REVEIL — un ecran eteint bloque am start (TOP_SLEEPING), zero image, aucun signal.
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
sleep 1
WAKE=$(timeout 30 $ADB -s "$S" shell dumpsys power 2>/dev/null | grep -oE 'mWakefulness=[A-Za-z]+' | head -1 | tr -d '\r')
say "etat ecran : ${WAKE:-inconnu}"
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell "cat /proc/meminfo" > "$OUT/meminfo-avant.txt" 2>&1

timeout $((WATCH+60)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
T0=$(date +%s.%N)
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
say "lance, echantillonnage RSS pendant ${WATCH}s"

: > "$OUT/rss.txt"
PEAK=0; PEAKPID=""
for i in $(seq 1 $((WATCH*2))); do
  PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
  NOW=$(date +%s.%N)
  EL=$(awk -v a="$T0" -v b="$NOW" 'BEGIN{printf "%.1f", b-a}')
  if [ -z "$PID" ]; then
    echo "$EL MORT" >> "$OUT/rss.txt"
  else
    RSS=$(timeout 10 $ADB -s "$S" shell cat /proc/$PID/status 2>/dev/null | grep -E '^VmRSS' | grep -oE '[0-9]+' | head -1)
    [ -n "${RSS:-}" ] && { echo "$EL $RSS" >> "$OUT/rss.txt"; PEAKPID=$PID
      if [ "$RSS" -gt "$PEAK" ]; then PEAK=$RSS
        timeout 20 $ADB -s "$S" shell cat /proc/$PID/smaps > "$OUT/smaps-pic.txt" 2>/dev/null
      fi; }
  fi
  sleep 0.5
done
kill $LOGPID 2>/dev/null
say "pic RSS = $PEAK Ko = $(awk -v p=$PEAK 'BEGIN{printf "%.1f", p/1024}') Mo"
timeout 30 $ADB -s "$S" shell "cat /proc/meminfo" > "$OUT/meminfo-apres.txt" 2>&1
echo "$PEAK" > "$OUT/peak-rss-kb.txt"
say "journal : $OUT/"
