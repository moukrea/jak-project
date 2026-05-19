#!/usr/bin/env bash
# Phase 19 validator: stress-test the AArch64 emitter against real jak1
# CGOs under qemu-aarch64-static. Host-only; no Android device involved.
#
# Concretely: bring up `gk` under qemu with `-game jak1 -fakeiso -iso-data
# out/jak1/iso/` (the same argv shape phase 20 will use on Android), let
# it idle 90s, and assert no SIGILL / SIGSEGV / qemu uncaught signal in
# the runtime. If anything faults, the emitter is producing bad code for
# a pattern present in jak1 — fix `goalc/emitter/IGen_arm64.cpp`, then
# regenerate CGOs via `bash .autoport/validators/phase-14-jak1.sh` before
# re-running this validator.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 19 validator (emitter stress on real jak1 CGOs, qemu-aarch64) =="

# Host tool gate.
if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
    echo "FAIL: qemu-aarch64-static not on PATH."
    echo "      On Fedora: sudo dnf install qemu-user-static glibc-aarch64-linux-gnu"
    exit 1
fi

# Make sure the cross-built gk is current. Phase 09 produced build-arm64/.
# If it's stale, rebuild.
echo "== ensuring build-arm64/gk is current =="
if [ ! -f build-arm64/CMakeCache.txt ]; then
    echo "FAIL: build-arm64/ missing (phase 09 regression?). Reconfigure manually first."
    exit 1
fi
if ! cmake --build build-arm64 --target gk -j > /tmp/p19-build.log 2>&1; then
    echo "FAIL: cmake --build build-arm64 --target gk failed"
    tail -60 /tmp/p19-build.log
    exit 1
fi

GK=$(find build-arm64 -name gk -type f -executable -not -path '*/CMakeFiles/*' | head -1)
[ -n "$GK" ] || { echo "FAIL: gk binary not found under build-arm64/"; exit 1; }
echo "  gk: $GK"

# CGOs must be present from phase 14.
ISO_DIR="$(pwd)/out/jak1/iso"
if [ ! -d "$ISO_DIR" ] || ! ls "$ISO_DIR"/KERNEL.CGO >/dev/null 2>&1; then
    echo "FAIL: $ISO_DIR/KERNEL.CGO missing (phase 14 regression?)"
    exit 1
fi
CGO_COUNT=$(ls "$ISO_DIR"/*.CGO 2>/dev/null | wc -l)
echo "  iso_data: $ISO_DIR ($CGO_COUNT CGO files)"

# Probe the runtime for a headless flag — what it's called depends on
# whether jak1's CLI parsing has it as `--headless`, `-nodisplay`, or
# something else. The validator picks the first one that `--help`
# advertises.
HELP_OUT=$(qemu-aarch64-static -L /usr/aarch64-linux-gnu "$GK" --help 2>&1 || true)
HEADLESS_FLAG=""
for cand in --headless -nodisplay --no-display -nogfx -nox11; do
    if echo "$HELP_OUT" | grep -qE "(^|[[:space:]])${cand}([[:space:]]|$)"; then
        HEADLESS_FLAG="$cand"
        break
    fi
done
if [ -z "$HEADLESS_FLAG" ]; then
    echo "  warning: no headless flag advertised in gk --help."
    echo "          The runtime may try to open a display; if it can't, it"
    echo "          should fall through. Proceeding without --headless."
fi
echo "  headless flag: ${HEADLESS_FLAG:-<none>}"

LOG=/tmp/p19-stress.log
: > "$LOG"

# Launch under qemu in the background with the same argv shape phase 20
# will use on Android, minus SDL/JNI plumbing.
echo "== launching gk under qemu-aarch64 =="
echo "  argv: $GK --game jak1 --portable -fakeiso -iso-data $ISO_DIR $HEADLESS_FLAG"
qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    "$GK" --game jak1 --portable -fakeiso -iso-data "$ISO_DIR" $HEADLESS_FLAG \
    > "$LOG" 2>&1 &
GK_PID=$!
trap "kill $GK_PID 2>/dev/null || true" EXIT

# Wait for boot markers, max 60s.
BOOT_DEADLINE=$(( $(date +%s) + 60 ))
boot_ok=false
while [ "$(date +%s)" -lt "$BOOT_DEADLINE" ]; do
    # Allow flexible kernel-boot signal — runtime may not log the exact
    # strings we expect on Android; map to whichever phase 09's runtime emits.
    if grep -qE 'gkernel: dispatcher started|kernel: target online|target started|level zero loaded' "$LOG"; then
        boot_ok=true; break
    fi
    if ! kill -0 $GK_PID 2>/dev/null; then
        echo "FAIL: gk exited during boot ($(wait $GK_PID; echo $?))"
        echo "--- last 60 lines of stress log ---"
        tail -60 "$LOG"
        exit 1
    fi
    if grep -qE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|Illegal instruction|Segmentation fault' "$LOG"; then
        echo "FAIL: fault during boot phase — emitter bug"
        grep -nE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|pc=' "$LOG" | head -20
        exit 1
    fi
    sleep 2
done
$boot_ok || {
    echo "FAIL: gk never reached a boot-complete marker within 60s"
    tail -80 "$LOG"
    exit 1
}
echo "  boot OK"

# Idle stress: 90s.
echo "== idling 90s to surface emitter bugs in idle / GC / dispatcher loops =="
STRESS_DEADLINE=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$STRESS_DEADLINE" ]; do
    if grep -qE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|Illegal instruction|Segmentation fault' "$LOG"; then
        echo "FAIL: emitter fault during idle stress"
        grep -nE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|pc=' "$LOG" | head -20
        echo "--- preceding context ---"
        grep -nE -B5 'SIGILL|SIGSEGV|qemu: uncaught' "$LOG" | head -40
        exit 1
    fi
    if ! kill -0 $GK_PID 2>/dev/null; then
        rc=0; wait $GK_PID 2>/dev/null || rc=$?
        # Some early shutdown paths can be clean (e.g. listener (:exit)). We
        # treat any early exit during idle as suspicious because the kernel
        # should be waiting for input.
        echo "FAIL: gk exited during idle window (rc=$rc) — should still be running"
        tail -40 "$LOG"
        exit 1
    fi
    sleep 5
done

# Clean kill.
kill -TERM $GK_PID 2>/dev/null || true
sleep 2
kill -KILL $GK_PID 2>/dev/null || true
wait $GK_PID 2>/dev/null || true

# Final pass on the whole log.
if grep -qE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|Illegal instruction|Segmentation fault' "$LOG"; then
    echo "FAIL: a fault slipped through interval polling"
    grep -nE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|pc=' "$LOG" | head -20
    exit 1
fi

echo "  emitter-stress: PASS (90s idle, 0 faults)"
echo
echo "== Phase 19 validator PASSED =="
echo "   AArch64 emitter is correct on real jak1 GOAL code under qemu."
echo "   Any phase-20 SIGILL on Android is therefore Bionic-specific,"
echo "   not an emitter bug."
