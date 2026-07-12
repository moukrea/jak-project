#!/usr/bin/env bash
# Gconsolidate_deploy_cgos.sh — push the CONSISTENT current-HEAD 28-file CGO/DGO set
# (out/jak1-arm64-full/iso) onto the device runtime (files/iso_data/jak1) via run-as,
# sha256-verifying every file. Keeps .extracted_v1 so the app does NOT re-extract the
# APK's bundled assets on next launch. libgk/APK already == HEAD on device (deploy_verify).
# Does NOT restore known-good — this phase LEAVES the consolidated build on the device.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
SRC=out/jak1-arm64-full/iso
die(){ echo "[deploy-cgos FAIL] $*" >&2; exit 1; }

$ADB -s $S get-state >/dev/null 2>&1 || die "device $S not attached"
[ -d "$SRC" ] || die "consistent CGO set missing: $SRC"
n=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l); [ "$n" -eq 28 ] || die "expected 28 CGO/DGO in $SRC, got $n"
# bundle v14 (025f68399): the loader's marker is now files/.asset_bundle_stamp (the old
# per-iso .extracted_v1 is gone). Extraction-done = stamp present + iso_data/jak1 populated.
$ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp >/dev/null 2>&1 || die "run-as / .asset_bundle_stamp missing (CE-locked or not extracted?)"
$ADB -s $S shell run-as $PKG ls files/iso_data/jak1/GAME.CGO >/dev/null 2>&1 || die "iso_data/jak1 not populated (extraction incomplete?)"

echo "== push 28 consistent HEAD CGO/DGO -> files/iso_data/jak1 (sha256-verified) =="
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0; cnt=0
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
  $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$bn" "files/iso_data/jak1/$bn" || { echo "  CP-FAIL $bn"; fail=1; }
  $ADB -s $S shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/iso_data/jak1/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] && cnt=$((cnt+1)) || { echo "  VERIFY-FAIL $bn want=$want got=$got"; fail=1; }
done
[ "$fail" -eq 0 ] || die "one or more files failed to push/verify"
echo "[deploy-cgos] pushed + sha256-verified all $cnt/28 consistent HEAD files into files/iso_data/jak1"
echo "[deploy-cgos] bundle stamp kept; device will boot the consolidated build on next launch."
