#!/usr/bin/env bash
# Gcollision-replay-diff: deploy fresh HEAD libgk (collision dump hook) + the
# FCVTZS-fixed consistent arm64 CGO set, replay the long.inputs gameplay clip on
# the device with a per-logic-frame collision trace, pull it. Restore-on-failure.
#   arg1 = trace tag (e.g. arm_long  or  arm_long_after)
#   arg2 = replay seconds (default 320)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CGO_SRC=out/jak1-arm64-full/iso
DEMO=.autoport/reports/Ginput-replay-determinism/long.inputs
D=.autoport/reports/Gcollision-replay-diff
TAG="${1:-arm_long}"; SECS="${2:-320}"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[dr FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

adb get-state >/dev/null 2>&1 || die "device not attached"
[ -f "$DEMO" ] || die "demo missing"

echo "== 1. assemble APK (bundles the fresh libgk.so) =="
( cd android && ./gradlew assembleJak1Debug ) > /tmp/gradle_assemble.log 2>&1 || { tail -20 /tmp/gradle_assemble.log; die "gradle assemble failed"; }
[ -f "$APK" ] || die "APK not produced"

echo "== 2. install (MIUI unblock) =="
adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
adb shell pm trim-caches 999G 2>/dev/null || true
adb install -r -d -t -i com.android.vending "$APK" >/tmp/apk_install.log 2>&1 || { tail -5 /tmp/apk_install.log; die "apk install failed"; }

echo "== 3. push FCVTZS-fixed consistent CGO set (28 files) =="
[ -d "$CGO_SRC" ] || die "consistent CGO set missing"
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
echo "  pushed+verified 28 consistent CGO/DGO"

echo "== 4. deploy_verify (build==APK==device libgk) =="
bash .autoport/lib/deploy_verify.sh "$S" || die "deploy_verify failed"

echo "== 5. push demo clip as pad_demo.inputs =="
adb push "$DEMO" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1 || die "demo push failed"
adb shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs || die "demo cp failed"
adb shell run-as $PKG rm -f "files/${TAG}.statedump.txt" >/dev/null 2>&1 || true

echo "== 6. arm the replay + trace, launch =="
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

echo "== 7. let it replay ${SECS}s =="
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ]; do
  sleep 20
  fr=$(adb shell run-as $PKG wc -l "files/${TAG}.statedump.txt" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  foc=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -c "$PKG")
  echo "  t=$(( $(date +%s) - t0 ))s trace_frames=${fr:-0} app_focus=${foc}"
  if grep -aqE 'Fatal signal|signal [0-9]+ \(SIG' "$LOG"; then echo "  CRASH detected"; break; fi
done
kill "$LCP" 2>/dev/null || true

echo "== 8. pull trace =="
adb shell run-as $PKG cp "files/${TAG}.statedump.txt" /data/local/tmp/${TAG}.statedump.txt 2>/dev/null || true
adb pull /data/local/tmp/${TAG}.statedump.txt "$D/${TAG}.trace" >/dev/null 2>&1 || die "trace pull failed"
adb shell rm -f /data/local/tmp/${TAG}.statedump.txt >/dev/null 2>&1 || true
echo "  pulled: $(grep -c '^ci frame=' "$D/${TAG}.trace" 2>/dev/null) frames -> $D/${TAG}.trace"

echo "== 9. clear replay props =="
adb shell setprop debug.opengoal.pad_replay '' 2>/dev/null || true
adb shell setprop debug.opengoal.pad_trace '' 2>/dev/null || true
adb shell setprop debug.opengoal.f1.warp '' 2>/dev/null || true
echo "[dr OK] $TAG"
grep -a 'ANCHOR reached' "$LOG" | head -1
