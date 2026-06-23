#!/usr/bin/env bash
# Phase F3 (autoport) — 30 FPS sustained device driver.
#
# Builds the current-HEAD libgk (with the F3 per-frame render-cadence probe in
# android/android_renderer.cpp + the 60 Hz simulation-tick probe in the Gd1
# vblank pacer in android/android_gfx.cpp), deploys it via a SLIM APK (libgk-only
# change; the device already has the HEAD DGOs and F3 touches no goal_src/CGOs),
# warps into Geyser Rock ('training) gameplay exactly like f1_run.sh, then runs a
# 60 s gameplay measurement window:
#
#   * debug.opengoal.f3.measure=1 arms BOTH probes for the window:
#       - the render swap loop records each swap-to-swap delta (microseconds,
#         SDL_GetPerformanceCounter) to $HOME/F3-frame-times.csv and reports a
#         WINDOW-scoped "sustained swap N" counter (= real render FPS over 60 s);
#       - the wall-clock 60 Hz IOP/overlord vblank pacer logs one "display tick"
#         per fired vblank — the honest simulation-rate heartbeat, which stays
#         60 Hz regardless of the render rate (Gd1 decoupling).
#   * movement input is injected for the whole window so the renderer is under
#     real gameplay load (camera sweeps + walking), not an idle title screen.
#
# Produces the artefacts the F3 validator inspects:
#   .autoport/reports/F3-boot.log         — GK-tag logcat of the 60 s window
#                                           (sustained swap N + display tick + crashes)
#   .autoport/reports/F3-frame-times.csv  — per-frame microsecond deltas
#
# The simulation rate is NOT halved: the render cadence and the 60 Hz vblank are
# independent threads (vsync() paces the chain builder to the swap; the pacer
# fires the vblank at wall-clock 60 Hz). Same-behavior contract preserved.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/F3-boot.log"
FRAME_CSV="$REPORT_DIR/F3-frame-times.csv"
STATUS_TXT="$REPORT_DIR/F3-status.txt"
SETUP_LOG="/tmp/f3-setup.log"
WINDOW_SECS="${F3_WINDOW_SECS:-60}"
mkdir -p "$REPORT_DIR"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }

# Guard against a leftover prior runner's trailing force-stop murdering this run.
pkill -f 'logcat.*opengoal-gk' 2>/dev/null || true

echo "== F3 step 1/6: build current-HEAD libgk.so (F3 cadence + sim-tick probes) =="
# Force the two F3 TUs to recompile so the .so provably reflects the edits
# (deploy_verify also enforces freshness vs source mtime + HEAD).
touch android/android_renderer.cpp android/android_gfx.cpp
bash .autoport/lib/d3_build.sh

echo "== F3 step 2/6: build SLIM jak1 debug APK (libgk-only; DGOs already on device) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 20 ) \
    || { echo "FAIL: gradle slim build failed"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }

echo "== F3 step 3/6: install + verify the device runs the fresh HEAD libgk =="
device_require_attached
device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

device_miui_unblock_install
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/f3-push.out 2>&1 || { cat /tmp/f3-push.out; echo "FAIL: push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/f3-pm.out 2>&1 || { cat /tmp/f3-pm.out; echo "FAIL: pm install"; exit 1; }
grep -q "Success" /tmp/f3-pm.out || { cat /tmp/f3-pm.out; echo "FAIL: pm install no Success"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true

bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify (device not running fresh HEAD libgk)"; exit 1; }

echo "== F3 step 4/6: arm warp, launch, settle at Geyser Rock gameplay =="
# Reuse the F1 deterministic warp to reach the Geyser Rock 'training game-start
# spawn (bypasses the separately-tracked arm64 intro cinematic). F3 measure is
# OFF here so boot frames never reach the CSV.
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f3.measure 0 >/dev/null 2>&1 || true
echo "  prop debug.opengoal.f1.warp     = $(A shell getprop debug.opengoal.f1.warp | tr -d '\r')"

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
clear_inject
A shell run-as "$PACKAGE" rm -f files/F3-frame-times.csv >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$SETUP_LOG"

# Boot-phase capture (separate from the window log) to watch for the markers.
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$SETUP_LOG" 2>&1 &
SETUP_PID=$!
cleanup() {
    kill "$SETUP_PID" 2>/dev/null || true
    kill "${WIN_PID:-}" 2>/dev/null || true
    A shell setprop debug.opengoal.f3.measure 0 >/dev/null 2>&1 || true
    clear_inject
    A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/f3-am.out 2>&1 || true
grep -q 'Error' /tmp/f3-am.out && { cat /tmp/f3-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() {
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$1" \
        && grep -qaE '>>> org.opengoal.gk.jak1' "$1"
}

echo "  warming up to title (link finish: logo, up to 150s)..."
for i in $(seq 1 150); do grep -qa "link finish: logo" "$SETUP_LOG" && { echo "  title linked ~${i}s"; break; }; sleep 1; done

echo "  waiting for warp + Geyser Rock (training-vis) load — cinematic load can take ~2-3min (up to 9min)..."
TRAIN_OK=0
T1=$(( 9 * 60 / 5 ))
for ((i=1;i<=T1;i++)); do
    sleep 5
    if grep -qaE "Adding level training|link finish: training-vis" "$SETUP_LOG"; then
        echo "   >>> Geyser Rock (training) loaded (~$((i*5))s)"; TRAIN_OK=1; break
    fi
    if crash_seen "$SETUP_LOG"; then echo "   >>> native crash before training load"; break; fi
    if (( i % 6 == 0 )); then echo "   [load ${i}/${T1}] waiting for training-vis..."; fi
done

if [ "$TRAIN_OK" != 1 ]; then
    echo "FAIL: never reached Geyser Rock gameplay — cannot honestly measure gameplay FPS"
    echo "      (see $SETUP_LOG tail)"; tail -30 "$SETUP_LOG"
    exit 1
fi

# Let the level fully settle (streaming/decompress) so the window measures
# steady-state gameplay, not the load spike.
echo "  letting Geyser Rock settle for 20s before the measurement window..."
sleep 20
if crash_seen "$SETUP_LOG"; then echo "FAIL: native crash during settle"; tail -30 "$SETUP_LOG"; exit 1; fi

echo "== F3 step 5/6: ${WINDOW_SECS}s gameplay measurement window =="
# Stop the boot capture, clear, start the clean window capture so F3-boot.log
# contains ONLY the window (window-scoped swap counter + prop-gated ticks).
kill "$SETUP_PID" 2>/dev/null || true
A logcat -c >/dev/null 2>&1 || true
: > "$BOOT_LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$BOOT_LOG" 2>&1 &
WIN_PID=$!

# Arm the F3 probes, then drive movement input for the window. The injected
# state is HELD (the watcher re-reads every 25 ms) until overwritten, so we
# rotate through camera sweeps + walking to keep the renderer under varied,
# realistic gameplay load. Avoid attack/jump-into-flies (known Gcrash-mouche).
A shell setprop debug.opengoal.f3.measure 1 >/dev/null 2>&1 || true
echo "  measure armed; driving gameplay for ${WINDOW_SECS}s..."

# Movement program: (label, inject-state, hold-seconds). Camera rx pans sweep
# the whole level through the frustum = worst-case renderer load.
SEQ=(
  "walk-forward+pan-right|ly=40 rx=190|7"
  "pan-camera-right|rx=205|6"
  "walk-forward|ly=30|6"
  "strafe-left+pan|lx=40 rx=70|6"
  "walk-back+pan-left|ly=215 rx=70|6"
  "pan-camera-left|rx=55|6"
  "walk-forward+pan-right|ly=40 rx=190|7"
  "circle-strafe|lx=210 rx=190|6"
  "walk-forward|ly=30|6"
  "idle-pan|rx=200|4"
)
WIN_START=$SECONDS
for entry in "${SEQ[@]}"; do
    IFS='|' read -r label state secs <<< "$entry"
    # Trim so the total never overshoots WINDOW_SECS (keeps tick count in band).
    elapsed=$(( SECONDS - WIN_START ))
    remain=$(( WINDOW_SECS - elapsed ))
    [ "$remain" -le 0 ] && break
    [ "$secs" -gt "$remain" ] && secs="$remain"
    inject "$state"
    sleep "$secs"
    if crash_seen "$BOOT_LOG"; then echo "   >>> native crash during measurement window"; break; fi
done
# Pad out any remaining time at idle-pan so the window is a full WINDOW_SECS.
elapsed=$(( SECONDS - WIN_START ))
if [ "$elapsed" -lt "$WINDOW_SECS" ]; then
    inject "rx=200"
    sleep $(( WINDOW_SECS - elapsed ))
fi

# Disarm: the renderer flushes + closes the CSV; the pacer stops ticking.
A shell setprop debug.opengoal.f3.measure 0 >/dev/null 2>&1 || true
clear_inject
sleep 3   # let the prop poll notice + the CSV flush land
kill "$WIN_PID" 2>/dev/null || true

echo "== F3 step 6/6: pull CSV + report =="
# exec-out (no pty) + tr -d '\r' so the CSV is pure "<int>\n" rows the validator parses.
A exec-out run-as "$PACKAGE" cat files/F3-frame-times.csv 2>/dev/null | tr -d '\r' > "$FRAME_CSV"
CSV_ROWS=$(grep -cE '^[0-9]+$' "$FRAME_CSV" 2>/dev/null || echo 0)

SWAP=$(grep -oE "sustained swap [0-9]+" "$BOOT_LOG" 2>/dev/null | awk '{print $3}' | sort -n | tail -1)
TICKS=$(grep -cE "display tick" "$BOOT_LOG" 2>/dev/null || echo 0)

# Local stats echo (the validator recomputes authoritatively).
python3 - "$FRAME_CSV" <<'PY' 2>/dev/null || true
import csv, sys, statistics
t=[]
with open(sys.argv[1]) as f:
    for r in csv.reader(f):
        if r and r[0].lstrip('-').isdigit(): t.append(int(r[0]))
if t:
    p95=sorted(t)[int(len(t)*0.95)]; p99=sorted(t)[int(len(t)*0.99)]
    print(f"  CSV: frames={len(t)} avg={statistics.mean(t)/1000:.2f}ms "
          f"p95={p95/1000:.2f}ms p99={p99/1000:.2f}ms "
          f"~fps={1e6/statistics.mean(t):.1f}")
PY

{
    echo "F3 device run $(date -Iseconds)"
    echo "  Geyser Rock gameplay window: ${WINDOW_SECS}s"
    echo "  sustained swap (window max): ${SWAP:-none}  (need >=1800 = 30fps)"
    echo "  simulation ticks (60Hz):     ${TICKS:-0}    (need 3400..3800)"
    echo "  frame CSV rows:              ${CSV_ROWS:-0}"
} > "$STATUS_TXT"
cat "$STATUS_TXT"

kill "$WIN_PID" "$SETUP_PID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.f3.measure 0 >/dev/null 2>&1 || true
clear_inject
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true

echo
echo "F3 device run complete: swap=${SWAP:-none} ticks=${TICKS:-0} csv_rows=${CSV_ROWS:-0}"
exit 0
