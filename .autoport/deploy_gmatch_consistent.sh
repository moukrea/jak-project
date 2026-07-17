#!/usr/bin/env bash
# deploy_gmatch_consistent.sh — deploy the CONSISTENT 3deef6bf3 current-source
# build + the frame-180 enter-slot canary, and smoke-boot it.
#
# Build = the slim APK (canary libgk: 3deef boot source + the ndi enter-slot
# content-canary) + the full consistent 3deef arm64 CGO/DGO set from
# out/jak1-arm64-full/iso (all 28, built by build_arm64_full_consistent.sh).
#
# This REPLACES the f1c boot CGOs with the consistent 3deef set. The set crashes
# at frame ~180 (ndi enter-slot zero-stomp) UNLESS the canary libgk repairs it.
# So this run is the experiment: does the canary let the consistent build boot
# past 180? On ANY smoke failure it AUTO-RESTORES the f1c known-good set so the
# device stays usable.
#
# Device serial eae4df44 ONLY. Real measurements only. Leaves the app RUNNING on
# smoke PASS so the graphics harness can drive it next.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CGO_SRC=out/jak1-arm64-full/iso
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[deploy FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
[ -f "$APK" ] || die "APK missing: $APK"
[ -d "$CGO_SRC" ] || die "consistent CGO set missing: $CGO_SRC"
ncgo=$(ls "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO 2>/dev/null | wc -l)
[ "$ncgo" -eq 28 ] || die "expected 28 CGO/DGO in $CGO_SRC, got $ncgo"

echo "== 1. MIUI install-unblock + install canary libgk slim APK =="
adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
adb shell pm trim-caches 999G 2>/dev/null || true
adb install -r -d -t -i com.android.vending "$APK" || die "apk install failed"
echo "  installed: $(adb shell dumpsys package $PKG | grep -m1 versionCode | tr -d '\r')"

echo "== 2. push the CONSISTENT 3deef arm64 CGO/DGO set (28 files) over files/cgo =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0
for f in "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO; do
  n=$(basename "$f")
  want=$(sha256sum "$f" | awk '{print $1}')
  adb push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || { echo "  PUSH-FAIL $n"; fail=1; continue; }
  adb shell run-as $PKG cp "/data/local/tmp/$n" "files/cgo/jak1/$n" || { echo "  CP-FAIL $n"; fail=1; }
  adb shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "files/cgo/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $n"; fail=1; }
done
[ "$fail" -eq 0 ] || die "consistent CGO push failed (one or more files)"
echo "  pushed + sha256-verified all 28 consistent 3deef files"

echo "== 3. smoke boot: launch + watch 120s for frame-180 SIGILL vs reaching title =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG=/tmp/gmatch-consistent-logcat.log; : > "$LOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'A35-RENDER frame=|GMATCH-NDI-DIAG|GMATCH-NDI-ENTER-STOMP|GCINE3-DEACT-STOMP|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG' > "$LOG" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0; crash=0
while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then crash=1; break; fi
  fr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); fr=${fr:-0}
  [ "$fr" -ge 900 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
kill ${LCP:-0} 2>/dev/null || true
maxfr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); maxfr=${maxfr:-0}
canary=$(grep -ac 'GMATCH-NDI-ENTER-STOMP' "$LOG" 2>/dev/null); canary=${canary:-0}
echo "  smoke: crash=$crash maxframe=$maxfr reached_render900=$ok canary_repairs_logged=$canary"
grep -aE 'GMATCH-NDI-ENTER-STOMP|GK-DIAG sig=' "$LOG" 2>/dev/null | head -4
[ "$crash" = 1 ] && die "SMOKE CRASH at maxframe=$maxfr (canary insufficient or wrong addr; canary_logged=$canary)"
[ "$ok" = 1 ] || die "smoke: did not reach render>=900 in 120s (maxframe=$maxfr)"
echo "[deploy] SMOKE PASS: consistent 3deef build booted past frame 180 to render=$maxfr (canary repairs=$canary)."
echo "[deploy] device left RUNNING — next: bash .autoport/lib/verify_device_graphics.sh"
