#!/usr/bin/env bash
# Phase Gcrash-geyser (autoport) — Geyser Rock crash repro/verify driver.
#
# Modes (arg1):
#   fly    — DETERMINISTIC scout-fly ("mouche") collect crash. Warps to Geyser
#            Rock, then flips debug.opengoal.fly.collect so the kernel spawns a
#            `buzzer` at Jak's position; the collide overlap fires the standard
#            touch->pickup collect path. Capture the crash forensics / no-crash.
#   steps  — owner's intermittent steps crash/blue-lock. Warps to Geyser Rock,
#            then cpad-injects the walk-to-steps + jump-up-the-steps sequence.
#            Detect BOTH a hard crash AND a render blue-lock (F1-STATE / send_chain
#            cadence stops while the app stays foreground).
#
# Usage: gcrash_run.sh <fly|steps> <run_tag> [out_dir]
#   SKIP_BUILD=1   reuse the already-built+deployed libgk (skip build+install)
#   OG_FLY_DELAY   kernel ticks after target-ready before the buzzer spawns (180)
#
# Produces, per run, under <out_dir> (default .autoport/reports/Gcrash-geyser):
#   <run_tag>-logcat.log     full GK-tag logcat for the run
#   <run_tag>-result.txt     one-line structured verdict (appended to runs.txt by caller)

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

MODE="${1:-fly}"
RUN_TAG="${2:-run1}"
OUT_DIR="${3:-.autoport/reports/Gcrash-geyser}"
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
  bash .autoport/lib/d3_build.sh
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 25 ) \
      || { echo "FAIL: gradle slim build failed"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + verify fresh HEAD libgk on device =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
  device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gcrash-push.out 2>&1 || { cat /tmp/gcrash-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gcrash-pm.out 2>&1 || { cat /tmp/gcrash-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gcrash-pm.out || { cat /tmp/gcrash-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm warp + census; mode=$MODE tag=$RUN_TAG =="
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp   1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.fly.collect 0 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"

A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gcrash-am.out 2>&1 || true
grep -q 'Error' /tmp/gcrash-am.out && { cat /tmp/gcrash-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() {
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" \
    && grep -qaE '>>> org.opengoal.gk.jak1|GK-DIAG sig=' "$LOG"
}
focus_is_app() {
  A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"
}

echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done

echo "  waiting for warp to fire (up to 90s)..."
for i in $(seq 1 90); do grep -qa "\[F1-WARP\] (start 'play game-start)" "$LOG" && { echo "  warp fired ~${i}s"; break; }; sleep 1; done

echo "  waiting for training (Geyser Rock) load (up to 8min)..."
TRAIN_OK=0
for ((i=1;i<=96;i++)); do
  sleep 5
  if grep -qaE "Adding level training|link finish: training-vis" "$LOG"; then echo "   >>> training loaded ~$((i*5))s"; TRAIN_OK=1; break; fi
  if crash_seen; then echo "   >>> crash before training load"; break; fi
  (( i % 6 == 0 )) && echo "   [load ${i}/96] waiting..."
done

if [ "$TRAIN_OK" != 1 ]; then
  echo "   >>> training never loaded; aborting run"
  echo "RESULT mode=$MODE tag=$RUN_TAG status=NO-TRAINING-LOAD" | tee "$RESULT"
  exit 0
fi

echo "  settle ~25s (no input) before the $MODE sequence..."
clear_inject
for ((i=1;i<=5;i++)); do sleep 5; crash_seen && { echo "   >>> crash during settle"; break; }; done

# Frame-progress baseline (render-thread liveness): F1-STATE samples + send_chain.
fstate_count() { grep -ac 'F1-STATE ' "$LOG" 2>/dev/null || echo 0; }
chain_count()  { grep -ac 'A35-RENDER send_chain' "$LOG" 2>/dev/null || echo 0; }
F0=$(fstate_count); C0=$(chain_count)
echo "   render baseline: F1-STATE=$F0 send_chain=$C0"

if [ "$MODE" = "fly" ]; then
  echo "== FLY: arm fly.collect; kernel spawns a buzzer at Jak, suck+touch collects it =="
  A shell setprop debug.opengoal.fly.collect 1 >/dev/null 2>&1 || true
  # Wait for the spawn marker (hook fires after OG_FLY_DELAY ticks).
  clear_inject
  for i in $(seq 1 30); do grep -qa "FLY-COLLECT spawn buzzer" "$LOG" && { echo "   buzzer spawned ~${i}s after arm"; break; }; sleep 1; done
  # Stay STILL: the buzzer's blue-eco-suck pulls the fly onto Jak and the per-frame
  # touch collects it within ~0.5s. DO NOT drift Jak off the spawn point (fly-A1
  # bug: an aggressive wiggle moved Jak ~7900u away during the 0.33s collect-arm
  # window). Only gentle in-place taps (stay well within the 4915u suck sphere) as
  # insurance after the static window.
  for i in $(seq 1 6); do sleep 1; crash_seen && break; done
  if ! crash_seen; then
    for w in 1 2 3 4; do
      inject "ly=110"; sleep 0.4     # gentle forward tap (~small move)
      inject "ly=144"; sleep 0.4     # gentle back tap (net ~0)
      clear_inject; sleep 0.6
      crash_seen && break
    done
  fi
elif [ "$MODE" = "steps" ] || [ "$MODE" = "sweep" ]; then
  echo "== SWEEP: drive Jak around Geyser Rock — rotate camera, run+spin-attack to break"
  echo "   crates (real scout flies), jump up steps/near walls (clip-force mercneric) =="
  snap() { # screencap to the run dir for visual nav
    A shell screencap -p /sdcard/gc.png >/dev/null 2>&1 || true
    A pull /sdcard/gc.png "$OUT_DIR/$RUN_TAG-snap-$1.png" >/dev/null 2>&1 || true
  }
  snap start
  # Sweep through 8 camera headings; at each, run forward spin-attacking (break
  # crates -> scout flies auto-suck-collect), then jump (climb steps / clip the
  # camera near walls). square=spin attack (bit15), x=jump (bit14), rx=camera.
  HEADINGS="10 40 70 100 160 190 220 250"
  rep=0
  for rx in $HEADINGS; do
    rep=$((rep+1))
    inject "rx=$rx"; sleep 0.7                 # rotate camera to a new heading
    inject "ly=10 rx=$rx"; sleep 1.0           # run forward
    inject "ly=10 square"; sleep 0.6           # spin-attack while moving (crates)
    inject "ly=10 x"; sleep 0.30               # jump (climb / clip)
    inject "ly=10"; sleep 0.6
    inject "ly=10 x"; sleep 0.30               # jump again
    inject "ly=10 square"; sleep 0.5           # spin-attack
    inject "square"; sleep 0.4                 # spin-attack in place
    inject "ly=200"; sleep 0.6                 # back up a little
    clear_inject; sleep 0.5
    [ $((rep % 3)) -eq 0 ] && snap "r$rep"
    crash_seen && { echo "   >>> CRASH during sweep rep $rep heading rx=$rx"; break; }
  done
  snap end
else
  echo "FAIL: unknown mode '$MODE'"; exit 1
fi

echo "  observe ~40s for crash / render-lock after the $MODE sequence..."
LOCK=0
for ((i=1;i<=40;i++)); do
  sleep 1
  crash_seen && { echo "   >>> CRASH detected"; break; }
done
clear_inject

# Render-progress delta over the action window (blue-lock = frames frozen).
F1=$(fstate_count); C1=$(chain_count)
FOC="no"; focus_is_app && FOC="yes"
DF=$(( F1 - F0 )); DC=$(( C1 - C0 ))
echo "   render after: F1-STATE=$F1 (+$DF) send_chain=$C1 (+$DC) focus_app=$FOC"

# Verdict.
SIG=""
if grep -qaE 'GK-DIAG sig=' "$LOG"; then SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+' "$LOG" | tail -1); fi
NEARFN=$(grep -aE 'A38-TRIPWIRE (pc|lr|fault) nearest-fn' "$LOG" | tail -3 | tr '\n' ';')
WHOSYM=$(grep -aE 'A37-WHOSYM' "$LOG" | tail -1)
STOMP=$(grep -aoE '(GCINE3-DEACT-STOMP|GMATCH-RFTD-STOMP|GND-OOB-WRITE)' "$LOG" | sort | uniq -c | tr '\n' ';')
CUR_PROC=$(grep -aE 'GK-DIAG (A34-DIAG|GSPARK-OBJ|GSPARK-PP)' "$LOG" | tail -3 | tr '\n' ';')

STATUS="UNKNOWN"
if crash_seen; then
  STATUS="HARD-CRASH"
elif [ "$DF" -lt 5 ] && [ "$FOC" = "yes" ]; then
  STATUS="RENDER-LOCK(blue?)-frames-frozen-app-foreground"
elif [ "$DF" -ge 5 ]; then
  STATUS="CRASH-FREE-render-advancing(+$DF frames)"
fi

{
  echo "RESULT mode=$MODE tag=$RUN_TAG status=$STATUS"
  echo "  sig=${SIG:-none} focus_app=$FOC F1-STATE +$DF send_chain +$DC"
  echo "  near-fn: ${NEARFN:-none}"
  echo "  whosym: ${WHOSYM:-none}"
  echo "  stomps: ${STOMP:-none}"
  echo "  cur-proc: ${CUR_PROC:-none}"
} | tee "$RESULT"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true
echo "== gcrash_run.sh $MODE/$RUN_TAG done: $STATUS =="
exit 0
