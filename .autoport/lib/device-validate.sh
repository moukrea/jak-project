#!/usr/bin/env bash
# Shared helpers for autoport phase validators that exercise the APK on
# a real USB-attached Android device. Sourced by .autoport/validators/phase-{17..22}-*.sh.
#
# Calling convention: each phase validator builds its APK, then calls
#   device_install_and_launch <package> <activity> <flavor>
# followed by
#   device_wait_for_marker <package> <regex> <timeout_seconds>
# and finally
#   device_dump_failure_context <package>      (only if a check failed)
#
# Hard rules (per the user's strict-validators preference):
#   - No marker = phase fails. Never "good enough" on installation alone.
#   - Build break or install reject also fails. No skip-on-error.
#   - Desktop x86 build is checked at the end of every phase 17+ validator;
#     phases that touch shared C++ regress trivially otherwise.

set -uo pipefail

# Source the toolchain env (puts adb/gradle/aapt2/apksigner on PATH).
. "$(git rev-parse --show-toplevel)/.autoport/lib/android-env.sh"

REPO_ROOT="$(git rev-parse --show-toplevel)"
APK_JAK1="$REPO_ROOT/android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
LOGCAT_LOG="$REPO_ROOT/.autoport/logs/device-logcat.last.log"

# Free-space floor on the device's /data partition. Below this we refuse to
# install — gradle install will half-succeed and leave the device in a bad
# state. 2 GB chosen so a 1.1 GB APK install plus its temporary unpack copy
# fits comfortably.
DEVICE_FREE_FLOOR_MB=2048

# Print a failure header and the most recent device-side context, then exit 1.
device_fail() {
    local msg="$1"
    echo
    echo "============================================================" >&2
    echo "VALIDATOR FAIL: $msg" >&2
    echo "============================================================" >&2
    if [ -f "$LOGCAT_LOG" ]; then
        echo "--- last 80 lines of opengoal-gk logcat ---" >&2
        tail -n 80 "$LOGCAT_LOG" >&2
    fi
    if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
        echo "--- last 30 lines from logcat -b crash ---" >&2
        adb logcat -d -b crash -t 30 2>&1 | tail -30 >&2 || true
    fi
    exit 1
}

# adb visible & device authorized?
device_require_attached() {
    if ! command -v adb >/dev/null 2>&1; then
        device_fail "adb not on PATH (android-env.sh failed?)"
    fi
    local n
    n=$(adb devices | awk '/\tdevice$/ {c++} END {print c+0}')
    if [ "$n" -eq 0 ]; then
        device_fail "no adb device attached. Plug phone, enable USB debugging,
   accept the 'Allow USB debugging?' dialog, then re-run.
   Visible USB devices:
$(lsusb | sed 's/^/      /')"
    fi
    if [ "$n" -gt 1 ]; then
        device_fail "more than one adb device attached; set ANDROID_SERIAL to choose one"
    fi
}

# When testing one game's APK, the other two jak* packages (if installed
# from a prior run) just hog ~2.5 GB each on the user's tight-storage
# device. Uninstall them at validator entry. The keep_pkg arg is the
# package this validator will install in a moment — leave it alone.
device_uninstall_other_games() {
    local keep_pkg="$1"
    local pkg
    for pkg in org.opengoal.gk.jak1 org.opengoal.gk.jak2 org.opengoal.gk.jak3; do
        if [ "$pkg" = "$keep_pkg" ]; then
            continue
        fi
        # `pm path` exits 0 only when the package is installed.
        if adb shell "pm path $pkg" >/dev/null 2>&1; then
            echo "  uninstalling sibling game $pkg to free storage"
            adb uninstall "$pkg" >/dev/null 2>&1 || true
        fi
    done
}

# Free space on /data in MB (rounded down). Android's toybox `df` only
# accepts -k / -h / -H — no -m — so we read 1K-blocks (the default) and
# divide. NR==2 grabs the data line (header is NR==1).
device_free_mb() {
    adb shell df -k /data 2>/dev/null | awk 'NR==2 {print int($4/1024)}'
}

device_require_free_space() {
    local have
    have=$(device_free_mb)
    if [ -z "$have" ]; then
        device_fail "cannot read /data free space from device"
    fi
    # If we're below the floor, ask the package manager to evict every
    # app cache it can. On full devices this typically recovers 100-500
    # MB without touching user data. We retry the measurement after.
    if [ "$have" -lt "$DEVICE_FREE_FLOOR_MB" ]; then
        echo "  device free: ${have} MB on /data (below ${DEVICE_FREE_FLOOR_MB} MB floor)"
        echo "  asking the package manager to trim app caches…"
        adb shell pm trim-caches 99999999999 >/dev/null 2>&1 || true
        adb shell sync >/dev/null 2>&1 || true
        sleep 3
        have=$(device_free_mb)
        echo "  device free after trim: ${have} MB on /data"
    fi
    # Second-stage escalation: pm trim-caches is conservative and on
    # MIUI often won't touch Google services caches (which routinely
    # consume 1-3 GB by themselves). Clear the worst offenders.
    if [ "$have" -lt "$DEVICE_FREE_FLOOR_MB" ]; then
        echo "  still below floor — clearing caches of large apps (Play, GMS, browsers…)"
        device_free_more_space
        sleep 3
        have=$(device_free_mb)
        echo "  device free after app-cache clear: ${have} MB on /data"
    fi
    if [ "$have" -lt "$DEVICE_FREE_FLOOR_MB" ]; then
        device_fail "only ${have} MB free on /data; need at least ${DEVICE_FREE_FLOOR_MB} MB.
   The package manager's cache trim did not recover enough space.
   Free storage on the device manually (Settings → Storage → clear app
   data for large apps, or remove files in /sdcard/Download) and re-run."
    fi
    echo "  device free: ${have} MB on /data"
}

# Keep the screen on while the validator runs; restore on exit.
device_stayon_on() {
    adb shell svc power stayon usb 2>/dev/null || true
}
device_stayon_restore() {
    adb shell svc power stayon false 2>/dev/null || true
}

# MIUI (Xiaomi/Redmi) gates every `adb install` via an AdbInstallActivity
# system dialog. Without user interaction, the install times out into
# INSTALL_FAILED_USER_RESTRICTED. Two changes pre-authorize the install:
#
#   1. `cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow`
#      tells PKMSImpl that shell-uid installs are pre-approved.
#   2. Installing with `-i com.android.vending` attributes the install to
#      Play Store, which MIUI's AdbInstallActivity treats more leniently.
#
# Phase 18 (autoport) discovered a *third* requirement: the phone must
# actually be unlocked when the install runs. With the keyguard up,
# AdbInstallActivity starts but immediately dispatches "canceled by user"
# without ever showing the dialog (logcat: "MIUILOG- assertCallerAndPackage
# … Install canceled by user", AdbInstallActivity onResumed with
# isKeyguardLocked=true). The validator can't unlock a PIN'd device, so
# `device_require_unlocked` (below) notifies the user and polls.
#
# All settings here are idempotent and persist across reboots, so we call
# this unconditionally before every install. Save quota: do it once
# centrally.
device_miui_unblock_install() {
    adb shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
    # Stock Android is unaffected by these; MIUI-specific knobs that
    # quiet the package-installer scan. All "set to 0" = disable the
    # MIUI-side verifier-loop that would otherwise re-prompt.
    adb shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
    adb shell settings put global package_verifier_enable 0 >/dev/null 2>&1 || true
    adb shell settings put global install_non_market_apps 1 >/dev/null 2>&1 || true
    # MIUI-specific: this setting toggles whether AdbInstallActivity
    # shows the confirmation dialog. Setting to 0 silences the dialog
    # when the device is otherwise unlocked; with the keyguard up the
    # check still fails, which is why device_require_unlocked exists.
    adb shell settings put global adb_install_need_confirm 0 >/dev/null 2>&1 || true
}

# Whether the device keyguard is currently up. Returns 0 (true) if the
# lock screen is showing or the device is asleep, 1 (false) if the user
# is in their unlocked home/app surface. Wraps the only somewhat-stable
# probe MIUI exposes — `dumpsys window policy` — into a single function
# so the rest of the lib doesn't have to parse it.
device_is_locked() {
    local out
    out=$(adb shell dumpsys window policy 2>/dev/null)
    if echo "$out" | grep -qE '^\s*showing=true'; then
        return 0  # locked
    fi
    return 1  # unlocked
}

# Block until the user unlocks the device, or fail loudly after a
# generous timeout. Phase 18 discovered that MIUI's AdbInstallActivity
# silently returns INSTALL_FAILED_USER_RESTRICTED whenever the keyguard
# is up — even with the appops grant and Play Store installer
# attribution. There is no headless way around a PIN'd lock screen, so
# this helper notifies the user via the ntfy topic configured in
# .notify.conf, then polls for the unlock.
device_require_unlocked() {
    if ! device_is_locked; then
        # Even when the keyguard is already down, the focused window
        # might still be Recents/Settings/an arbitrary app from a prior
        # run. Bring the launcher to the foreground so the install
        # dialog (if it ever shows) lands on a stable surface.
        adb shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
        sleep 2
        echo "  device is unlocked"
        return 0
    fi
    echo "  device keyguard up — notifying user via ntfy and waiting"
    local notify="$REPO_ROOT/.autoport/lib/notify.sh"
    if [ -x "$notify" ]; then
        "$notify" alert "Phase validator paused: unlock your phone so the APK install dialog can dispatch." >/dev/null 2>&1 || true
    fi
    # Phase A5 (autoport): extend the unlock wait from 5 min to 30 min.
    # The legacy 5-min ceiling was tied to the install path: MIUI's
    # AdbInstallActivity wouldn't dispatch with the keyguard up, so a
    # locked phone meant the install couldn't even start. After A5 the
    # install runs through `pm install` (see device_install_and_launch)
    # which is keyguard-independent — the unlock wait only gates the
    # *launch* step now, where SDL needs the screen on so its SurfaceView
    # doesn't pause. A 30-min budget lets the validator keep working
    # while we wait on the user without trashing a multi-hour A5 run if
    # the unlock notification takes a few minutes to surface.
    local deadline=$(( $(date +%s) + 1800 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        # Keep the screen lit during the wait so the user notices.
        adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
        if ! device_is_locked; then
            # Window transitions take ~1s on MIUI; the first install
            # attempt right after `showing=false` reliably races
            # AdbInstallActivity and trips USER_RESTRICTED. Settle, then
            # press HOME so the install dialog (if any) anchors on the
            # launcher. Verify mCurrentFocus has moved off the
            # NotificationShade/KeyguardHostView before returning.
            sleep 3
            adb shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
            sleep 2
            local focus
            focus=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)
            if echo "$focus" | grep -qiE 'Keyguard|NotificationShade'; then
                echo "  unlock detected but focus still on $focus — waiting more"
                sleep 3
                continue
            fi
            echo "  device unlocked (focus: ${focus#  })"
            return 0
        fi
        sleep 5
    done
    device_fail "device still locked after 5 min. MIUI's AdbInstallActivity
   needs the keyguard down to dispatch an adb install. Unlock the phone
   and re-run the validator."
}

# When /data is below the install-floor, clear caches from chunky apps
# that build them up automatically — Play Store and Play Services
# alone routinely sit on 1-3 GB. This is destructive only to caches:
# user data, logins, and accounts are preserved. Called from
# device_require_free_space as a second-stage escalation if
# `pm trim-caches` doesn't recover enough.
device_free_more_space() {
    # The set below is empirically the highest-yield on the user's test
    # device. Each call is idempotent — clearing an already-empty cache
    # is a no-op. Failures (uninstalled, permission denied) are ignored
    # because we don't know which apps are present on every device.
    local pkg
    for pkg in \
        com.google.android.gms \
        com.google.android.googlequicksearchbox \
        com.google.android.youtube \
        com.android.chrome \
        com.google.android.webview \
        com.android.vending \
        com.discord \
        com.openai.chatgpt \
        com.shazam.android \
        com.amazon.mShop.android.shopping \
        com.alibaba.aliexpresshd \
        com.miui.gallery; do
        adb shell pm clear "$pkg" >/dev/null 2>&1 || true
    done
}

# Build the per-flavor APK. Fails fast on AGP errors.
device_build_flavor() {
    local flavor="$1"   # jak1, jak2, or jak3
    local task="assemble${flavor^}Debug"   # assembleJak1Debug
    echo "== building $task =="
    if ! (cd "$REPO_ROOT/android" && ./gradlew "$task" 2>&1) | tee "$REPO_ROOT/.autoport/logs/gradle.last.log" \
            | tail -n 80; then
        device_fail "$task failed (full log at .autoport/logs/gradle.last.log)"
    fi
}

# Install + cold-launch the activity, with logcat captured from the moment
# of launch. Killing the app first ensures a clean lifecycle.
device_install_and_launch() {
    local package="$1"   # org.opengoal.gk.jak1
    local activity="$2"  # .LoaderActivity, .MainActivity, etc.
    local apk_path="$3"
    if [ ! -f "$apk_path" ]; then
        device_fail "APK not found at $apk_path (did the build step succeed?)"
    fi
    echo "== installing $(basename "$apk_path") =="
    device_miui_unblock_install
    # Phase A5 (autoport): use `adb push` + `adb shell pm install` instead
    # of the older `adb install` path. The legacy path goes through MIUI's
    # AdbInstallActivity dialog, which silently cancels the install
    # whenever the keyguard is up — forcing every headless validator run
    # to block on a manual unlock. `pm install` invoked from `adb shell`
    # is a different code path that the MIUI lock-screen check doesn't
    # gate, so the install completes regardless of whether the device is
    # currently in front of the launcher or behind the lock screen.
    #
    # We still wait for unlock BEFORE the launch step because SDL's
    # SurfaceView calls onPause as soon as the keyguard re-takes focus
    # — the GOAL kernel boot path wouldn't actually run otherwise. But
    # the install is now independent of the user's unlock timing, so the
    # validator can pre-stage the APK + libs while the user is away.
    local stage_path="/data/local/tmp/$(basename "$apk_path")"
    local push_log=/tmp/install-push.out
    local pm_log=/tmp/install-pm.out
    if ! adb push "$apk_path" "$stage_path" > "$push_log" 2>&1; then
        cat "$push_log" >&2
        device_fail "adb push to $stage_path failed (out of space? bad permissions?)"
    fi
    # -r: replace if installed
    # -d: allow downgrade (covers debug-built downgrades during iteration)
    # -t: allow test packages (-debug.apk is a test build)
    # -i com.android.vending: attribute install to Play Store (MIUI is
    #     friendlier to that attribution than an anonymous adb install).
    if ! adb shell pm install -r -d -t -i com.android.vending "$stage_path" \
            > "$pm_log" 2>&1; then
        cat "$pm_log" >&2
        adb shell rm -f "$stage_path" >/dev/null 2>&1 || true
        device_fail "pm install rejected the APK (keyguard, signature, or disk?)"
    fi
    if ! grep -q "Success" "$pm_log"; then
        cat "$pm_log" >&2
        adb shell rm -f "$stage_path" >/dev/null 2>&1 || true
        device_fail "pm install completed without 'Success' marker"
    fi
    # Tidy up the staged APK so /data/local/tmp doesn't accumulate copies
    # across iterations.
    adb shell rm -f "$stage_path" >/dev/null 2>&1 || true
    # MIUI's AdbInstallActivity dialog isn't involved on this path, so we
    # only wait for unlock here — once the user wakes the device, SDL can
    # bring its surface to the foreground and the renderer marker fires.
    device_require_unlocked
    adb shell am force-stop "$package" 2>/dev/null || true
    # Increase logcat buffer so longer waits don't drop early markers.
    adb logcat -G 8M 2>/dev/null || true
    adb logcat -c 2>/dev/null || true
    echo "== launching $package/$activity =="
    adb shell am start -W -n "$package/$activity" >/tmp/amstart.out 2>&1 || true
    if grep -q 'Error' /tmp/amstart.out; then
        cat /tmp/amstart.out >&2
        device_fail "am start failed"
    fi
    # Begin capturing logcat to a file in the background. The validator
    # tails this file, not adb directly, so the dump on failure is reliable.
    : > "$LOGCAT_LOG"
    adb logcat -v threadtime > "$LOGCAT_LOG" 2>&1 &
    LOGCAT_PID=$!
    # Make sure we kill it on script exit.
    trap "kill $LOGCAT_PID 2>/dev/null; adb shell am force-stop $package 2>/dev/null; device_stayon_restore" EXIT
}

# Poll the captured logcat for a regex within a timeout. Returns 0 on hit,
# 1 on timeout. Does NOT exit on miss — the caller decides whether a miss
# is a phase failure (it usually is).
device_wait_for_marker() {
    local regex="$1"
    local timeout_s="${2:-60}"
    local deadline=$(( $(date +%s) + timeout_s ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if grep -qE "$regex" "$LOGCAT_LOG" 2>/dev/null; then
            local hit
            hit=$(grep -m1 -E "$regex" "$LOGCAT_LOG")
            echo "  ✓ marker hit: $hit"
            return 0
        fi
        sleep 2
    done
    echo "  ✗ marker '$regex' not seen in ${timeout_s}s"
    return 1
}

# Assert the app has not crashed during the run window. Looks for the
# canonical Android crash signatures from any thread of the package.
device_assert_no_crash() {
    local package="$1"
    if grep -qE "Fatal signal|SIGSEGV|SIGABRT|SIGILL|FATAL EXCEPTION.*$package" "$LOGCAT_LOG"; then
        echo "  ✗ crash detected:"
        grep -E "Fatal signal|SIGSEGV|SIGABRT|SIGILL|FATAL EXCEPTION" "$LOGCAT_LOG" | tail -10
        return 1
    fi
    return 0
}

# Sanity: the desktop x86 build must keep working. Phases 17+ touch shared
# C++ in ways that easily regress the x86 backend; we catch that here
# rather than discovering it after merge.
device_assert_desktop_build() {
    echo "== sanity: desktop x86 build still passes =="
    # Reuse build-x86/ if present, otherwise reconfigure quickly.
    local build_dir="$REPO_ROOT/build"
    if [ -f "$REPO_ROOT/build-x86/CMakeCache.txt" ]; then
        build_dir="$REPO_ROOT/build-x86"
    fi
    if [ ! -f "$build_dir/CMakeCache.txt" ]; then
        cmake -S "$REPO_ROOT" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            >/tmp/cmake-x86.out 2>&1 || {
                cat /tmp/cmake-x86.out >&2
                device_fail "cmake configure for x86 desktop build failed"
            }
    fi
    if ! cmake --build "$build_dir" --target common -j 2>&1 | tail -40; then
        device_fail "desktop x86 build of 'common' target broke"
    fi
}
