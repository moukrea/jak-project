#!/usr/bin/env bash
# Phase D4 validator — device-first verification that real jak1 kmachine
# runs in the APK on the user's Redmi Note 9 Pro.
#
# Authored by the supervisor 2026-05-21 after the on-device run with
# claude's D3 abort-stub confirmed exactly where the boot path breaks.
# D4 is the first phase whose validator REQUIRES installing on device
# and capturing logcat. No structural-only short-circuits.
#
# 18 checks. The device steps run via .autoport/lib/device-validate.sh
# helpers (handles MIUI install dance + lock-screen waits).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
D4_RUN_SCRIPT=".autoport/lib/d4_run.sh"
BOOT_LOG=".autoport/reports/D4-boot.log"
STATUS_TXT=".autoport/reports/D4-status.txt"
REPORT_MD=".autoport/reports/D4-launch.md"
STUB_FILE="android/android_jak1_kernel_stubs.cpp"
CMAKE_FILE="android/CMakeLists.txt"
KMACHINE_CPP="game/kernel/jak1/kmachine.cpp"
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1_COMMIT=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"

# device-validate.sh expects LOGCAT_LOG to be the file path where logcat
# is streamed. We point it at BOOT_LOG so the captured run lives in
# .autoport/reports/.
export LOGCAT_LOG="$BOOT_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase D4 validator (device-first) =="

# ---- 1. The D3 abort-stub must be gone ----
[ ! -e "$STUB_FILE" ] || fail "$STUB_FILE still present (D4 must delete it)"
ok "D3 abort-stub deleted"

# ---- 2. CMakeLists no longer references the stub + adds kmachine.cpp ----
grep -qE "android_jak1_kernel_stubs" "$CMAKE_FILE" \
    && fail "$CMAKE_FILE still references android_jak1_kernel_stubs (D4 must drop it)"
grep -qE "kernel/jak1/kmachine\.cpp" "$CMAKE_FILE" \
    || fail "$CMAKE_FILE missing game/kernel/jak1/kmachine.cpp in the kernel archive"
ok "CMakeLists wires kmachine.cpp"

# ---- 3. d4_run.sh exists ----
[ -x "$D4_RUN_SCRIPT" ] || fail "$D4_RUN_SCRIPT missing or not executable"
ok "d4_run.sh present"

# ---- 4-6. Build + install via d4_run.sh ----
device_require_attached
echo "  running d4_run.sh (build → install → launch → capture)..."
"$D4_RUN_SCRIPT" > /tmp/d4-run.log 2>&1 \
    || { tail -50 /tmp/d4-run.log; fail "d4_run.sh failed; see /tmp/d4-run.log"; }
ok "d4_run.sh completed (build + install + launch + capture)"

[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing (d4_run.sh should have captured logcat)"
[ -f "$STATUS_TXT" ] || fail "$STATUS_TXT missing"
[ -f "$REPORT_MD" ] || fail "$REPORT_MD missing"
ok "all D4 reports produced"

# ---- 7. No immediate crash (process must have lived ≥ 5 s) ----
LAUNCH_OK=$(grep -c "MainActivity onCreate done" "$BOOT_LOG" || true)
[ "$LAUNCH_OK" -ge 1 ] || fail "MainActivity onCreate never logged — app didn't even start"
ok "MainActivity onCreate fired"

# ---- 8. The D3 abort message must NOT be in logcat ----
if grep -qE "jak1::InitMachine ABORT" "$BOOT_LOG"; then
    echo "Found D3 abort message in logcat:"
    grep -nE "jak1::InitMachine ABORT" "$BOOT_LOG" | head -3
    fail "D3 abort-stub still firing — kmachine isn't actually wired"
fi
ok "no D3 abort message in logcat"

# ---- 9. No fatal signals in the capture window for our process ----
if grep -qE "F DEBUG +:.*signal (6|11|4|7) \((SIGABRT|SIGSEGV|SIGILL|SIGBUS)\)" "$BOOT_LOG"; then
    echo "Native fatal in logcat:"
    grep -nE "F DEBUG +:.*signal" "$BOOT_LOG" | head -3
    grep -nE "F DEBUG +:.*Abort message" "$BOOT_LOG" | head -3
    fail "process crashed with a native fatal signal during D4 capture"
fi
ok "no SIGABRT/SIGSEGV/SIGILL/SIGBUS in capture window"

# ---- 10. Render loop entered ----
grep -qE "android_renderer_run: entered" "$BOOT_LOG" \
    || fail "android_renderer_run never entered (kmachine returned without dispatching renderer?)"
ok "android_renderer_run entered"

# ---- 11. Sustained-swap heartbeat fired at least once ----
grep -qE "android_renderer: sustained swap [0-9]+" "$BOOT_LOG" \
    || fail "no 'sustained swap' heartbeat in logcat (render loop didn't iterate ≥ 60 frames)"
ok "render loop sustained ≥ 60 frames"

# ---- 12. Real upstream kmachine markers ----
HIT=0
for m in 'InitIOP OK' 'Initialized GOAL heap' 'Got DGO file header for KERNEL.CGO' \
         'link finish: gcommon' 'link finish: gkernel' 'link finish: gstate'; do
    if grep -qE "$m" "$BOOT_LOG"; then HIT=$((HIT+1)); fi
done
[ "$HIT" -ge 3 ] || fail "only $HIT/6 real upstream kmachine markers in logcat (need ≥ 3 — real kmachine isn't reaching DGO load)"
ok "$HIT/6 real upstream kmachine markers observed in logcat"

# ---- 13. No new *_stubs.cpp files since D3 ----
D3_COMMIT=$(git log --format=%H --all --grep='\[autoport/D3-android-sdl3-surface\] sustained swap loop' | head -1)
if [ -n "$D3_COMMIT" ]; then
    NEW_STUBS=$(git diff --name-only --diff-filter=A "$D3_COMMIT" HEAD | grep -E '_stubs\.cpp$' || true)
    [ -z "$NEW_STUBS" ] || fail "new *_stubs.cpp files added since D3: $NEW_STUBS"
fi
ok "no new *_stubs.cpp files since D3"

# ---- 14. No new abort() calls in source since D3 ----
if [ -n "$D3_COMMIT" ]; then
    ABORTS_ADDED=$(git diff "$D3_COMMIT" HEAD -- 'android/**.cpp' 'game/**.cpp' 2>/dev/null \
        | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
    [ "$ABORTS_ADDED" -eq 0 ] \
        || fail "abort() call(s) added since D3 ($ABORTS_ADDED additions)"
fi
ok "no new abort() calls in code since D3"

# ---- 15. Codegen still locked since A4 ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/CodeGenerator.h; do
    if [ -f "$f" ]; then
        DIFF=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF" -eq 0 ] || fail "$f changed since A4 (codegen-lock violated)"
    fi
done
ok "goalc codegen byte-identical to A4"

# ---- 16. Classifier byte-identical to A1 ----
CLF_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1"
ok "classifier byte-identical to A1"

# ---- 17. x86 CGOs untouched ----
while read -r expected_hash path; do
    [ -z "$expected_hash" ] && continue
    [[ "$path" == /* || "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected_hash" = "$actual" ] \
        || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 18. Desktop smoke still works ----
echo "  desktop gk smoke (link finish: logo)..."
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
if ! grep -q "link finish: logo$" "$SMOKE_LOG"; then
    tail -25 "$SMOKE_LOG"
    fail "desktop gk did not reach 'link finish: logo'"
fi
ok "desktop smoke test passes"

echo ""
echo "PASS: Phase D4 — real jak1 kmachine.cpp runs on device, render loop"
echo "      iterates, D3 abort eliminated, locks intact."
