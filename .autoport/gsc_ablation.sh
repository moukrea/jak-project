#!/usr/bin/env bash
# gsc_ablation.sh — ABLATION SANS RECONSTRUCTION : bascule une cle de settings.ini
# sur l'appareil et remesure le pic RSS. NATURE : RSS du processus (Ko, VmRSS).
# REPERE : le processus entier. LIGNE DE BASE : la meme course avec la cle a sa
# valeur d'origine, publiee cote a cote.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=${S:?}; NAME=${NAME:?}; KEY=${KEY:?}; VAL=${VAL:?}; WATCH=${WATCH:-70}
PKG=org.opengoal.gk.jak1
INI=/storage/emulated/0/OpenGOAL/jak1/settings.ini
OUT=.autoport/logs/gsc/$NAME; mkdir -p "$OUT"
say(){ echo "[$(date +%H:%M:%S)] $*"; }
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell "cp $INI $INI.gscbak" 2>&1
OLD=$(timeout 20 $ADB -s "$S" shell "grep '^$KEY = ' $INI" | tr -d '\r')
say "avant: $OLD"
timeout 30 $ADB -s "$S" shell "sed -i 's|^$KEY = .*|$KEY = $VAL|' $INI"
NEW=$(timeout 20 $ADB -s "$S" shell "grep '^$KEY = ' $INI" | tr -d '\r')
say "apres: $NEW"
[ "$OLD" = "$NEW" ] && { say "ECHEC: la cle n'a pas change, ablation NON FAITE"; exit 3; }
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; sleep 1
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout $((WATCH+60)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
T0=$(date +%s.%N)
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
: > "$OUT/rss.txt"; PEAK=0
for i in $(seq 1 $((WATCH*2))); do
  PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
  EL=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  if [ -z "$PID" ]; then echo "$EL MORT" >> "$OUT/rss.txt"; else
    RSS=$(timeout 10 $ADB -s "$S" shell cat /proc/$PID/status 2>/dev/null | grep -E '^VmRSS' | grep -oE '[0-9]+' | head -1)
    [ -n "${RSS:-}" ] && { echo "$EL $RSS" >> "$OUT/rss.txt"; [ "$RSS" -gt "$PEAK" ] && { PEAK=$RSS
        timeout 25 $ADB -s "$S" exec-out run-as $PKG cat /proc/$PID/smaps > "$OUT/smaps-pic.txt" 2>/dev/null; }; }
  fi
  sleep 0.5
done
kill $LOGPID 2>/dev/null
echo "$PEAK" > "$OUT/peak-rss-kb.txt"
say "pic RSS = $PEAK Ko = $(awk -v p=$PEAK 'BEGIN{printf "%.0f", p/1024}') Mo"
# RESTAURER — une ablation ne laisse jamais l'appareil dans son etat de test.
timeout 30 $ADB -s "$S" shell "cp $INI.gscbak $INI"
say "restaure: $(timeout 20 $ADB -s "$S" shell "grep '^$KEY = ' $INI" | tr -d '\r')"
