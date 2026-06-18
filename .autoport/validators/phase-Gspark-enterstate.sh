#!/usr/bin/env bash
# Validator — Gspark-enterstate: a FRESH, fully-consistent CURRENT-source 28-file
# CGO set must boot PAST frame 180 on the real device (the frame-180 enter-state
# null-enter SIGILL is gone). Objective: a real on-device run; force-restores the
# known-good f1c set afterward so the phone is always left usable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gspark-enterstate
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SRC=out/jak1-arm64-full/iso
mkdir -p "$OUT"

restore(){ bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; }
fail(){ echo "[GSPARK FAIL] $*" >&2; restore; exit 1; }

# 0. device reachable + CE-unlocked
$ADB -s $S get-state >/dev/null 2>&1 || fail "device $S not attached"
$ADB -s $S shell run-as $PKG ls files >/dev/null 2>&1 || fail "run-as fails (device CE-locked) — owner must unlock"

# 1. ANTI-STUB: a real fix must have changed goal_src/ or game/ since the last
#    [autoport/supervisor] commit (the phase anchor). No code change => false green.
ANCHOR=$(git log --grep='autoport/supervisor' -1 --format=%H 2>/dev/null || echo "")
if [ -n "$ANCHOR" ]; then
  CHANGED=$(git diff --name-only "$ANCHOR" HEAD -- goal_src/ game/ 2>/dev/null | wc -l)
  UNCOMMITTED=$(git status --porcelain -- goal_src/ game/ 2>/dev/null | wc -l)
  [ "$CHANGED" -gt 0 ] || [ "$UNCOMMITTED" -gt 0 ] || fail "no goal_src/game code change since anchor $ANCHOR — refusing stub pass"
fi

# 2. Build a fresh consistent CURRENT-source arm64 set (all 28) + restore x86 oracle.
echo "[GSPARK] building consistent arm64 set..."
bash .autoport/build_arm64_full_consistent.sh > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log" >&2; fail "consistent build failed"; }
[ "$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l)" -eq 28 ] || fail "staged set != 28 files"

# 3. If libgk changed vs device, reinstall the APK (nativeLibraryDir is read-only).
#    Always rebuild libgk so the APK is fresh; reinstall is cheap insurance.
echo "[GSPARK] building libgk + APK..."
bash .autoport/lib/d3_build.sh > "$OUT/libgk.log" 2>&1 || fail "libgk build failed"
cp -f build-android/lib/arm64-v8a/libgk.so android/app/src/main/jniLibs/arm64-v8a/libgk.so 2>/dev/null || true
( cd android && ./gradlew :app:assembleJak1Debug -q ) > "$OUT/gradle.log" 2>&1 || fail "gradle assemble failed"
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
$ADB -s $S push "$APK" /data/local/tmp/gspark.apk >/dev/null 2>&1 || fail "apk push failed"
$ADB -s $S shell pm install -r -d -t -i com.android.vending /data/local/tmp/gspark.apk 2>&1 | grep -qi Success || fail "apk install failed"
$ADB -s $S shell rm -f /data/local/tmp/gspark.apk >/dev/null 2>&1

# 4. Push the fresh consistent CGO set to the runtime (do NOT wipe .extracted_v1).
echo "[GSPARK] pushing 28 CGOs..."
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  n=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || fail "push $n failed"
  $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$n" "files/iso_data/jak1/$n" || fail "cp $n failed"
  $ADB -s $S shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/iso_data/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || fail "on-device sha mismatch for $n"
done

# 5. Run + capture well past frame 180.
$ADB -s $S logcat -c 2>/dev/null
$ADB -s $S shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1
sleep 55
$ADB -s $S exec-out screencap -p > "$OUT/boot.png" 2>/dev/null || true
$ADB -s $S logcat -d 2>/dev/null > "$OUT/run-logcat.txt"
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -oE 'mCurrentFocus=Window\{[^}]*\}' | head -1)
PIDV=$($ADB -s $S shell pidof $PKG 2>/dev/null || echo GONE)

# 6. Assertions.
SIG4=$(grep -acE 'GK-DIAG sig=4|signal 11 \(' "$OUT/run-logcat.txt" || true)
FRAME=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$OUT/run-logcat.txt" | grep -oE '[0-9]+' | sort -n | tail -1)
FRAME=${FRAME:-0}
echo "[GSPARK] frame=$FRAME sig4=$SIG4 pid=$PIDV focus=$FOCUS"

# 7. ALWAYS restore the known-good set so the device stays usable.
restore

# 8. Verdict.
echo "$FOCUS" | grep -q "$PKG" || fail "app NOT foreground at end (focus=$FOCUS) — crashed/backgrounded"
[ "$SIG4" -eq 0 ] || fail "saw $SIG4 sig=4/sig11 in the run — still crashing"
[ "$FRAME" -ge 600 ] || fail "only reached frame $FRAME (<600) — did not boot well past frame 180"
echo "[GSPARK PASS] current-source CGOs boot past frame 180 (frame=$FRAME, foreground, 0 sig=4). Known-good restored."
exit 0
