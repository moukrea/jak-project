#!/usr/bin/env bash
# gswamp_fstore_redeploy.sh — land the Gswamp-fstore libgk fix on the device.
#
# The fix is asm-only (game/kernel/asm_funcs_arm64.s _mips2c_call_arm64: seed gpr s7
# with the GOAL offset x14-x15). It changes libgk.so but produces BYTE-IDENTICAL
# CGO/DGO (arm64 goalc output unaffected), so this is a libgk-ONLY redeploy:
#   rebuild gk -> gradle re-copies the fresh .so into jniLibs + repackages APK ->
#   reinstall (keep app data so the already-consistent CGOs persist) -> deploy_verify.
#
# Attempt 1 failed close-gate because a direct `cmake --build` rebuilt build-android/
# libgk.so (7c21f1be, has fix) but gradle was never re-run, so the APK + device kept
# the STALE pre-fix .so (eba2f8d6). This re-runs gradle so build==APK==device.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${1:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
BUILT=build-android/lib/arm64-v8a/libgk.so
JNI=android/app/src/main/jniLibs/arm64-v8a/libgk.so
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gswamp-redeploy FAIL] $*" >&2; exit 1; }

say "0. preflight: device attached + unlocked + run-as OK"
$ADB -s "$S" get-state >/dev/null 2>&1 || die "device $S not attached"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
$ADB -s "$S" shell run-as $PKG ls files/cgo/jak1/ENGINE.CGO >/dev/null 2>&1 || die "run-as fails (CE locked / not extracted)"

say "1. rebuild gk (asm fix already in tree; cmake incremental) + confirm fix bytes"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f "$BUILT" ] || die "libgk.so not built"
OBJDUMP=$(command -v aarch64-linux-gnu-objdump || echo llvm-objdump)
$OBJDUMP -d "$BUILT" 2>/dev/null | grep -A60 "<_mips2c_call_arm64>:" | grep -q "sub[[:space:]]*x11, x14, x15" \
  || die "fix bytes (sub x11,x14,x15) NOT in built libgk.so — wrong source/build"
BUILT_SHA=$(sha256sum "$BUILT" | cut -d' ' -f1)
echo "  built libgk.so sha: ${BUILT_SHA:0:32}  (has fix bytes)"

say "2. gradle assemble (copyNativeLibs re-copies fresh .so into jniLibs, repackages APK)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "3. VERIFY jniLibs + APK now carry the FRESH .so (== build)"
JNI_SHA=$(sha256sum "$JNI" | cut -d' ' -f1)
[ "$JNI_SHA" = "$BUILT_SHA" ] || die "jniLibs .so ($JNI_SHA) != build ($BUILT_SHA) — copyNativeLibs did NOT re-copy"
APK_SHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$APK_SHA" = "$BUILT_SHA" ] || die "APK-bundled .so ($APK_SHA) != build ($BUILT_SHA) — stale APK"
echo "  jniLibs==APK==build: ${BUILT_SHA:0:32}"

say "4. capture device ENGINE.CGO BEFORE reinstall (must be unchanged: libgk-only change)"
CGO_BEFORE=$($ADB -s "$S" shell run-as $PKG sha256sum files/cgo/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO before: ${CGO_BEFORE:-<none>}"

say "5. install APK (keep app data => extracted CGOs persist, loader skips re-extract)"
$ADB -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
$ADB -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
$ADB -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
$ADB -s "$S" shell run-as $PKG ls files >/dev/null 2>&1 || die "run-as broke after install"

say "6. deploy_verify (build==APK==device libgk, built-after-source)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -6 || die "deploy_verify FAILED"

say "7. boot-check: launch + confirm foreground jak1 (close-gate GATE 2b)"
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 25
FOCUS=$($ADB -s "$S" shell dumpsys window 2>/dev/null | grep -i mCurrentFocus | tr -d '\r')
echo "  focus: $FOCUS"
echo "$FOCUS" | grep -q "$PKG" || echo "  WARN: jak1 not in foreground (may still be extracting/loading)"

say "8. confirm ENGINE.CGO UNCHANGED across reinstall (consistency)"
CGO_AFTER=$($ADB -s "$S" shell run-as $PKG sha256sum files/cgo/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO after:  ${CGO_AFTER:-<none>}"
if [ -n "$CGO_BEFORE" ] && [ -n "$CGO_AFTER" ] && [ "$CGO_BEFORE" != "$CGO_AFTER" ]; then
  die "ENGINE.CGO CHANGED across reinstall ($CGO_BEFORE -> $CGO_AFTER) — CGOs re-extracted; consistency risk"
fi
echo "[gswamp-redeploy] DONE — fixed libgk deployed, deploy_verify PASS, CGOs unchanged."
