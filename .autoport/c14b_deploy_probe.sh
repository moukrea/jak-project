#!/usr/bin/env bash
# c14b_deploy_probe.sh — install the fresh APK, push the external physics_chains.txt override,
# deploy_verify, then the single-leg D-MAX probe (fast iteration before the full 5-leg proof).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets
die(){ echo "[c14b-deploy FAIL] $*" >&2; exit 1; }

$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — wait for owner"
fi
echo "== install APK =="
$ADB -s $S install -r -d -t "$APK" 2>&1 | tail -2 || die "apk install failed"
echo "== push external physics_chains.txt override =="
$ADB -s $S push recharged_assets/physics_chains.txt "$EXT/physics_chains.txt" || die "chains push failed"
$ADB -s $S push recharged_assets/physics_mesh.txt "$EXT/physics_mesh.txt" || die "mesh push failed"
echo "== deploy_verify =="
bash .autoport/lib/deploy_verify.sh $S jak1 2>&1 | tail -3 || die "deploy_verify failed"
echo "== D-MAX probe =="
bash .autoport/physics_probe_dmax.sh
