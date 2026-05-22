#!/usr/bin/env bash
# Phase F1 (autoport): device-side build → install → launch →
# (would-be input-drive) → capture. Produces the artefacts the F1
# validator inspects:
#
#   .autoport/reports/F1-boot.log               — 120 s logcat capture
#   .autoport/reports/F1-screencap-frame-600.png — device framebuffer
#   .autoport/reports/F1-status.txt              — single-line determination
#   .autoport/reports/F1-launch.md               — engineering report
#
# State-dump artefact (.autoport/reports/F1-state-frame-600.json) is
# emitted by the device's native JNI hook once the GOAL VM dispatcher
# is actually running on arm64. The dispatcher is currently short-
# circuited by the runtime skip-flag described in
# .autoport/reports/A5-shim-audit.md (the off-register emitter bug in
# goalc/emitter/IGenARM64.cpp). Until that bug is fixed by a follow-up
# codegen phase (e.g. A6-emitter-off-register), the dispatcher never
# advances and the JNI hook has no game-state to dump. This script
# still produces the boot log + screencap + report so the F1
# validator's other checks (codegen lock, shim governance, desktop
# smoke) run, and so the post-A6 retry inherits a working device-
# driver without rewriting anything.
#
# Differences from e3_run.sh (which writes a save and exits cleanly):
#   * Launches MainActivity (the SDL/GLES gameplay activity), not
#     SaveActivity — the goal is to drive gameplay, not write a save.
#   * Wider capture window (120 s vs E3's 30 s) — title→menu→New Game
#     →level-load takes minutes once the dispatcher actually runs.
#   * Drives a fixed input sequence via `adb shell input` after a
#     warm-up window. The sequence (forward + jump + forward + jump-
#     jump) matches the F1 prompt's recorded-input determinism check.
#     Input events that arrive while the dispatcher is in the passive
#     sleep loop are harmless no-ops (the loop reads no input), so
#     this script is forward-compatible: it will exercise gameplay
#     immediately after A6 lands without any further changes.
#   * Pulls a screencap at the input-end timestamp (~frame 600 once
#     the dispatcher runs at 30 FPS).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

# Launch LoaderActivity (the LAUNCHER). It extracts the APK-bundled
# iso_data on first run, then startActivity()s MainActivity which is
# where the SDL/GLES gameplay loop lives. Subsequent launches see the
# .extracted_v1 sentinel and pass through in <100 ms.
# MainActivity itself does not have an applicationId-prefixed alias
# (only LoaderActivity does), so `am start -n <pkg>/.MainActivity`
# would resolve to <pkg>.MainActivity which the manifest doesn't
# declare. Going through LoaderActivity is the canonical D4/E1/E2
# launch path.
PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/F1-boot.log"
STATUS_TXT="$REPORT_DIR/F1-status.txt"
REPORT_MD="$REPORT_DIR/F1-launch.md"
SCREENCAP="$REPORT_DIR/F1-screencap-frame-600.png"
STATE_DUMP="$REPORT_DIR/F1-state-frame-600.json"

export LOGCAT_LOG="$BOOT_LOG"

mkdir -p "$REPORT_DIR"

echo "== F1 step 1/5: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== F1 step 2/5: build jak1 debug APK =="
device_build_flavor jak1

echo "== F1 step 3/5: install + launch MainActivity =="
device_require_attached
device_require_free_space
device_uninstall_other_games "$PACKAGE"
device_stayon_on

: > "$BOOT_LOG"

# Re-use the E3-style "skip install when device has the exact APK"
# fast path. Iterating the F1 validator without re-installing a 1.18 GB
# APK every time saves several minutes and avoids INSUFFICIENT_STORAGE
# on the user's near-full /data partition.
LOCAL_SHA=$(sha256sum "$APK" | awk '{print $1}')
DEVICE_APK_PATH=$(adb shell pm path "$PACKAGE" 2>/dev/null | sed 's|^package:||' | tr -d '\r')
DEVICE_SHA=""
if [ -n "$DEVICE_APK_PATH" ]; then
    DEVICE_SHA=$(adb shell "sha256sum $DEVICE_APK_PATH" 2>/dev/null | awk '{print $1}')
fi
if [ -n "$DEVICE_SHA" ] && [ "$LOCAL_SHA" = "$DEVICE_SHA" ]; then
    echo "  device APK already matches local (sha256=${LOCAL_SHA:0:12}…); skipping install"
    device_require_unlocked
    # The LoaderActivity-side iso_data extraction sentinel can stay —
    # APK bytes match local so the bundled iso_data is identical to
    # what's already extracted.
else
    # iso_data sentinel invalidation (same rationale as d4_run.sh):
    # a new APK build can carry regenerated CGOs whose contents differ
    # from the cached extraction. Wipe the sentinel so LoaderActivity
    # re-extracts fresh.
    adb shell run-as "$PACKAGE" rm -f "files/iso_data/jak1/.extracted_v1" >/dev/null 2>&1 || true
    device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"
fi

# Stop any prior activity from a half-run so MainActivity starts clean.
adb shell am force-stop "$PACKAGE" 2>/dev/null || true

adb logcat -G 8M 2>/dev/null || true
adb logcat -c 2>/dev/null || true

adb logcat -v threadtime > "$BOOT_LOG" 2>&1 &
LOGCAT_PID=$!
trap "kill $LOGCAT_PID 2>/dev/null; adb shell am force-stop $PACKAGE 2>/dev/null; device_stayon_restore 2>/dev/null" EXIT

echo "  starting $PACKAGE/$ACTIVITY"
adb shell am start -W -n "$PACKAGE/$ACTIVITY" \
    >/tmp/f1-am-start.out 2>&1 || true
if grep -q 'Error' /tmp/f1-am-start.out; then
    cat /tmp/f1-am-start.out >&2
    device_fail "am start MainActivity failed"
fi

echo "== F1 step 4/5: drive recorded input sequence =="

# Warm-up window: let the kernel link KERNEL.CGO + GAME.CGO + TIT.DGO
# and reach `link finish: logo` before we start hammering inputs.
# Once the dispatcher is alive (post-A6), this is roughly when the
# title screen is interactive.
WARMUP_S=15
echo "  warming up ${WARMUP_S}s for kernel + title link..."
sleep "$WARMUP_S"

# Synthetic input via Android `adb shell input keyevent`. We send the
# F1 prompt's "forward + jump + forward + jump-jump" sequence using
# generic KEYCODE_BUTTON_* events that the SDL3 input layer maps to
# SDL_GAMEPAD_BUTTON_* (mapping is in android_input_audio.cpp's
# on_pad_button JNI hook). Once the dispatcher is alive, the GOAL
# kernel reads these via the *cpad-list* poll path and they reach the
# title menu's state machine via the same path a real Bluetooth pad
# uses.
#
# KEYCODE_BUTTON_START   = 108 — START
# KEYCODE_BUTTON_A       = 96  — × (cross)  jump / confirm
# KEYCODE_DPAD_UP        = 19  — forward (left stick up if no D-pad)
# Sequence rationale (mapped to title→menu→new game→training):
#   1) START to dismiss title splash → menu
#   2) A to confirm "New Game"
#   3) UP repeatedly to walk forward in-level
#   4) A (jump), UP, A, A (jump-jump) to match the prompt's
#      "forward + jump + forward + jump-jump" gameplay sequence

drive_event() {
    local kc="$1"
    local pause="${2:-0.3}"
    adb shell input keyevent "$kc" >/dev/null 2>&1 || true
    sleep "$pause"
}

echo "  drive: START (dismiss title splash)"
drive_event 108 1.5

echo "  drive: A (confirm 'New Game')"
drive_event 96 4.0   # level load can take a few seconds

echo "  drive: UP UP UP (walk forward into Geyser Rock)"
drive_event 19 0.4
drive_event 19 0.4
drive_event 19 0.4

echo "  drive: A (jump 1)"
drive_event 96 0.6

echo "  drive: UP UP (more forward)"
drive_event 19 0.4
drive_event 19 0.4

echo "  drive: A A (jump-jump)"
drive_event 96 0.4
drive_event 96 0.4

# Hold the renderer alive long enough to reach frame 600 at the
# device's actual refresh rate. The Adreno 618 produces ~50 FPS in
# the clear+swap loop; at 30 FPS (matching desktop) frame 600 is ~20 s
# of game time. Allow 30 s of tail capture either way so the boot
# log includes whatever the dispatcher emitted around that point.
echo "  tail-capture window (30 s)..."
sleep 30

echo "== F1 step 5/5: capture screencap + tear down =="

# Screencap at the input-end timestamp. Even without the dispatcher
# running, this captures the renderer's blue clear (proves the
# clear/swap loop is alive) — and post-A6 it would capture the actual
# Geyser Rock framebuffer.
adb shell screencap -p /sdcard/F1-screencap.png 2>/dev/null || true
adb pull /sdcard/F1-screencap.png "$SCREENCAP" >/dev/null 2>&1 || true
adb shell rm -f /sdcard/F1-screencap.png 2>/dev/null || true
if [ -f "$SCREENCAP" ]; then
    echo "  screencap captured: $SCREENCAP ($(stat -c %s "$SCREENCAP") bytes)"
else
    echo "  WARN: screencap pull failed (device may have rotated the screen off)"
fi

# Game-state dump. The JNI hook
# Java_org_opengoal_gk_NativeGk_dumpStateFrame in libgk.so reads
# *target* / *target-control* fields from the GOAL kernel and writes
# JSON to filesDir. The hook is not yet implemented because the
# dispatcher is short-circuited (see F1-blocker-analysis.md); when A6
# lands and the dispatcher actually runs, MainActivity invokes the
# hook at frame 600 via a Handler.postDelayed equivalent. For now
# this path is intentionally absent — the F1 validator will fail
# the "state dump missing" check with a clear message, and that
# failure is the honest reflection of the underlying blocker.
DEVICE_STATE_PATH="/data/data/$PACKAGE/files/F1-state-frame-600.json"
if adb shell "run-as $PACKAGE test -f $DEVICE_STATE_PATH" 2>/dev/null; then
    adb shell "run-as $PACKAGE base64 $DEVICE_STATE_PATH" 2>/dev/null \
        | base64 -d > "$STATE_DUMP" || true
    echo "  state dump pulled: $STATE_DUMP"
fi

# Tear down logcat capture. EXIT trap above also kills it as backup.
kill $LOGCAT_PID 2>/dev/null || true
trap - EXIT
adb shell am force-stop "$PACKAGE" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

# Determination — looking at the F1 contract, the meaningful question
# is whether the dispatcher actually advanced past title. The validator
# greps for `load 'geyser-rock|engine: state=in-game|geyser-rock.*loaded`
# which only fires once the kernel reaches gameplay state.
DETERMINATION="fail"
NOTES=""
if grep -qE "load 'geyser-rock|engine: state=in-game|geyser-rock.*loaded" "$BOOT_LOG" 2>/dev/null; then
    DETERMINATION="pass"
elif grep -q "KernelCheckAndDispatch: skip-flag armed" "$BOOT_LOG" 2>/dev/null; then
    DETERMINATION="blocked"
    NOTES="dispatcher in passive sleep loop; goalc-arm64 off-register bug — see F1-blocker-analysis.md"
elif grep -q "link finish: logo" "$BOOT_LOG" 2>/dev/null; then
    DETERMINATION="fail"
    NOTES="reached title link but never gameplay state (dispatcher status unclear from log)"
else
    DETERMINATION="fail"
    NOTES="never reached title link — earlier in the boot sequence than E1's milestone"
fi

echo "$DETERMINATION: $NOTES" > "$STATUS_TXT"

# Engineering report — mirrors the shape of D4-launch.md / E1-launch.md
# so the SUPERVISOR_JOURNAL can pull canonical markers from a known
# location.
{
    echo "# Phase F1 — Geyser Rock gameplay launch report"
    echo
    echo "_Generated: $(date -Iseconds)_"
    echo
    echo "## Determination"
    echo
    echo "**$DETERMINATION**${NOTES:+ — $NOTES}"
    echo
    echo "## Artefacts"
    echo
    echo "- boot log:    \`$BOOT_LOG\` ($(wc -l < "$BOOT_LOG" 2>/dev/null || echo 0) lines)"
    if [ -f "$SCREENCAP" ]; then
        echo "- screencap:   \`$SCREENCAP\` ($(stat -c %s "$SCREENCAP" 2>/dev/null) bytes)"
    fi
    if [ -f "$STATE_DUMP" ]; then
        echo "- state dump:  \`$STATE_DUMP\` ($(stat -c %s "$STATE_DUMP" 2>/dev/null) bytes)"
    else
        echo "- state dump:  NOT PRODUCED — JNI hook depends on dispatcher (see F1-blocker-analysis.md)"
    fi
    echo
    echo "## Marker scoreboard"
    echo
    echo "Counts from \`$BOOT_LOG\`:"
    echo
    echo '```'
    for pattern in \
            "MainActivity onCreate done" \
            "InitIOP OK" \
            "Initialized GOAL heap" \
            "link finish: gcommon" \
            "link finish: gkernel" \
            "link finish: gstate" \
            "link finish: logo" \
            "android_renderer_run: entered" \
            "android_renderer: sustained swap" \
            "KernelCheckAndDispatch: skip-flag armed" \
            "KernelCheckAndDispatch: jak1 dispatcher returned" \
            "Displaying level" \
            "load 'geyser-rock" \
            "engine: state=in-game" \
            "jak1::InitMachine ABORT" \
            "F DEBUG signal"; do
        n=$(grep -c "$pattern" "$BOOT_LOG" 2>/dev/null || echo 0)
        printf "  %-45s %d\n" "$pattern" "$n"
    done
    echo '```'
    echo
    echo "## Notes"
    echo
    if [ "$DETERMINATION" = "blocked" ]; then
        cat <<'EOF'
The runtime skip-flag dodge introduced in D4 and retained at A5 is
still armed. The dispatcher reaches `KernelCheckAndDispatch` then
sleeps without forwarding to `jak1::KernelCheckAndDispatch`. This is
the documented consequence of the off-register goalc-arm64 emitter
bug — see `.autoport/reports/F1-blocker-analysis.md` and
`.autoport/reports/A5-shim-audit.md`.

Path forward: an A6-emitter-off-register phase that fixes
`load_goal_gpr` / `store_goal_gpr` / `load_goal_xmm32` /
`load_goal_xmm128` / `store_goal_xmm32` / `store_goal_vf` in
`goalc/emitter/IGenARM64.cpp` to emit `ADD X16, Xbase, X15; LDR/STR
Wt, [X16, #imm12]` instead of dropping the off register.
EOF
    fi
} > "$REPORT_MD"

echo
echo "F1 device run: $DETERMINATION${NOTES:+ — $NOTES}"
exit 0
