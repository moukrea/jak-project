#!/usr/bin/env bash
# gdfix_deploy.sh — deploy the Gdynamic-fix render-scale controller rewrite.
# GOAL-only change (pckernel-common.gc) -> rebuild arm64 CGOs only; libgk UNCHANGED
# from the on-device build, so this is a CGO-only CONSISTENT push on a fixed libgk
# (the established practice; see gres_refine_deploy.sh). Pushes the 28 consistent
# arm64 CGO/DGO from out/jak1-arm64-full/iso to files/cgo/jak1, sha256-verifies
# each, runs deploy_verify (libgk build==APK==device chain), then boots to the attract.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
CGO_SRC=out/jak1-arm64-full/iso
OUT=.autoport/reports/Gdynamic-fix; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gdfix-deploy FAIL] $*" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || die "device $S not attached"
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
[ -d "$CGO_SRC" ] || die "consistent CGO set missing: $CGO_SRC (run build_arm64_full_consistent.sh first)"
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
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -8 || die "deploy_verify FAILED"

echo "== 3. boot to attract =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gdfix-boot-logcat.log"; : > "$LOG"
# render liveness: this build emits per-frame A42-TFTREE/A42-TFGL markers during the
# attract flythrough (older builds used A35-RENDER frame=NN); accept either.
( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I '*:S' \
   | grep --line-buffered -aE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=|link finish: logo|\[dyn-rs\]|PC Settings|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
LCP=$!
# kill the background logcat on ANY exit (incl. die), so no orphan survives
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 150 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  # count render-frame markers; >=20 = the attract is actively rendering
  rf=$(grep -acE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 20 ] 2>/dev/null && { ok=1; echo "  attract rendering ($rf render-frame markers)"; break; }
  sleep 3
done
rf=$(grep -acE 'A42-TFTREE|A42-TFGL|A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
FOCUS=$(adb shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  boot render-markers=$rf reached_attract=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not in foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach attract (render-markers=$rf)"
echo "[gdfix-deploy] DONE — device booted to attract on the fresh consistent CGO set. Ready for owner play-test (Options -> Graphics -> Dynamic Render Scale)."
