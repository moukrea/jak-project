#!/usr/bin/env bash
# gres_refine_deploy.sh — deploy the Gres-picker REFINEMENT ^aspect-adaptive = NATIVE.
# GOAL-only change (progress-pc.gc) -> rebuild arm64 CGOs only; libgk unchanged from
# the on-device 90a7a1dce build, so this is a CGO-only consistent push on a fixed
# libgk (the established practice for the prior 3 Gres iterations). Pushes the 28
# consistent arm64 CGO/DGO from out/jak1-arm64-full/iso to files/cgo/jak1, sha256-
# verifies each, runs deploy_verify, then boots to the attract.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
CGO_SRC=out/jak1-arm64-full/iso
OUT=.autoport/reports/Gres-picker; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gres-deploy FAIL] $*" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
[ -d "$CGO_SRC" ] || die "consistent CGO set missing: $CGO_SRC"
ncgo=$(ls "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO 2>/dev/null | wc -l)
[ "$ncgo" -eq 28 ] || die "expected 28 CGO/DGO in $CGO_SRC, got $ncgo"

echo "== 1. push the CONSISTENT arm64 CGO/DGO set (28 files) -> files/cgo/jak1 =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0
for f in "$CGO_SRC"/*.CGO "$CGO_SRC"/*.DGO; do
  n=$(basename "$f")
  want=$(sha256sum "$f" | awk '{print $1}')
  adb push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || { echo "  PUSH-FAIL $n"; fail=1; continue; }
  adb shell run-as $PKG cp "/data/local/tmp/$n" "files/cgo/jak1/$n" || { echo "  CP-FAIL $n"; fail=1; }
  adb shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "files/cgo/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $n want=$want got=$got"; fail=1; }
done
[ "$fail" -eq 0 ] || die "consistent CGO push failed (one or more files)"
echo "  pushed + sha256-verified all 28 consistent arm64 files"

echo "== 2. deploy_verify (libgk build==APK==device chain) =="
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -6 || die "deploy_verify FAILED"

echo "== 3. boot to attract =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG="$OUT/refine-boot-logcat.log"; : > "$LOG"
( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish: logo|Setting (borderless|window)|PC Settings|build-resolution|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 150 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  fr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); fr=${fr:-0}
  [ "$fr" -ge 1500 ] 2>/dev/null && { ok=1; echo "  attract rendering (frame $fr)"; break; }
  sleep 3
done
kill ${LCP:-0} 2>/dev/null || true
maxfr=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); maxfr=${maxfr:-0}
echo "  boot maxframe=$maxfr reached_attract=$ok focus=$(adb shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')"
[ "$ok" = 1 ] || die "did not reach attract (maxframe=$maxfr)"
echo "[gres-deploy] DONE — device booted to attract, ready for menu navigation."
