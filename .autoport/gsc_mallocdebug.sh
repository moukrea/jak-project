#!/usr/bin/env bash
# gsc_mallocdebug.sh — NOMMER les deux blocs de 157 626 368 octets par leur
# PILE D'APPEL, via libc malloc_debug (backtrace) + am dumpheap -n.
# NATURE : dump du tas natif avec pile d'allocation. REPERE : le processus.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=${S:?}; PKG=org.opengoal.gk.jak1; NAME=${NAME:-c3-mallocdebug}; WAIT=${WAIT:-45}
OUT=.autoport/logs/gsc/$NAME; mkdir -p "$OUT"
say(){ echo "[$(date +%H:%M:%S)] $*"; }
timeout 30 $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1
timeout 30 $ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; sleep 1
say "activation de malloc_debug (backtrace=24)"
timeout 30 $ADB -s "$S" shell setprop wrap.org.opengoal.gk.jak1 '"LIBC_DEBUG_MALLOC_OPTIONS=backtrace=24 logwrapper"' 2>&1
timeout 30 $ADB -s "$S" shell getprop wrap.org.opengoal.gk.jak1
timeout 30 $ADB -s "$S" shell logcat -c >/dev/null 2>&1
timeout $((WAIT+60)) $ADB -s "$S" shell logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!
timeout 30 $ADB -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
say "attente ${WAIT}s pour depasser l'allocation (elle tombe vers t=4-6 s)"
sleep "$WAIT"
PID=$(timeout 10 $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r' | awk '{print $1}')
say "pid=$PID"
[ -z "$PID" ] && { say "PROCESSUS MORT — pas de dump"; kill $LOGPID 2>/dev/null; exit 1; }
timeout 60 $ADB -s "$S" shell am dumpheap -n "$PID" /data/local/tmp/gsc-heap.txt 2>&1
sleep 8
timeout 90 $ADB -s "$S" shell "cat /data/local/tmp/gsc-heap.txt" > "$OUT/heap.txt" 2>&1
kill $LOGPID 2>/dev/null
wc -l "$OUT/heap.txt"
timeout 30 $ADB -s "$S" shell setprop wrap.org.opengoal.gk.jak1 '""' 2>&1
say "dump -> $OUT/heap.txt"
