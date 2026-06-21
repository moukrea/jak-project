#!/usr/bin/env bash
# Phase F1 (autoport) — north-star device driver.
#
# Builds the current-HEAD libgk (with the property-armed F1-STATE probe in
# game/graphics/opengl_renderer/foreground/Merc2.cpp), deploys it to the Redmi
# via a SLIM APK (libgk-only change; the device already has the HEAD DGOs
# extracted, and F1 does NOT touch goal_src/CGOs so there is no mixed-build
# risk), then drives the canonical NEW-GAME -> intro-cinematic -> Geyser Rock
# ('training) sequence via the cpad_inject watcher and captures the deterministic
# settled game state.
#
# Produces the artefacts the F1 validator inspects:
#   .autoport/reports/F1-boot.log              — GK-tag logcat (link sequence +
#                                                 F1-STATE + engine: state=in-game)
#   .autoport/reports/F1-state-frame-600.json  — device (-> *target* control trans)
#                                                 at the settled training spawn
#   .autoport/reports/F1-screencap-frame-600.png — device framebuffer (best effort)
#   .autoport/reports/F1-status.txt / F1-launch.md
#
# The probe reads the SAME GOAL field the desktop x86 oracle reads
# (cross-validated on x86: C++ probe == listener == -5393129.0/28317.46/4362849.5),
# so the device JSON is directly comparable to F1-desktop-state-frame-600.json.

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
BOOT_LOG="$REPORT_DIR/F1-boot.log"
STATUS_TXT="$REPORT_DIR/F1-status.txt"
REPORT_MD="$REPORT_DIR/F1-launch.md"
SCREENCAP="$REPORT_DIR/F1-screencap-frame-600.png"
STATE_DUMP="$REPORT_DIR/F1-state-frame-600.json"
mkdir -p "$REPORT_DIR"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }

# Guard against a leftover prior runner's trailing force-stop murdering this run.
pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

echo "== F1 step 1/5: build current-HEAD libgk.so (with F1-STATE probe) =="
bash .autoport/lib/d3_build.sh

echo "== F1 step 2/5: build SLIM jak1 debug APK (libgk-only; DGOs already on device) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 40 ) \
    || { echo "FAIL: gradle slim build failed"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }

echo "== F1 step 3/5: install + verify the device runs the fresh HEAD libgk =="
device_require_attached
device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

# Install the slim APK (pm install -r preserves /data/data, so the device keeps
# its already-extracted HEAD DGOs + the iso_data .extracted sentinel — we do NOT
# wipe it, the slim APK carries no iso_data to re-extract).
device_miui_unblock_install
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/f1-push.out 2>&1 || { cat /tmp/f1-push.out; echo "FAIL: push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/f1-pm.out 2>&1 || { cat /tmp/f1-pm.out; echo "FAIL: pm install"; exit 1; }
grep -q "Success" /tmp/f1-pm.out || { cat /tmp/f1-pm.out; echo "FAIL: pm install no Success"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true

# Deploy-landing guard: PROVE the device runs the freshly built HEAD libgk.so.
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify (device not running fresh HEAD libgk)"; exit 1; }

echo "== F1 step 4/5: arm probe, launch, drive NEW GAME -> cinematic -> Geyser Rock =="
# Arm the F1 census BEFORE launch (the probe's static-init reads the prop on the
# first eichar draw). OFF by default; this run turns it on.
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
echo "  prop debug.opengoal.f1.census = $(A shell getprop debug.opengoal.f1.census | tr -d '\r')"

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$BOOT_LOG"

# Capture only the GOAL-runtime tags: opengoal-gk carries the link sequence
# (incl. `link finish: logo`, which trace_diff anchors on); GK_STDOUT carries the
# probe's F1-STATE + `engine: state=in-game`; libc/DEBUG carry native crashes.
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$BOOT_LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
    kill "$LOGCAT_PID" 2>/dev/null || true
    A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/f1-am.out 2>&1 || true
grep -q 'Error' /tmp/f1-am.out && { cat /tmp/f1-am.out; echo "FAIL: am start"; exit 1; }

# Warm up to the interactive title (poll for the title link milestone).
echo "  warming up to title (link finish: logo, up to 90s)..."
for i in $(seq 1 90); do grep -qa "link finish: logo" "$BOOT_LOG" && { echo "  title linked ~${i}s"; break; }; sleep 1; done
sleep 40  # let the attract FULLY settle before the first START. 8s was too short:
          # an unsettled title can eat the first injection and leave the game in
          # the logo-intro attract loop. The proven G-phase reach scripts
          # (gd3_device_census.sh / gcine_cut_reach.sh / gfix_cine_run.sh) all
          # wait ~40s after `link finish: logo` before the first inject.

# Canonical NEW-GAME -> "continue without saving" injection (the proven Gd2/Gd3
# sequence that reaches master-mode=game / Geyser Rock crash-free on this build).
echo "  drive: START -> NEW GAME -> CONTINUE WITHOUT SAVING"
inject "start"; sleep 1.2; clear_inject; sleep 4
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

# Two-phase settle. The probe now streams F1-STATE ONLY for the gameplay player
# model (eichar-lod*), so the boot ND-logo / title-attract / cinematic puppets
# (eichar-ndi-intro, eichar-*-intro-sequence) no longer pollute the capture.
#  (1) Wait for the REAL training-level load — the new-game intro cinematic plays
#      out first (~2-3 min). This is the unfakeable kernel marker the validator
#      also checks; gating on it removes the old early-stop bug where the run
#      latched onto the frozen title-attract samples and quit in ~44s.
#  (2) Once training is loaded, idle with NO input so Jak settles to the spawn
#      rest, letting the probe accumulate a long STABLE run that mirrors the
#      desktop oracle's 42 identical idle samples (the path-independent
#      equilibrium of standing at the training-start continue point).
crash_seen() {
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$BOOT_LOG" \
        && grep -qaE '>>> org.opengoal.gk.jak1' "$BOOT_LOG"
}

echo "  phase 1: wait for training (Geyser Rock) load — cinematic ~2-3min (up to 8min)..."
TRAIN_OK=0
T1=$(( 8 * 60 / 5 ))
for ((i=1;i<=T1;i++)); do
    sleep 5
    if grep -qaE "Adding level training|link finish: training-vis" "$BOOT_LOG"; then
        echo "   >>> training level loaded (~$((i*5))s after new-game inject)"; TRAIN_OK=1; break
    fi
    if crash_seen; then echo "   >>> native crash before training load"; break; fi
    if (( i % 6 == 0 )); then echo "   [load ${i}/${T1}] waiting for training-vis..."; fi
done

SETTLED=0
if [ "$TRAIN_OK" = 1 ]; then
    echo "  phase 2: idle ~150s for Jak to settle at the spawn rest (no input)..."
    clear_inject
    STABLE_NEEDED=60          # ~3s of identical (rounded) samples at device frame rate
    T2=$(( 150 / 5 ))
    for ((i=1;i<=T2;i++)); do
        sleep 5
        if crash_seen; then echo "   >>> native crash during settle"; break; fi
        NSAMP=$(grep -ac 'F1-STATE ' "$BOOT_LOG" 2>/dev/null || echo 0)
        # longest stable run among ALL (gameplay-only) F1-STATE samples (rounded to 1 unit)
        STABLE=$(grep -aE 'F1-STATE tx=' "$BOOT_LOG" 2>/dev/null | awk '
            { if (match($0, /tx=([-0-9.]+) ty=([-0-9.]+) tz=([-0-9.]+)/, m)) {
                k=sprintf("%d|%d|%d", m[1], m[2], m[3]);
                if (k==prev) run++; else run=1; prev=k;
                if (run>best) best=run } }
            END { print best+0 }')
        if (( i % 3 == 0 )); then echo "   [settle ${i}/${T2}] F1-STATE=$NSAMP stable_run=$STABLE"; fi
        if [ "${STABLE:-0}" -ge "$STABLE_NEEDED" ]; then
            echo "   >>> settled at spawn: stable_run=$STABLE (>= $STABLE_NEEDED)"; SETTLED=1
            sleep 10   # deepen the stable run a little, then capture
            break
        fi
    done
fi

echo "== F1 step 5/5: capture screencap + parse settled state =="
# Screencap (best effort) with foreground sanity check.
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus: $FOC"
A shell screencap -p /sdcard/F1-screencap.png >/dev/null 2>&1 || true
A pull /sdcard/F1-screencap.png "$SCREENCAP" >/dev/null 2>&1 || true
A shell rm -f /sdcard/F1-screencap.png >/dev/null 2>&1 || true

# Parse the settled F1-STATE -> JSON (longest stable run = Jak idle at the spawn).
python3 - "$BOOT_LOG" "$STATE_DUMP" <<'PY'
import sys, re, json
log, out = sys.argv[1], sys.argv[2]
pat = re.compile(r'F1-STATE tx=([-0-9.]+) ty=([-0-9.]+) tz=([-0-9.]+)')
samples = []
with open(log, encoding='utf-8', errors='replace') as fh:
    for line in fh:
        m = pat.search(line)
        if m:
            samples.append(tuple(float(x) for x in m.groups()))
if not samples:
    print("F1-PARSE: no F1-STATE samples — device never reached gameplay probe", file=sys.stderr)
    sys.exit(0)  # leave STATE_DUMP absent -> validator fails honestly with a clear msg
# longest run of consecutive samples identical when rounded to 1 unit
def key(s): return tuple(round(v) for v in s)
best_run, best_val, run, prev = 0, None, 0, None
for s in samples:
    k = key(s)
    if k == prev:
        run += 1
    else:
        run, prev = 1, k
    if run >= best_run:
        best_run, best_val = run, s   # representative full-precision sample of the run
tx, ty, tz = best_val
json.dump({"target_trans": {"x": tx, "y": ty, "z": tz}},
          open(out, 'w'), indent=2)
print(f"F1-PARSE: {len(samples)} samples, longest stable run={best_run}, "
      f"settled=({tx}, {ty}, {tz}) -> {out}", file=sys.stderr)
PY

# Determination + status.
DET="fail"; NOTES=""
if grep -qaE "load 'geyser-rock|engine: state=in-game|geyser-rock.*loaded" "$BOOT_LOG" && [ -f "$STATE_DUMP" ]; then
    DET="pass"; NOTES="reached Geyser Rock; settled state dumped"
elif grep -qa "link finish: logo" "$BOOT_LOG"; then
    DET="fail"; NOTES="reached title but not a settled in-game state (see F1-boot.log)"
else
    DET="fail"; NOTES="never reached title link"
fi
echo "$DET: $NOTES" > "$STATUS_TXT"

{
    echo "# Phase F1 — Geyser Rock gameplay launch report"
    echo; echo "_Generated: $(date -Iseconds)_"; echo
    echo "## Determination"; echo; echo "**$DET**${NOTES:+ — $NOTES}"; echo
    echo "## Artefacts"; echo
    echo "- boot log:   \`$BOOT_LOG\` ($(wc -l < "$BOOT_LOG" 2>/dev/null || echo 0) lines)"
    [ -f "$STATE_DUMP" ] && echo "- state dump: \`$STATE_DUMP\` -> $(cat "$STATE_DUMP" | tr -d '\n' | tr -s ' ')"
    [ -f "$SCREENCAP" ] && echo "- screencap:  \`$SCREENCAP\` ($(stat -c %s "$SCREENCAP") bytes)"
    echo; echo "## Marker scoreboard"; echo; echo '```'
    for p in "link finish: logo" "engine: state=in-game" "F1-STATE tx=" "Fatal signal"; do
        printf "  %-30s %d\n" "$p" "$(grep -ac "$p" "$BOOT_LOG" 2>/dev/null || echo 0)"
    done
    echo '```'
} > "$REPORT_MD"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true

echo
echo "F1 device run: $DET${NOTES:+ — $NOTES}"
exit 0
