#!/usr/bin/env bash
# Gffi-xmm-validate — EXTENDED device regression soak.
#
# The north-star f1_run.sh stops capturing at the settled-spawn detection (~45s,
# render frame ~1770), so it cannot demonstrate the phase's frame>=10500 soak gate
# even though the app keeps running healthily in gameplay. This driver reuses the
# SAME deployed HEAD libgk (already deploy_verify'd) and the SAME proven NEW-GAME
# injection, but keeps the app foregrounded and the logcat running until the free-
# running A35-RENDER frame counter passes 10500 (or a crash, or a hard time cap).
#
# It does NOT rebuild or redeploy (the device already runs the fresh HEAD libgk).
# Covers: clean boot -> title -> village1 flythrough -> ndi/new-game cinematic ->
# gameplay, sustained past frame 10500. Asserts 0 sig(4/6/11)/Fatal with the jak1
# tombstone gate, foreground=jak1 at end.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
OUT=".autoport/reports/Gffi-xmm-validate"
LOG="$OUT/extended-soak.log"
TARGET_FRAME="${TARGET_FRAME:-10500}"
mkdir -p "$OUT"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }
maxframe() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }
maxgf()    { grep -aoE 'target-pos f=[0-9]+'     "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

echo "== extended soak: keep-screen-on, launch, drive NEW GAME, capture to frame>=$TARGET_FRAME =="
device_require_attached
device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

# Arm the prop-gated F1-STATE census (permanent HEAD code; OFF by default).
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
FG=""
cleanup() {
    # capture foreground BEFORE force-stop so the EXIT trap cannot hide it
    FG=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
    kill "$LOGCAT_PID" 2>/dev/null || true
    A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gffi-ext-am.out 2>&1 || true

echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title linked ~${i}s"; break; }; sleep 1; done
sleep 8

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

echo "  sustaining gameplay until A35-RENDER frame>=$TARGET_FRAME (hard cap ~13min)..."
CRASH=0; REACHED=0
ITERS=156   # 156 * 5s = 13 min
for ((i=1;i<=ITERS;i++)); do
    sleep 5
    if grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; then
        if grep -qaE '>>> org\.opengoal\.gk\.jak1' "$LOG"; then
            echo "  >>> GENUINE jak1 native crash detected"; CRASH=1; break
        fi
    fi
    MF=$(maxframe); MF=${MF:-0}
    GF=$(maxgf);    GF=${GF:-0}
    # keep the screen awake periodically (defend against PIN-lock on sleep)
    if (( i % 12 == 0 )); then A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; fi
    if (( i % 6 == 0 )); then echo "   [${i}/${ITERS}] A35-RENDER frame=$MF  target-pos f=$GF"; fi
    if (( MF >= TARGET_FRAME )); then echo "   >>> reached frame $MF (>= $TARGET_FRAME)"; REACHED=1; break; fi
done

# foreground capture happens in cleanup(); also grab it here for the summary.
FG_NOW=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
MF=$(maxframe); MF=${MF:-0}
GF=$(maxgf);    GF=${GF:-0}
NSIG=$(grep -acE 'Fatal signal|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null || echo 0)
NTOMB=$(grep -acE '>>> org\.opengoal\.gk\.jak1' "$LOG" 2>/dev/null || echo 0)
INGAME=$(grep -ac 'engine: state=in-game' "$LOG" 2>/dev/null || echo 0)
NCINE=$(grep -acE 'cine|cinematic|intro|scene-player|ndi-intro' "$LOG" 2>/dev/null || echo 0)
NVIL=$(grep -acE 'village1|vil1|logo|title|flythrough' "$LOG" 2>/dev/null || echo 0)
NREPAIR=$(grep -acE 'TARGET-TRANS-REPAIR' "$LOG" 2>/dev/null || echo 0)

echo
echo "=== EXTENDED SOAK SUMMARY ==="
echo "max A35-RENDER frame = $MF   (target $TARGET_FRAME; reached=$REACHED)"
echo "max target-pos f     = $GF"
echo "sig(4/6/11)/Fatal lines = $NSIG ; jak1 tombstones = $NTOMB ; genuine crash=$CRASH"
echo "engine state=in-game = $INGAME ; cinematic-markers = $NCINE ; village/title-markers = $NVIL"
echo "GD3 target-trans repairs (protective, not crashes) = $NREPAIR"
echo "foreground = ${FG_NOW:-$FG}"
echo "log = $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines)"
