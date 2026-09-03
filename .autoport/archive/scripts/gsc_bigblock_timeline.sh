#!/usr/bin/env bash
# gsc_bigblock_timeline.sh — a quel MOMENT du demarrage apparaissent les deux
# blocs de 157 626 368 octets ? NATURE : compte de mappings anonymes de cette
# taille exacte, lu dans /proc/<pid>/maps. REPERE : le processus. LIGNE DE
# BASE : 0 mapping avant que l'allocateur ne les cree.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=${S:?}; NAME=${NAME:?}; PKG=org.opengoal.gk.jak1; WATCH=${WATCH:-90}
OUT=.autoport/logs/gsc/$NAME; mkdir -p "$OUT"
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; sleep 1
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout $((WATCH+60)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
T0=$(date +%s.%N)
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
: > "$OUT/timeline.txt"
for i in $(seq 1 $WATCH); do
  PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
  EL=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  if [ -z "$PID" ]; then echo "$EL MORT" >> "$OUT/timeline.txt"; else
    MAPS=$(timeout 15 $ADB -s "$S" exec-out run-as $PKG cat /proc/$PID/maps 2>/dev/null | tr -d '\r')
    N=$(echo "$MAPS" | awk -F'[- ]' '/^[0-9a-f]+-[0-9a-f]+ /{d=strtonum("0x"$2)-strtonum("0x"$1); if(d==157626368) n++} END{print n+0}')
    BIG=$(echo "$MAPS" | awk -F'[- ]' '/^[0-9a-f]+-[0-9a-f]+ /{d=strtonum("0x"$2)-strtonum("0x"$1); if(d>=33554432) s+=d} END{printf "%.0f", s/1048576}')
    RSS=$(timeout 10 $ADB -s "$S" shell cat /proc/$PID/status 2>/dev/null | grep -E '^VmRSS' | grep -oE '[0-9]+' | head -1)
    echo "$EL n150=$N gros>=32Mo=${BIG}Mo rss=${RSS:-?}kB" >> "$OUT/timeline.txt"
  fi
  sleep 0.6
done
kill $LOGPID 2>/dev/null
echo "fini -> $OUT/timeline.txt"
