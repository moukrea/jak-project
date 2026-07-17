#!/usr/bin/env bash
# restore_knowngood_device.sh — the UNDO BUTTON for the Redmi.
# Pushes the verified-good consistent 28-file CGO/DGO set to the app's runtime
# (files/cgo/jak1/) via run-as cp, as a CONSISTENT SET, and sha256-verifies.
# This set is the fresh CONSISTENT HEAD 28-file set (Gconsolidate-deploy): it
# boots clean to gameplay frame 11160, 0 sig, and carries the data-resident
# fixes (menu widen, sun corona, particles/stars) the June-11 set lacked.
# The June-11 dir (device-knowngood-cgos-20260618) is kept as a fallback.
# Use this any time a CGO experiment leaves the phone crashing.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
PKG=org.opengoal.gk.jak1
SRC=.autoport/backups/device-knowngood-cgos-20260622
die(){ echo "[restore FAIL] $*" >&2; exit 1; }

[ -d "$SRC" ] || die "backup set missing: $SRC"
$ADB -s $S get-state >/dev/null 2>&1 || die "device $S not attached"
$ADB -s $S shell run-as $PKG ls files/cgo/jak1 >/dev/null 2>&1 || die "run-as fails (device CE-locked?)"

echo "== restore_knowngood $(date -Is) =="
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell setprop debug.opengoal.gcine.cam 0 2>/dev/null || true
$ADB -s $S shell setprop debug.opengoal.gintro.dbg 0 2>/dev/null || true

fail=0
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  n=$(basename "$f")
  want=$(sha256sum "$f" | awk '{print $1}')
  $ADB -s $S push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 || { echo "  PUSH-FAIL $n"; fail=1; continue; }
  $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$n" "files/cgo/jak1/$n" || { echo "  CP-FAIL $n"; fail=1; }
  $ADB -s $S shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/cgo/jak1/$n" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || { echo "  VERIFY-FAIL $n"; fail=1; }
done
[ $fail -eq 0 ] || die "one or more files failed to restore"
echo "[restore] all $(ls "$SRC"/*.CGO "$SRC"/*.DGO | wc -l) files restored + sha256-verified (consistent set)"
echo "[restore] launch with: $ADB -s $S shell am start -n $PKG/.LoaderActivity"
