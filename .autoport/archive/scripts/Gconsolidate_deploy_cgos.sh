#!/usr/bin/env bash
# Gconsolidate_deploy_cgos.sh — push the CONSISTENT current-HEAD 28-file CGO/DGO set
# (out/jak1-arm64-full/iso) onto the device runtime (files/cgo/jak1) via run-as,
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
# bundle v15+ (LoaderActivity.java:991): the loader's completion marker is now
# files/.cgo_pack_stamp_<game> (written LAST); the old .asset_bundle_stamp is gone.
# Extraction-done = per-game cgo stamp present + files/cgo/<game> populated.
$ADB -s $S shell run-as $PKG ls files/.cgo_pack_stamp_jak1 >/dev/null 2>&1 || die "run-as / .cgo_pack_stamp_jak1 missing (CE-locked or not extracted?)"
# The runtime (fake_iso) scans files/cgo/jak1/ FIRST as the active overlay (the slim-APK CGO-pack
# unpack dir), then falls back to the legacy adb-push dir files/cgo/jak1/. A push into iso_data/
# is INVISIBLE when cgo/ is populated -> the 2026-07-14 overhang5 mixed-build boot crash (fresh libgk
# + STALE GAME/ENGINE left in cgo/ after an extraction-skip). Deploy to the ACTIVE dir (cgo/ if
# present) AND iso_data/ for older installs.
DEST_DIRS="files/cgo/jak1"
if $ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  DEST_DIRS="files/cgo/jak1 files/cgo/jak1"
fi
$ADB -s $S shell run-as $PKG ls files/cgo/jak1/GAME.CGO >/dev/null 2>&1 || die "iso_data/jak1 not populated (extraction incomplete?)"

echo "== push 28 consistent HEAD CGO/DGO -> $DEST_DIRS (sha256-verified) =="
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0; cnt=0
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
  ok_all=1
  for DD in $DEST_DIRS; do
    $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$bn" "$DD/$bn" || { echo "  CP-FAIL $DD/$bn"; fail=1; ok_all=0; }
    got=$($ADB -s $S shell run-as $PKG sha256sum "$DD/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
    [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $DD/$bn want=$want got=$got"; fail=1; ok_all=0; }
  done
  $ADB -s $S shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  [ "$ok_all" = 1 ] && cnt=$((cnt+1))
done
[ "$fail" -eq 0 ] || die "one or more files failed to push/verify"
echo "[deploy-cgos] pushed + sha256-verified all $cnt/28 consistent HEAD files into $DEST_DIRS"
echo "[deploy-cgos] bundle stamp kept; device will boot the consolidated build on next launch."
