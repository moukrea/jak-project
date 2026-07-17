#!/usr/bin/env bash
# Gtouch-fix deploy: slim APK (libgk from HEAD) + push the freshly-built arm64
# CGO/DGO set (.autoport/gtf-arm64-set, same-HEAD => consistent build) + stamp.
# deploy_verify must PASS (build==APK==device libgk chain).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
PACKAGE="org.opengoal.gk.jak1"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
A() { "$ADB" -s "$SERIAL" "$@"; }
SRC=.autoport/gtf-arm64-set
[ -d "$SRC" ] || { echo "FAIL: $SRC missing"; exit 1; }
N=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l)
[ "$N" -eq 28 ] || { echo "FAIL: expected 28 CGO/DGO in $SRC, got $N"; exit 1; }

echo "== gradle slim APK (libgk only) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 8 ) || { echo "FAIL: gradle"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }

echo "== install =="
device_require_attached; device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked
device_miui_unblock_install
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/gtf-push.out 2>&1 || { cat /tmp/gtf-push.out; echo "FAIL: push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gtf-pm.out 2>&1 || { cat /tmp/gtf-pm.out; echo "FAIL: pm install"; exit 1; }
grep -q "Success" /tmp/gtf-pm.out || { cat /tmp/gtf-pm.out; echo "FAIL: pm install no Success"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true

echo "== deploy_verify =="
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }

echo "== push fresh arm64 CGO/DGO set (28 files) + stamp =="
# slim APK ships manifest version=2 but no assets zip (see gbe_run.sh); stamping
# it prevents LoaderActivity.unpackBundleIfNeeded from wiping the pushed set.
SLIM_VER="${SLIM_VER:-2}"
A shell run-as "$PACKAGE" mkdir -p files/cgo/jak1 files/out/jak1/fr3 >/dev/null 2>&1 || true
for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
  n=$(basename "$f")
  A push "$f" "/data/local/tmp/$n" >/dev/null 2>&1 && \
    A shell run-as "$PACKAGE" cp "/data/local/tmp/$n" "files/cgo/jak1/$n" >/dev/null 2>&1 \
    || { echo "FAIL: push $n"; exit 1; }
  A shell rm -f "/data/local/tmp/$n" >/dev/null 2>&1 || true
done
# stamp so LoaderActivity's unpack fast-path doesn't wipe the pushed set
if [ -n "${SLIM_VER:-}" ]; then
  A shell "run-as $PACKAGE sh -c 'echo $SLIM_VER > files/.asset_bundle_stamp'" >/dev/null 2>&1 || true
  echo "  stamped .asset_bundle_stamp=$SLIM_VER"
fi
echo "== verify pushed GAME.CGO hash =="
LOCAL=$(sha256sum "$SRC/GAME.CGO" | cut -d' ' -f1)
REMOTE=$(A shell run-as "$PACKAGE" sha256sum files/cgo/jak1/GAME.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  local=$LOCAL"
echo "  device=$REMOTE"
[ "$LOCAL" = "$REMOTE" ] || { echo "FAIL: GAME.CGO mismatch on device"; exit 1; }
echo "== DEPLOY OK =="
