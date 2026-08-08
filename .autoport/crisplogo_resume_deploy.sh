#!/usr/bin/env bash
# crisplogo_resume_deploy.sh — resume the Grecharged-title-logo-fullres deploy from step 5.
# The libgk chain (build==APK==device) already verified; deploy_verify only failed on the CUSTOM
# PACK stamp, which LoaderActivity re-unpacks on its next boot (MainActivity bypasses extraction).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-title-logo-fullres; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[crisplogo-resume FAIL] $*" >&2; exit 1; }

say "5a. boot LoaderActivity so the custom pack re-unpacks at the new version"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || die "could not launch LoaderActivity"
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 1200 ]; do
  if bash .autoport/lib/deploy_verify.sh "$S" jak1 >/tmp/crisp_dv.log 2>&1; then ok=1; break; fi
  grep -q 'custom pack STALE' /tmp/crisp_dv.log || { echo "  deploy_verify failing for another reason:"; tail -6 /tmp/crisp_dv.log; }
  sleep 15
done
tail -8 /tmp/crisp_dv.log
[ "$ok" = 1 ] || die "custom pack never re-unpacked within 1200s"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true

say "5b. push the consistent 28-file arm64 CGO set + verify assets"
extract_done(){ $ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp >/dev/null 2>&1 \
  && [ "$($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
extract_done || die "asset bundle stamp / 28 CGOs not present after extraction"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -5 || die "CGO push failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"

say "DEPLOY OK — device runs fresh HEAD ($(git rev-parse --short HEAD))"
