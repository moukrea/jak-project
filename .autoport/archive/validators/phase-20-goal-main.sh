#!/usr/bin/env bash
# Phase 19 validator: goal_main is wired into gk_sdl_main and the GOAL
# kernel boots far enough to load KERNEL.CGO + start the dispatcher.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 20 validator (kernel boot via goal_main, on-device) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "APK missing"

device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Loader → Main transition. Tight timeout because the sentinel is
# expected to be present from phase 17 — we want the fast path.
if ! device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 60; then
    device_fail "iso_data missing — phase 17 sentinel got wiped? Try uninstall + reinstall."
fi

# Argv must reach goal_main with the right flags.
if ! device_wait_for_marker 'goal_main: argv=\[gk,--game,jak1,--portable,-fakeiso,-iso-data,' 30; then
    device_fail "goal_main never received the expected argv"
fi

# kheap initialized.
if ! device_wait_for_marker 'kheap_alloc: OK' 30; then
    device_fail "kheap_alloc never reported success — heap setup failed"
fi

# KERNEL.CGO loaded — non-zero byte count.
if ! device_wait_for_marker 'KERNEL\.CGO: loaded [1-9][0-9]+ bytes' 60; then
    device_fail "KERNEL.CGO load marker absent or zero bytes (data_root wrong? CGO unreadable?)"
fi

# Dispatcher running.
if ! device_wait_for_marker 'gkernel: dispatcher started' 30; then
    device_fail "gkernel dispatcher never started — kernel boot stalled mid-init"
fi

# No fatal crash in the boot window.
if ! device_assert_no_crash "$PACKAGE"; then
    # Pull tombstones for forensic context if any.
    echo "--- recent tombstones (if any) ---"
    adb shell 'ls -la /data/tombstones 2>/dev/null | tail -5' || true
    device_fail "crash detected during kernel boot — see logcat above + tombstones"
fi

# Optional but useful: confirm goal_main has NOT returned yet. If it
# returned, that means we exited the runtime — broken.
if grep -q 'goal_main: returned' "$LOGCAT_LOG"; then
    rc=$(grep -m1 'goal_main: returned' "$LOGCAT_LOG" | grep -oE 'returned -?[0-9]+')
    device_fail "goal_main returned early ($rc) — kernel should stay alive"
fi

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 20 validator PASSED =="
echo "   GOAL kernel boots: goal_main → kheap → KERNEL.CGO → gkernel dispatcher."
echo "   No crash. goal_main still running. Desktop build still green."
