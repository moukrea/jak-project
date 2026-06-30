#!/usr/bin/env bash
# apk_selfcontained_verify.sh — install the FULL self-contained APK fresh, verify
# first-run decompression -> boot -> render (menu tint + frame). The owner's
# Task-3/4 deliverable gate: prove the in-APK bundle unpacks and the game boots
# from it with NO external data push.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL="${SERIAL:-eae4df44}"
PKG=org.opengoal.gk.jak1
ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Gapk-selfcontained
mkdir -p "$OUT"
TAG="${1:-run1}"
LOG="$OUT/$TAG-logcat.log"
A(){ "$ADB" -s "$SERIAL" "$@"; }

[ -f "$APK" ] || { echo "FAIL: $APK missing"; exit 1; }
echo "== APK $(du -h "$APK"|cut -f1) =="
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_miui_unblock_install 2>/dev/null || true

echo "== wipe app data + uninstall (force true first-run unpack) =="
A shell pm clear "$PKG" >/dev/null 2>&1 || true
A uninstall "$PKG" >/dev/null 2>&1 || true

echo "== install full self-contained APK (this pushes 1.2GB; ~1-2 min) =="
STAGE="/data/local/tmp/app-jak1-fullselfcontained.apk"
A push "$APK" "$STAGE" >/tmp/apk-push.out 2>&1 || { tail -5 /tmp/apk-push.out; echo "FAIL push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/apk-pm.out 2>&1 || true
if ! grep -q "Success" /tmp/apk-pm.out; then
  echo "  pm install needs MIUI dialog-tap; retrying with dialog tap..."
  A shell am start -a android.intent.action.VIEW -d "file://$STAGE" -t application/vnd.android.package-archive >/dev/null 2>&1 || true
  sleep 4
  # tap the AdbInstallActivity "Install/Continue" button (MIUI bottom-right)
  A shell input tap 880 2150 >/dev/null 2>&1 || true
  sleep 8
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/apk-pm2.out 2>&1 || true
  grep -q "Success" /tmp/apk-pm2.out || { echo "  (install via pm may have completed via dialog; checking pkg)"; }
fi
A shell rm -f "$STAGE" >/dev/null 2>&1 || true
A shell pm path "$PKG" >/dev/null 2>&1 || { echo "FAIL: package not installed"; exit 1; }
echo "  installed: $(A shell pm path "$PKG" | tr -d '\r')"

echo "== first-run launch: unpack -> boot -> render =="
A logcat -c >/dev/null 2>&1 || true
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LCPID=$!
trap 'kill $LCPID 2>/dev/null||true; A shell svc power stayon true >/dev/null 2>&1||true' EXIT
A shell am start -W -n "$PKG/$ACT" >/tmp/apk-am.out 2>&1 || true

echo "  waiting for first-run unpack (up to 600s; 1.6GB decompress)..."
UNPACK_OK=0
for i in $(seq 1 600); do
  if grep -qaE "unpack.*complete|decompress.*done|asset.*ready|Bundle unpack|unpacked|asset_bundle_stamp|link finish: logo" "$LOG"; then UNPACK_OK=1; echo "  unpack/boot marker ~${i}s"; break; fi
  grep -qaE "asset setup failed|FATAL|Fatal signal" "$LOG" && { echo "  unpack FAILED ~${i}s"; break; }
  (( i % 30 == 0 )) && echo "   [unpack ${i}s] $(grep -aoE 'unpack[^ ]*|[0-9]+%|link finish: [a-z0-9-]+' "$LOG" | tail -1)"
  sleep 1
done

echo "  waiting for title (link finish: logo, up to 180s)..."
for i in $(seq 1 180); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; grep -qaE "Fatal signal|GK-DIAG sig=" "$LOG" && { echo "  CRASH"; break; }; sleep 1; done

echo "  observing render for 60s..."
for i in $(seq 1 60); do (( i % 20 == 0 )) && echo "   frame=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG"|grep -oE '[0-9]+$'|sort -n|tail -1)"; sleep 1; done

# capture a frame
A shell screencap -p /sdcard/apk-$TAG.png >/dev/null 2>&1 || true
A pull /sdcard/apk-$TAG.png "$OUT/$TAG-frame.png" >/dev/null 2>&1 || true
A shell rm -f /sdcard/apk-$TAG.png >/dev/null 2>&1 || true

FRAME=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG"|grep -oE '[0-9]+$'|sort -n|tail -1); FRAME=${FRAME:-0}
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PKG" && echo yes || echo no)
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|Fatal signal [0-9]+' "$LOG" | tail -1)
STAMP=$(A shell run-as "$PKG" cat files/.asset_bundle_stamp 2>/dev/null | tr -d '\r')
NISO=$(A shell run-as "$PKG" ls files/iso_data/jak1/ 2>/dev/null | tr -d '\r' | wc -l)
NVIS=$(A shell run-as "$PKG" ls files/iso_data/jak1/ 2>/dev/null | tr -d '\r' | grep -ic VIS)

{
echo "=== Gapk-selfcontained ($TAG) $(date -Is) ==="
echo "RESULT unpack_ok=$UNPACK_OK title_frame=$FRAME focus=$FOC sig=${SIG:-none}"
echo "  device files/iso_data/jak1 count=$NISO  VIS=$NVIS  asset_bundle_stamp=$STAMP"
echo "  last link-finish: $(grep -aoE 'link finish: [a-z0-9-]+' "$LOG"|tail -6|tr '\n' ' ')"
} | tee "$OUT/$TAG-result.txt"
kill $LCPID 2>/dev/null || true
echo "== done =="
