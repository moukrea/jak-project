#!/usr/bin/env bash
# gcine_cut_killdiag.sh — find out WHY the app silently vanishes (~render frame 4620)
# at the END of the new-game misty cinematic on the device. The normal capture
# filters logcat to opengoal-gk:I libc:F DEBUG:V, which SILENCES the system tags
# (ActivityManager / lmkd / lowmemorykiller) that log an OOM/LMK kill. This run
# captures the FULL system logcat (all buffers) + meminfo so the kill reason is
# visible. Drives NEW GAME exactly like the proven gcine_cut_device.sh.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=".autoport/reports/Gcine-cut"
FULL="$OUT/device-killdiag-full.log"     # filtered-but-all-buffers (kill tags + frames)
SNAP="$OUT/device-killdiag-snapshot.log" # full -b all dump at moment of vanish
MEM="$OUT/device-killdiag-mem.txt"
WATCH_MIN="${WATCH_MIN:-8}"
mkdir -p "$OUT"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug com.miui.home)
reenable() { for p in com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_il() { for p in com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
read_focus() { adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r'; }
app_pid() { adb shell pidof "$PKG" 2>/dev/null | tr -d '\r'; }

echo "== gcine_cut killdiag (full system logcat) =="
# kill any leftover runner that could murder this run's app on its trailing force-stop
for rp in $(pgrep -f 'gcine_(audit|cut)_device|verify_device_graphics|gcine_cut_killdiag' 2>/dev/null | grep -v "^$$\$" || true); do
  [ "$rp" != "$$" ] && { echo "  killing leftover runner pid=$rp"; kill "$rp" 2>/dev/null || true; }
done
device_require_attached
disable_il
trap 'reenable; kill ${LC_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
# maximize free memory + disk headroom
adb shell pm trim-caches 99999999999 >/dev/null 2>&1 || true
adb shell am kill-all >/dev/null 2>&1 || true
adb shell am force-stop "$PKG" 2>/dev/null || true

{ echo "### meminfo BEFORE launch $(date -Is)"; adb shell cat /proc/meminfo 2>/dev/null | tr -d '\r' | head -8;
  echo "### MemAvailable + lmk props"; adb shell getprop | grep -iE 'lowmem|lmk' | tr -d '\r' | head;
} > "$MEM"

adb shell setprop debug.opengoal.gcine.cam 1 2>/dev/null || true
adb logcat -G 96M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -b crash 2>/dev/null -c || true
# FULL: all buffers, keep kill-relevant tags + the app frames + spool/loader signals
( adb logcat -b main,system,crash,events -v threadtime 2>/dev/null \
    | grep --line-buffered -aiE 'opengoal-gk|ActivityManager|lowmemory|lmkd|killing|am_kill|am_proc_died|am_anr|am_crash|died|out of memory|\boom\b|jak1|tombston|libc *:|DEBUG *:|Fatal signal|signal [0-9]+ \(SIG|backtrace|loader stall|GCINE-|A35-RENDER|GK-DIAG' \
    > "$FULL" ) &
LC_PID=$!

echo "  launch"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "== warmup 40s (title attract settle) =="; sleep 40
echo "== START =="; inject "start"; sleep 1.2; inject ""; sleep 4
echo "== nav to NEW GAME =="
inject "down"; sleep 0.4; inject ""; sleep 1.5
inject "down"; sleep 0.4; inject ""; sleep 1.5
inject "up";   sleep 0.4; inject ""; sleep 1
inject "up";   sleep 0.4; inject ""; sleep 1.5
echo "== X (select NEW GAME) =="; inject "x"; sleep 0.6; inject ""; sleep 3
echo "== CONTINUE WITHOUT SAVING =="
inject "down"; sleep 0.4; inject ""; sleep 1
inject "down"; sleep 0.4; inject ""; sleep 1
inject "down"; sleep 0.4; inject ""; sleep 1
inject "down"; sleep 0.4; inject ""; sleep 1
inject "x";    sleep 0.6; inject ""; sleep 4

echo "== watch for vanish (poll 2s, ${WATCH_MIN}min) =="
ITERS=$(( WATCH_MIN * 60 / 2 ))
LASTPID=""; GONE=0; MAXF=0
for ((i=1;i<=ITERS;i++)); do
  sleep 2
  PID=$(app_pid)
  FM=$(tail -n 400 "$FULL" 2>/dev/null | grep -aoE 'A35-RENDER frame=[0-9]+' | tail -1 | grep -oE '[0-9]+$'); FM=${FM:-$MAXF}
  [ "${FM:-0}" -gt "$MAXF" ] && MAXF=$FM
  if (( i % 5 == 0 )); then echo "   [${i}/${ITERS}] frame=${FM} pid='${PID:-gone}'"; fi
  # snapshot meminfo periodically while alive (catch the climb)
  if [ -n "$PID" ] && (( i % 10 == 0 )); then
    { echo "### meminfo frame~${FM} $(date -Is)"; adb shell cat /proc/meminfo 2>/dev/null | tr -d '\r' | grep -iE 'MemAvailable|MemFree|SwapFree'; } >> "$MEM"
  fi
  if [ -z "$PID" ]; then
    GONE=$((GONE+1))
    if [ "$GONE" -eq 1 ]; then
      echo "   >>> app GONE detected at frame~${FM} — snapshotting full logcat"
      adb logcat -b all -d -t 3000 > "$SNAP" 2>/dev/null || true
      { echo "### meminfo AFTER vanish $(date -Is)"; adb shell cat /proc/meminfo 2>/dev/null | tr -d '\r' | head -6;
        echo "### dmesg tail (may be empty w/o root)"; adb shell dmesg 2>/dev/null | tail -40 | tr -d '\r';
        echo "### dumpsys activity lru/kill"; adb shell dumpsys activity 2>/dev/null | grep -iE 'kill|jak1|lru' | tr -d '\r' | head -20;
      } >> "$MEM"
    fi
    [ "$GONE" -ge 2 ] && { echo "   >>> confirmed gone"; break; }
  else
    GONE=0
  fi
  [ "${FM:-0}" -ge 11000 ] && { echo "   >>> reached frame ${FM} (>=11000) — cinematic survived!"; break; }
done

echo "== teardown =="
kill ${LC_PID:-0} 2>/dev/null || true
trap - EXIT
reenable
adb shell setprop debug.opengoal.gcine.cam 0 2>/dev/null || true
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== KILL-CAUSE SCOREBOARD =="
echo "  max render frame : $MAXF"
echo "  end focus        : $(read_focus)"
echo "  --- LMK / OOM lines (full all-buffer snapshot) ---"
grep -aiE 'lowmemory|lmkd|killing|am_kill|am_proc_died|out of memory|\boom\b|oom_adj|oom_score' "$SNAP" 2>/dev/null | grep -ai 'jak1\|opengoal\|'"$(app_pid)" | tail -25
echo "  --- ActivityManager death lines ---"
grep -aiE 'ActivityManager|am_proc_died|died|ANR' "$SNAP" 2>/dev/null | grep -ai 'jak1\|opengoal' | tail -15
echo "  --- native crash (libc/DEBUG/tombstone) ---"
grep -aiE 'libc *:|DEBUG *:|Fatal signal|signal [0-9]+ \(SIG|backtrace|tombston' "$SNAP" 2>/dev/null | tail -15
echo "  (full: $FULL ; snapshot: $SNAP ; mem: $MEM)"
