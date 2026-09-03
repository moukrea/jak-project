#!/usr/bin/env bash
# gmouche3_device.sh — Gcrash-mouche3 REAL crate→fly→collect repro/verify (arm64 eae4df44).
#
# Drives the OWNER's real path — break a Geyser-Rock fly-CRATE, the buzzer flies out,
# Jak collects it — autonomously on-device, the path the PROGRAMMATIC mouche.buzz faked:
#   debug.opengoal.f1.warp=1  -> warp to Geyser Rock ('training), Jak has control
#   debug.opengoal.tele=1     -> arm the teleport hook (kmachine.cpp tele_maybe_fire)
#   debug.opengoal.tele.idx N -> move Jak ONTO real buzzer crate N (0..6)
#   debug.opengoal.tele.gen G -> nonce; the hook teleports whenever G changes
#   then cpad_inject "circle"  -> Jak's REAL spin attack breaks the ACTUAL crate ->
#                                 real drop-pickup -> real buzzer -> Jak collects it.
# All 7 crates are broken+collected in rapid succession (the real dead-pool-heap reuse
# the owner hits). Watches logcat for the crash (Fatal signal / GK-DIAG sig=4|6|11 /
# RFTD-NULLRET-REDIRECT / ENTER-STATE-CODE-REPAIR), render progress (A35-RENDER),
# and the scout-fly count (M3-FLYCOUNT = real-collect evidence).
#
# Usage: gmouche3_device.sh <run_tag> [out_dir]
#   SKIP_BUILD=1  reuse the already-built+deployed libgk (skip build+install)
#   PASSES=N      number of full 7-crate passes (default 1; re-warp between passes)
#   SPIN_S        seconds to hold the spin per crate (default 1.4)
#   COLLECT_S     seconds to wait for buzzer fall+collect per crate (default 2.6)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gcrash-mouche3}"
PASSES="${PASSES:-1}"
SPIN_S="${SPIN_S:-1.4}"
COLLECT_S="${COLLECT_S:-2.6}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 15 ) \
      || { echo "FAIL: gradle slim build failed"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + verify fresh HEAD libgk on device =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
  device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gm3-push.out 2>&1 || { cat /tmp/gm3-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gm3-pm.out 2>&1 || { cat /tmp/gm3-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gm3-pm.out || { cat /tmp/gm3-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm warp + teleport; tag=$RUN_TAG =="
A shell setprop debug.opengoal.f1.warp    1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele       1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.idx  -1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.gen   0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.fx  0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.buzz 0 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  clear_inject
  A shell setprop debug.opengoal.tele 0 >/dev/null 2>&1 || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gm3-am.out 2>&1 || true
grep -q 'Error' /tmp/gm3-am.out && { cat /tmp/gm3-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() { grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; }
focus_is_app() { A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
flycount() { grep -aoE 'M3-FLYCOUNT total=[0-9.]+' "$LOG" 2>/dev/null | grep -oE '[0-9.]+$' | sort -g | tail -1; }

echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
echo "  waiting for warp (start 'play game-start) (up to 90s)..."
for i in $(seq 1 90); do grep -qa "F1-SPAWN" "$LOG" && { echo "  warp/spawn fired ~${i}s"; break; }; sleep 1; done
echo "  waiting for training (Geyser Rock) load (up to 8min)..."
for ((i=1;i<=96;i++)); do
  sleep 5
  if grep -qaE "Adding level training|link finish: training|TELE-ARM|F1-SPAWN" "$LOG"; then echo "   >>> training active ~$((i*5))s"; break; fi
  if crash_seen; then echo "   >>> crash before training load"; break; fi
  (( i % 6 == 0 )) && echo "   [load ${i}/96] waiting..."
done
sleep 8  # let Jak settle + HUD activate

GEN=0
CRASHED=0
NCOLLECT_ATTEMPTS=0
{
  echo "=== Gcrash-mouche3 REAL crate->fly->collect drive (tag=$RUN_TAG) ==="
} | tee -a "$RESULT"

for ((p=1; p<=PASSES; p++)); do
  for ((i=0; i<=6; i++)); do
    [ "$CRASHED" = 1 ] && break
    GEN=$((GEN+1))
    NCOLLECT_ATTEMPTS=$((NCOLLECT_ATTEMPTS+1))
    FB=$(max_frame); FB=${FB:-0}
    A shell setprop debug.opengoal.tele.idx "$i"  >/dev/null 2>&1 || true
    A shell setprop debug.opengoal.tele.gen "$GEN" >/dev/null 2>&1 || true
    # wait for the teleport to fire (TELE-JAK idx=i)
    for w in $(seq 1 20); do grep -qaE "TELE-JAK idx=$i .*gen|TELE-JAK idx=$i " "$LOG" && break; sleep 0.25; done
    sleep 0.4
    # REAL break: Jak spin attack (circle) on the actual crate
    inject "circle"; sleep "$SPIN_S"; clear_inject
    # let the buzzer rise + fall back onto Jak -> real collide 'touch -> collect
    sleep "$COLLECT_S"
    FA=$(max_frame); FA=${FA:-0}; DF=$(( FA - FB ))
    FC=$(flycount); FC=${FC:-0}
    FOC="no"; focus_is_app && FOC="yes"
    if crash_seen; then
      echo "  pass$p crate$i (fly$i): CRASH  flycount=$FC frame+$DF focus=$FOC" | tee -a "$RESULT"
      CRASHED=1; break
    fi
    echo "  pass$p crate$i (fly$i): collect attempt  flycount=$FC frame+$DF focus=$FOC" | tee -a "$RESULT"
  done
  [ "$CRASHED" = 1 ] && break
  # re-warp for another pass (reload training -> crates respawn) if more passes
  if (( p < PASSES )); then
    echo "  -- re-warp for pass $((p+1)) --"
    A shell setprop debug.opengoal.tele.idx -1 >/dev/null 2>&1 || true
    A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    sleep 2
    A shell am start -W -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1 || true
    for ((i=1;i<=96;i++)); do sleep 5; grep -qa "F1-SPAWN" "$LOG" && break; crash_seen && { CRASHED=1; break; }; done
    sleep 8
  fi
done

# final fly-count read
GEN=$((GEN+1))
A shell setprop debug.opengoal.tele.idx 0   >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.gen "$GEN" >/dev/null 2>&1 || true
sleep 2

# ── Forensics harvest ──
FA=$(max_frame); FA=${FA:-0}
FC=$(flycount); FC=${FC:-0}
FOC="no"; focus_is_app && FOC="yes"
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|signal (11|6|4) \(SIG[A-Z]+' "$LOG" | tail -1)
NEARFN=$(grep -aE 'A38-TRIPWIRE (pc|lr|fault) nearest-fn|nearest-fn' "$LOG" | tail -5 | tr '\n' ';')
RFTD=$(grep -aoE '(GCINE3-DEACT-STOMP|GMATCH-RFTD-STOMP|RFTD-STOMP-REPAIR|RFTD-NULLRET-REDIRECT|ENTER-STATE-CODE-REPAIR|DBLEE-DROP-KERNELCODE)' "$LOG" | sort | uniq -c | tr '\n' ';')
A34=$(grep -aE 'A34-DIAG|fp-walk|A37-PCWIN|A37-LRWIN|GSPARK-PP' "$LOG" | tail -6 | tr '\n' ';')
BT=$(grep -aE '#[0-9]{2} pc [0-9a-f]+' "$LOG" | head -14 | tr '\n' ';')
TELES=$(grep -acE 'TELE-JAK idx=' "$LOG" 2>/dev/null || echo 0)
FLYLINE=$(grep -aoE 'M3-FLYCOUNT total=[0-9.]+' "$LOG" | tr '\n' ' ')

STATUS="UNKNOWN"
if [ "$CRASHED" = 1 ]; then
  STATUS="REAL-COLLECT-CRASH(sig=${SIG:-?})"
elif awk "BEGIN{exit !($FC>=5)}"; then
  STATUS="REAL-COLLECT-CRASH-FREE(flies=$FC,teleports=$TELES)"
else
  STATUS="INCONCLUSIVE(flies=$FC,teleports=$TELES,focus=$FOC)"
fi

{
  echo ""
  echo "RESULT tag=$RUN_TAG status=$STATUS"
  echo "  flycount(final)=$FC  teleports=$TELES  collect_attempts=$NCOLLECT_ATTEMPTS  render_frame(max)=$FA  focus_app=$FOC"
  echo "  sig=${SIG:-none}"
  echo "  flycount-progression: ${FLYLINE:-none}"
  echo "  rftd/repair-markers: ${RFTD:-none}"
  echo "  near-fn: ${NEARFN:-none}"
  echo "  a34/fp-walk: ${A34:-none}"
  echo "  backtrace: ${BT:-none}"
} | tee -a "$RESULT"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
clear_inject
A shell setprop debug.opengoal.tele 0 >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true
echo "== gmouche3_device.sh $RUN_TAG done: $STATUS =="
exit 0
