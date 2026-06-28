#!/usr/bin/env bash
# deploy_fix_to_device.sh — put the Gcollision-nanroot FIX (fmin/fmax codegen) on the
# device for the OWNER play-test. The phase validator restores the known-good CGO set
# as its safe state, so this re-deploys the FIXED full-consistent arm64 CGO set
# (out/jak1-arm64-full/iso, 28 files, built with the fmin/fmax fix). The clean
# fmin/fmax-fixed libgk is already installed (deploy_verify PASS); this only swaps the
# CGO/DGO assets in files/iso_data/jak1.
#
# NOTE: Gconsolidate_deploy_cgos.sh checks files/iso_data/jak1/.extracted_v1, but the
# app's extraction sentinel moved to files/.asset_bundle_stamp — so this helper does the
# launch-to-extract then direct run-as push that was verified working this phase.
#
# Usage: bash .autoport/reports/Gcollision-nanroot/deploy_fix_to_device.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
SRC=out/jak1-arm64-full/iso
die(){ echo "[deploy-fix FAIL] $*" >&2; exit 1; }
[ -d "$SRC" ] || die "fixed CGO set missing: $SRC (re-run build_arm64_full_consistent.sh)"
n=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l); [ "$n" -eq 28 ] || die "expected 28, got $n"
$ADB -s $S get-state >/dev/null 2>&1 || die "device $S not attached"

# 1. launch once so the app extracts its asset bundle (creates files/iso_data/jak1/*)
$ADB -s $S shell am start -n $PKG/.LoaderActivity >/dev/null 2>&1 || true
for i in $(seq 1 30); do $ADB -s $S shell "run-as $PKG ls files/iso_data/jak1/GAME.CGO" >/dev/null 2>&1 && break; sleep 2; done
$ADB -s $S shell am force-stop $PKG; sleep 2

# 2. push the 28 fixed CGO/DGO over the extracted set, sha256-verified
ok=0
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "PUSH-FAIL $bn"; continue; }
  $ADB -s $S shell "run-as $PKG cp /data/local/tmp/$bn files/iso_data/jak1/$bn" 2>/dev/null
  $ADB -s $S shell "rm -f /data/local/tmp/$bn" >/dev/null 2>&1
  got=$($ADB -s $S shell "run-as $PKG sha256sum files/iso_data/jak1/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] && ok=$((ok+1)) || echo "VERIFY-FAIL $bn"
done
[ "$ok" -eq 28 ] || die "only $ok/28 verified"
echo "[deploy-fix] 28/28 fixed CGO/DGO pushed + sha256-verified into files/iso_data/jak1"
echo "[deploy-fix] launch for the owner play-test:"
echo "    $ADB -s $S shell am start -n $PKG/.LoaderActivity"
echo "[deploy-fix] (drive Jak into walls/ledges; collision should behave like the x86 build)"
