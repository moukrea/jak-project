#!/usr/bin/env bash
# rhud4_build_deploy.sh — ROUND 4 GOAL-only rebuild + redeploy.
# Only goal_src/jak1/pc/hud-classes-pc.gc changed (cell-body fast-merc fix), so libgk /
# asset-bundle / APK are UNCHANGED (already == HEAD on device per deploy_verify). Just:
#   1. rebuild the consistent arm64 CGO/DGO set (28) with the fix
#   2. push it to files/iso_data/jak1 (sha-verified, keeps .extracted_v1 — no re-extract)
#   3. deploy_verify_assets + deploy_verify (device provably runs the fresh set)
#   4. boot + attract render gate (the fix must not crash)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hud-jak1; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[rhud4-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "arm64 build failed (GOAL compile error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. push consistent arm64 CGO/DGO to device"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -4 || die "CGO push failed"

say "3. deploy_verify (libgk) + deploy_verify_assets (CGO freshness)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify (libgk) failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify_assets failed"

say "4. boot + attract render gate (fix must not crash)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/round4/rhud4-boot-logcat.log"; mkdir -p "$OUT/round4"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'recharged-hud|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; echo "  attract rendering"; break; }
  sleep 3
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_attract=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach attract (crash or hang)"
echo "  recharged loader lines: $(grep -ac 'recharged-hud' "$LOG" 2>/dev/null || echo 0)"
echo "[rhud4-build] DONE — cell-fix CGOs on device, boots, deploy_verify PASS."
