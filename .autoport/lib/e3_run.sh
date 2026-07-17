#!/usr/bin/env bash
# Phase E3 (autoport): device-side driver for the save-portability
# contract. Builds libgk.so + the jak1 APK, installs, starts
# SaveActivity (a dedicated no-SDL activity that drives the kmemcard
# deterministic save writer via NativeGk.writeTestSave), waits for the
# `test save written: <path>` marker, then adb-pulls the produced file
# out to /tmp/E3-android-save.bin where the phase-E3 validator can
# hash it against the desktop x86_64 reference.
#
# The activity is independent of LoaderActivity / MainActivity / SDL —
# its onCreate body is just a JNI call into libgk.so's
# Java_org_opengoal_gk_NativeGk_writeTestSave, which in turn calls
# game/kernel/common/kmemcard.cpp::write_test_save_to_path. The same
# entry point is invoked from the desktop x86 build via main.cpp's
# `-save-then-exit <path>` flag, so the file produced on either side
# comes from the exact same code path.
#
# Artefacts the E3 validator consumes:
#   /tmp/E3-android-save.bin               — the device-produced save
#   .autoport/reports/E3-boot.log          — logcat capture window
#   .autoport/reports/E3-launch.md         — engineering report

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
. .autoport/lib/device_env.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".SaveActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/E3-boot.log"
STATUS_TXT="$REPORT_DIR/E3-status.txt"
REPORT_MD="$REPORT_DIR/E3-launch.md"
SAVE_OUT="/tmp/E3-android-save.bin"

# Where the in-app SaveActivity will write the deterministic save.
# Grecharged-buildsys-firstboot: saves now live in the per-game external
# root ($DEVICE_SAVES = /storage/emulated/0/OpenGOAL/jak1/saves), which is
# world-accessible under the app's MANAGE_EXTERNAL_STORAGE — direct adb
# reads/writes work, no run-as needed.
DEVICE_SAVE_DIR="$DEVICE_SAVES"
DEVICE_SAVE_PATH="$DEVICE_SAVE_DIR/E3-android-save.bin"

export LOGCAT_LOG="$BOOT_LOG"

mkdir -p "$REPORT_DIR"

echo "== E3 step 1/5: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== E3 step 2/5: build jak1 debug APK =="
device_build_flavor jak1

echo "== E3 step 3/5: install + launch SaveActivity =="
device_require_attached
device_require_free_space
device_uninstall_other_games "$PACKAGE"
device_stayon_on

# Truncate so a previous run's bytes don't leak into the marker check.
: > "$BOOT_LOG"

# Wipe any prior save so we can be sure the bytes we pull came from this
# run's write_test_save_to_path call and not a stale carry-over.
adb -s "$S" shell mkdir -p "$DEVICE_SAVE_DIR" >/dev/null 2>&1 || true
adb -s "$S" shell rm -f "$DEVICE_SAVE_PATH" >/dev/null 2>&1 || true

# Decide whether the device already has the exact APK installed. Re-
# installing a 1.18 GB jak1 APK on every iteration is expensive enough
# in /data churn that running validators back-to-back can dump us into
# `Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]` on a near-full
# device — the pm install path needs ~APK_SIZE of scratch on top of
# the existing install, which on a 98%-full /data partition simply
# isn't there. Skipping install when the bytes match avoids that cost
# entirely (and is honest: the binary on disk IS the build we want).
LOCAL_SHA=$(sha256sum "$APK" | awk '{print $1}')
DEVICE_APK_PATH=$(adb shell pm path "$PACKAGE" 2>/dev/null | sed 's|^package:||' | tr -d '\r')
DEVICE_SHA=""
if [ -n "$DEVICE_APK_PATH" ]; then
    DEVICE_SHA=$(adb shell "sha256sum $DEVICE_APK_PATH" 2>/dev/null | awk '{print $1}')
fi
if [ -n "$DEVICE_SHA" ] && [ "$LOCAL_SHA" = "$DEVICE_SHA" ]; then
    echo "  device APK already matches local (sha256=${LOCAL_SHA:0:12}…); skipping install"
    device_require_unlocked
else
    # Stage + install fresh. Mirrors device_install_and_launch's
    # push/pm-install split but with SaveActivity as the launch target.
    device_miui_unblock_install
    APK_STAGE="/data/local/tmp/$(basename "$APK")"
    # Drop any prior staged APK left over from a failed validator
    # iteration. At ~1.2 GB per copy these accumulate on /data fast
    # enough to push pm install into INSUFFICIENT_STORAGE when the
    # next iteration tries to push again. Same goes for the older
    # `jak1.apk` filename that earlier validator iterations of
    # phases 17+ left behind.
    adb shell rm -f "$APK_STAGE" /data/local/tmp/jak1.apk >/dev/null 2>&1 || true
    if ! adb push "$APK" "$APK_STAGE" >/tmp/e3-install-push.out 2>&1; then
        cat /tmp/e3-install-push.out >&2
        device_fail "adb push to $APK_STAGE failed"
    fi
    if ! adb shell pm install -r -d -t -i com.android.vending "$APK_STAGE" \
            >/tmp/e3-install-pm.out 2>&1; then
        cat /tmp/e3-install-pm.out >&2
        adb shell rm -f "$APK_STAGE" >/dev/null 2>&1 || true
        device_fail "pm install rejected the APK"
    fi
    if ! grep -q "Success" /tmp/e3-install-pm.out; then
        cat /tmp/e3-install-pm.out >&2
        adb shell rm -f "$APK_STAGE" >/dev/null 2>&1 || true
        device_fail "pm install did not report Success"
    fi
    adb shell rm -f "$APK_STAGE" >/dev/null 2>&1 || true
    device_require_unlocked
fi

# Stop any prior MainActivity / LoaderActivity so SaveActivity is the
# only entry; SDL state from a half-booted MainActivity would otherwise
# linger on a re-launch.
adb shell am force-stop "$PACKAGE" 2>/dev/null || true

adb logcat -G 8M 2>/dev/null || true
adb logcat -c 2>/dev/null || true

: > "$BOOT_LOG"
adb logcat -v threadtime > "$BOOT_LOG" 2>&1 &
LOGCAT_PID=$!
# Make sure logcat + app are torn down on script exit so the next
# iteration sees a clean slate.
trap "kill $LOGCAT_PID 2>/dev/null; adb shell am force-stop $PACKAGE 2>/dev/null; device_stayon_restore 2>/dev/null" EXIT

echo "  starting $PACKAGE/$ACTIVITY with writeTestSaveTo=$DEVICE_SAVE_PATH"
adb shell am start -W -n "$PACKAGE/$ACTIVITY" \
    --es writeTestSaveTo "$DEVICE_SAVE_PATH" \
    >/tmp/e3-am-start.out 2>&1 || true
if grep -q 'Error' /tmp/e3-am-start.out; then
    cat /tmp/e3-am-start.out >&2
    device_fail "am start SaveActivity failed"
fi

echo "== E3 step 4/5: wait for save-written marker =="

MARKER_HIT=1
if device_wait_for_marker 'test save written: ' 30; then MARKER_HIT=0; fi

# Give SaveActivity a beat to finish() before we pull, so any final
# JNI clean-up (no-op today, but be defensive) is done.
sleep 1

echo "== E3 step 5/5: pull save file from external saves dir =="

# The save is on world-accessible external storage ($DEVICE_SAVES), so a
# plain adb read works — no run-as needed.
if ! adb -s "$S" shell "test -f $DEVICE_SAVE_PATH"; then
    device_fail "save file not present at $DEVICE_SAVE_PATH on device"
fi

# Use base64 to ferry binary bytes through adb shell — a plain `cat`
# through adb shell mixes the bytes with shell stderr / TTY translations
# on some devices and produces a CRLF-translated copy of the file. base64
# armours the bytes against any of that.
adb -s "$S" shell "base64 $DEVICE_SAVE_PATH" 2>/tmp/e3-pull.err \
    | base64 -d > "$SAVE_OUT" || true
if [ ! -s "$SAVE_OUT" ]; then
    cat /tmp/e3-pull.err >&2 || true
    device_fail "adb base64-pull of $DEVICE_SAVE_PATH produced empty $SAVE_OUT"
fi

PULLED_SIZE=$(stat -c %s "$SAVE_OUT")
PULLED_SHA=$(sha256sum "$SAVE_OUT" | cut -d' ' -f1)
echo "  pulled $SAVE_OUT: $PULLED_SIZE bytes, sha256=$PULLED_SHA"

# Tear down logcat capture so the script can exit cleanly. The EXIT
# trap above kills it again as a belt-and-braces backup.
kill $LOGCAT_PID 2>/dev/null || true
trap - EXIT
device_stayon_restore 2>/dev/null || true

# Determination + engineering report.
DETERMINATION="pass"
NOTES=""
if [ "$MARKER_HIT" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="SaveActivity did not log 'test save written:' marker; pulled bytes anyway."
fi
if [ ! -s "$SAVE_OUT" ]; then
    DETERMINATION="fail"
    NOTES="Pulled save file is empty."
fi

echo "$DETERMINATION: $NOTES" > "$STATUS_TXT"
{
    echo "# Phase E3 — UX (save/load binary identity) launch report"
    echo
    echo "_Generated: $(date -Iseconds)_"
    echo
    echo "## Determination"
    echo
    echo "**$DETERMINATION**${NOTES:+ — $NOTES}"
    echo
    echo "## Save artefact"
    echo
    echo "- device path: \`$DEVICE_SAVE_PATH\`"
    echo "- pulled to:   \`$SAVE_OUT\`"
    echo "- bytes:       $PULLED_SIZE"
    echo "- sha256:      $PULLED_SHA"
    echo
    echo "## SaveActivity logcat"
    echo
    if [ -f "$BOOT_LOG" ]; then
        echo '```'
        grep -E '(SaveActivity|writeTestSave|test save written|kmemcard|libgk.so loaded)' "$BOOT_LOG" \
            | head -40 || echo "(no matching markers)"
        echo '```'
    else
        echo "(no $BOOT_LOG produced)"
    fi
} > "$REPORT_MD"

echo
echo "E3 device run: $DETERMINATION${NOTES:+ — $NOTES}"
exit 0
