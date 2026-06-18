#!/usr/bin/env bash
# Gd1_deploy.sh — deploy the Gcine-camfov fix to the device, SIGILL-safely.
#
# Preconditions: device eae4df44 CE-UNLOCKED (run-as works). The fixed arm64
# boot CGOs exist at out/jak1-arm64/iso/ and the fixed APK is built. Only the 3
# boot CGOs (KERNEL/ENGINE/GAME) carry this fix; level DGOs are unchanged, so we
# push the 3 boot CGOs as a CONSISTENT SET (a standalone single-CGO push SIGILLs)
# and leave level DGOs as-is. Aborts on any inconsistency.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL=eae4df44
PKG=org.opengoal.gk.jak1
ARM64=out/jak1-arm64/iso
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CGOS=(KERNEL.CGO ENGINE.CGO GAME.CGO)
die(){ echo "[Gd1_deploy FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gd1_deploy] ok: $*"; }

echo "== Gd1_deploy $(date -Is) =="

# 0. Preconditions.
$ADB -s $SERIAL get-state >/dev/null 2>&1 || die "device $SERIAL not attached"
st=$($ADB -s $SERIAL shell dumpsys user 2>/dev/null | grep -oE 'RUNNING_(UN)?LOCKED' | head -1 | tr -d '\r')
[ "$st" = "RUNNING_UNLOCKED" ] || die "device still $st (needs owner CE-unlock)"
$ADB -s $SERIAL shell run-as $PKG ls files >/dev/null 2>&1 || die "run-as fails (CE locked)"
for c in "${CGOS[@]}"; do [ -s "$ARM64/$c" ] || die "missing built $ARM64/$c"; done
ok "device unlocked, run-as OK, built arm64 CGOs present"

install_apk(){
  [ -f "$APK" ] || die "no APK at $APK"
  echo "[Gd1_deploy] installing APK $APK (~1.3GB)"
  $ADB -s $SERIAL shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
  $ADB -s $SERIAL push "$APK" /data/local/tmp/gd1.apk >/dev/null || die "apk push failed"
  $ADB -s $SERIAL shell pm install -r -d -t -i com.android.vending /data/local/tmp/gd1.apk 2>&1 | tail -3
  $ADB -s $SERIAL shell rm -f /data/local/tmp/gd1.apk >/dev/null 2>&1 || true
  $ADB -s $SERIAL shell run-as $PKG ls files >/dev/null 2>&1 || die "run-as broke after install"
  ok "APK installed"
}

# 2. Ensure files/iso_data/jak1 exists (launch once to extract if needed).
if ! $ADB -s $SERIAL shell run-as $PKG ls files/iso_data/jak1/ENGINE.CGO >/dev/null 2>&1; then
  echo "[Gd1_deploy] iso_data not extracted yet — launching once to extract (up to 5min)"
  $ADB -s $SERIAL shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  for i in $(seq 1 60); do
    sleep 5
    $ADB -s $SERIAL shell run-as $PKG ls files/iso_data/jak1/GAME.CGO >/dev/null 2>&1 && break
  done
  $ADB -s $SERIAL shell am force-stop $PKG >/dev/null 2>&1 || true
  $ADB -s $SERIAL shell run-as $PKG ls files/iso_data/jak1/GAME.CGO >/dev/null 2>&1 || die "extraction did not produce GAME.CGO"
fi
ok "filesDir iso_data present"

# 3. Push the 3 fixed boot CGOs as a consistent set; verify on-device hashes.
for c in "${CGOS[@]}"; do
  $ADB -s $SERIAL push "$ARM64/$c" "/data/local/tmp/$c" >/dev/null || die "push $c to tmp failed"
  $ADB -s $SERIAL shell run-as $PKG cp "/data/local/tmp/$c" "files/iso_data/jak1/$c" || die "run-as cp $c failed"
  $ADB -s $SERIAL shell rm -f "/data/local/tmp/$c" >/dev/null 2>&1 || true
  want=$(sha256sum "$ARM64/$c" | awk '{print $1}')
  got=$($ADB -s $SERIAL shell run-as $PKG sha256sum "files/iso_data/jak1/$c" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] || die "$c on-device hash $got != built $want"
  echo "[Gd1_deploy]   $c on-device hash == built ($want)"
done
ok "all 3 boot CGOs pushed + hash-verified on device (consistent set)"

# 4. deploy_verify (libgk chain). If the device is running a stale libgk.so,
#    install the fresh APK and re-verify (then re-push CGOs since paranoia is cheap).
if ! bash .autoport/lib/deploy_verify.sh $SERIAL; then
  echo "[Gd1_deploy] deploy_verify failed — device libgk likely stale; installing APK"
  install_apk
  for c in "${CGOS[@]}"; do
    $ADB -s $SERIAL push "$ARM64/$c" "/data/local/tmp/$c" >/dev/null || die "re-push $c failed"
    $ADB -s $SERIAL shell run-as $PKG cp "/data/local/tmp/$c" "files/iso_data/jak1/$c" || die "re-cp $c failed"
    $ADB -s $SERIAL shell rm -f "/data/local/tmp/$c" >/dev/null 2>&1 || true
    want=$(sha256sum "$ARM64/$c" | awk '{print $1}')
    got=$($ADB -s $SERIAL shell run-as $PKG sha256sum "files/iso_data/jak1/$c" 2>/dev/null | awk '{print $1}' | tr -d '\r')
    [ "$want" = "$got" ] || die "$c on-device hash $got != built $want (after reinstall)"
  done
  bash .autoport/lib/deploy_verify.sh $SERIAL || die "deploy_verify still failing after reinstall"
fi
echo "== Gd1_deploy DONE $(date -Is) =="
