#!/usr/bin/env bash
# Gcollision-replay-diff: deploy HEAD libgk (collision dump hook) + a chosen arm64
# CGO set, replay the OWNER gameplay demo on the device with a per-logic-frame
# collision trace, pull it. Restore-on-failure.
#   arg1 = trace tag           (e.g. arm_g  or  arm_g_after)
#   arg2 = replay seconds      (default 360)
#   arg3 = CGO source dir      (default out/jak1-arm64-full/iso  = FCVTZS-fixed set)
#   arg4 = skip rebuild+install (1 = just push CGO+demo and replay; default 0)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
DEMO=.autoport/demos/collision-glitch-gameplay.inputs
D=.autoport/reports/Gcollision-replay-diff
TAG="${1:-arm_g}"; SECS="${2:-360}"; CGO_SRC="${3:-out/jak1-arm64-full/iso}"; SKIP="${4:-0}"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[dr FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

adb get-state >/dev/null 2>&1 || die "device not attached"
[ -f "$DEMO" ] || die "demo missing: $DEMO"
[ -d "$CGO_SRC" ] || die "CGO set missing: $CGO_SRC"

if [ "$SKIP" != "1" ]; then
  echo "== 1. cmake build libgk (native; gradle skips it on C++ edits) =="
  cmake --build build-android --target gk -j"$(nproc)" > /tmp/cmake_gk.log 2>&1 || { tail -20 /tmp/cmake_gk.log; die "cmake gk build failed"; }
  echo "== 2. assemble SLIM APK (-PslimIso=true; device keeps its files/iso_data; ~100MB fits 1.6GB free) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true ) > /tmp/gradle_assemble.log 2>&1 || { tail -20 /tmp/gradle_assemble.log; die "gradle assemble failed"; }
  [ -f "$APK" ] || die "APK not produced"
  echo "  slim APK size: $(du -h "$APK" | awk '{print $1}')"
  echo "== 3. install (MIUI unblock) =="
  adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  adb shell pm trim-caches 999G 2>/dev/null || true
  adb install -r -d -t -i com.android.vending "$APK" >/tmp/apk_install.log 2>&1 || { tail -5 /tmp/apk_install.log; die "apk install failed"; }
fi

echo "== 4. push CGO set ($CGO_SRC) =="
ncgo=$(ls "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO 2>/dev/null | wc -l)
[ "$ncgo" -eq 28 ] || die "expected 28 CGO/DGO, got $ncgo"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0
for f in "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO; do
  n=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  adb push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || { echo "PUSH-FAIL $n"; fail=1; continue; }
  adb shell run-as $PKG cp "/data/local/tmp/$n" "files/iso_data/jak1/$n" || { echo "CP-FAIL $n"; fail=1; }
  adb shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "files/iso_data/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "VERIFY-FAIL $n"; fail=1; }
done
[ "$fail" -eq 0 ] || die "CGO push failed"
echo "  pushed+verified 28 CGO/DGO from $CGO_SRC"

if [ "$SKIP" != "1" ]; then
  echo "== 5. deploy_verify (build==APK==device libgk) =="
  bash .autoport/lib/deploy_verify.sh "$S" || die "deploy_verify failed"
fi

echo "== 6. push gameplay demo =="
adb push "$DEMO" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1 || die "demo push failed"
adb shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs || die "demo cp failed"
adb shell run-as $PKG rm -f "files/${TAG}.statedump.txt" >/dev/null 2>&1 || true

echo "== 7. arm replay+trace, launch =="
adb shell setprop debug.opengoal.f1.warp 1
adb shell setprop debug.opengoal.pad_replay replay
adb shell setprop debug.opengoal.pad_trace "${TAG}.statedump.txt"
adb shell svc power stayon true 2>/dev/null || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/${TAG}_logcat.log; : > "$LOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'pad_replay:|ANCHOR reached|link finish:|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "== 8. replay ${SECS}s =="
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ]; do
  sleep 20
  fr=$(adb shell run-as $PKG wc -l "files/${TAG}.statedump.txt" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  foc=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -c "$PKG")
  echo "  t=$(( $(date +%s) - t0 ))s trace_frames=${fr:-0} app_focus=${foc}"
  if grep -aqE 'Fatal signal|signal [0-9]+ \(SIG' "$LOG"; then echo "  CRASH detected"; break; fi
done
kill "$LCP" 2>/dev/null || true

echo "== 9. pull trace (exec-out stream; /data near-full so no /data/local/tmp staging) =="
adb exec-out run-as $PKG cat "files/${TAG}.statedump.txt" > "$D/${TAG}.trace" 2>/dev/null
[ -s "$D/${TAG}.trace" ] || die "trace pull failed"
echo "  pulled: $(grep -c '^ci frame=' "$D/${TAG}.trace" 2>/dev/null) frames -> $D/${TAG}.trace"

echo "== 10. clear props =="
adb shell setprop debug.opengoal.pad_replay '' 2>/dev/null || true
adb shell setprop debug.opengoal.pad_trace '' 2>/dev/null || true
adb shell setprop debug.opengoal.f1.warp '' 2>/dev/null || true
echo "[dr OK] $TAG"
grep -a 'ANCHOR reached' "$LOG" | head -1
