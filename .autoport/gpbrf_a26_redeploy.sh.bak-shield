#!/usr/bin/env bash
# gpbrf_a26_redeploy.sh — attempt-26 CLOSE-GATE fix.
#
# ROOT CAUSE of the attempt-25 close-gate failure (diagnosed 2026-07-25):
#   build-android/lib/arm64-v8a/libgk.so was rebuilt at 10:58 (sha d3019ba3...),
#   but android/app/src/main/jniLibs/arm64-v8a/libgk.so was still the 06:45 copy
#   (sha 6b75e562...) and the APK on disk was the 06:45 assemble. The worker ran
#   `cmake --build build-android --target gk` DIRECTLY and never re-ran gradle, so
#   gradle's copyNativeLibs (build-android -> jniLibs) never fired and the APK
#   bundled the STALE .so => deploy_verify check 3 "build libgk.so != APK-bundled".
#   FIXED by re-running ./gradlew assembleJak1Debug: build==jniLibs==APK==d3019ba3.
#
# SECOND blocker: the Redmi (eae4df44) physically left the USB bus at 08:29:52
#   (journalctl: "usb 1-6: USB disconnect, device number 97"); it is absent from
#   lsusb and there is no wireless-adb route to it (the only LAN host with 5555
#   open is 192.168.1.32, an NVIDIA device, and it is unauthorized anyway).
#   deploy_verify's chain step + the orchestrator's boot check BOTH need the
#   device, so this script WAITS for it to come back and then finishes the deploy.
#
# CGO consistency: jak1_cgo.zip is 2026-07-24 15:10, newest goal_src is
#   2026-07-24 12:34 (progress-pc.gc) => the CGO pack already reflects HEAD
#   goal_src. This is a libgk-ONLY redeploy; `install -r` keeps app data so the
#   unpacked device CGOs/custom pack persist.
#
# Usage: gpbrf_a26_redeploy.sh [WAIT_SECONDS]   (default 900)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${ANDROID_SERIAL:-eae4df44}"; PKG=org.opengoal.gk.jak1; GAME=jak1
ACT_MAIN="$PKG/org.opengoal.gk.MainActivity"
ACT_LOAD="$PKG/.LoaderActivity"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SO=build-android/lib/arm64-v8a/libgk.so
WAIT_S="${1:-900}"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[a26-redeploy FAIL] $*" >&2; exit 1; }

say "0. local chain: build == jniLibs == APK (device-independent)"
[ -f "$SO" ] || die "no libgk.so at $SO"
[ -f "$APK" ] || die "no APK at $APK"
B=$(sha256sum "$SO" | cut -d' ' -f1)
J=$(sha256sum android/app/src/main/jniLibs/arm64-v8a/libgk.so 2>/dev/null | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "  build   = ${B:0:16}  ($(stat -c '%y' "$SO" | cut -c1-19))"
echo "  jniLibs = ${J:0:16}"
echo "  apk     = ${A:0:16}  ($(stat -c '%y' "$APK" | cut -c1-19))"
[ "$B" = "$J" ] || die "jniLibs stale — run ./gradlew assembleJak1Debug"
[ "$B" = "$A" ] || die "APK bundled a STALE libgk — run ./gradlew assembleJak1Debug"
echo "  ok: build==jniLibs==APK"

say "0b. freshness vs source (deploy_verify check 1, pre-flight)"
SO_MTIME=$(stat -c %Y "$SO")
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
echo "  libgk=$(date -d @$SO_MTIME +%H:%M:%S)  newest_src=$(date -d @$NEWEST_SRC +%H:%M:%S)"
[ "$SO_MTIME" -ge "$NEWEST_SRC" ] || die "libgk.so older than newest source — rebuild+reassemble"
echo "  ok: fresh"

say "1. wait for device $S (up to ${WAIT_S}s; recovers adb-server wedges)"
t0=$(date +%s); seen=0
while [ $(( $(date +%s) - t0 )) -lt "$WAIT_S" ]; do
  st=$("$ADB" -s "$S" get-state 2>/dev/null | tr -d '\r')
  if [ "$st" = "device" ]; then seen=1; echo "  device present after $(( $(date +%s) - t0 ))s"; break; fi
  # every ~60s bounce the adb server: a wedged daemon reports "not found" even
  # when the phone is physically back (feedback_adb_server_wedge_false_deploy_fail).
  if [ $(( ($(date +%s) - t0) % 60 )) -lt 6 ]; then
    "$ADB" kill-server >/dev/null 2>&1; sleep 1; "$ADB" start-server >/dev/null 2>&1
  fi
  sleep 5
done
if [ "$seen" -ne 1 ]; then
  echo
  echo "[a26-redeploy] DEVICE-ABSENT: $S never appeared within ${WAIT_S}s."
  echo "  lsusb shows no Android device; journalctl recorded 'usb 1-6: USB disconnect'"
  echo "  at 08:29:52. The phone is UNPLUGGED/powered off — this needs a physical"
  echo "  replug by the owner/supervisor. The LOCAL half of the close-gate"
  echo "  (build==jniLibs==APK==${B:0:16}, fresh vs source) is FIXED and verified;"
  echo "  re-run this script once the phone is back to finish install+boot+verify."
  exit 42
fi

say "2. device sanity (no reboot — feedback_device_reboot_locks_out)"
"$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if "$ADB" -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then
  die "DEVICE_LOCKED — needs owner unlock (do NOT reboot)"
fi
TEMP=$("$ADB" -s "$S" shell dumpsys battery 2>/dev/null | grep -i temperature | grep -oE '[0-9]+' | head -1)
[ -n "${TEMP:-}" ] && echo "  battery temp=$((TEMP/10))C (battery LEVEL is bogus on this unit — ignored)"

say "3. install fresh APK (MIUI unblock recipe; -r keeps app data => CGO/custom pack persist)"
"$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
"$ADB" -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
"$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. launch + prove render (all logcat wrapped in timeout — supervisor mandate)"
"$ADB" -s "$S" shell svc power stayon true >/dev/null 2>&1 || true
"$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
"$ADB" -s "$S" logcat -c >/dev/null 2>&1 || true
LOG="$OUT/a26_redeploy_boot.log"; : > "$LOG"
( timeout 240 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|A42-TFTREE|master-mode=game|Setup failed|jak1_assets|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
"$ADB" -s "$S" shell am start -W -n "$ACT_MAIN" >/dev/null 2>&1 || \
  "$ADB" -s "$S" shell am start -W -n "$ACT_LOAD" >/dev/null 2>&1 || true
t0=$(date +%s); booted=0
while [ $(( $(date +%s) - t0 )) -lt 150 ]; do
  grep -aqE 'Setup failed|jak1_assets' "$LOG" 2>/dev/null && die "app shows 'Setup failed' — asset unpack failed"
  rf=$(grep -acE 'A35-RENDER frame=|A42-TFTREE|master-mode=game' "$LOG" 2>/dev/null); rf=${rf:-0}
  if [ "$rf" -ge 8 ] 2>/dev/null; then booted=1; echo "  render markers=$rf -> booted"; break; fi
  sleep 4
done
kill ${LCP:-0} 2>/dev/null || true
FOCUS=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  $FOCUS"
echo "$FOCUS" > "$OUT/a26_focus.txt"
case "$FOCUS" in *org.opengoal.gk.jak1*) echo "  ok: jak1 has focus";; *) echo "  WARN: focus not jak1";; esac

say "4b. wait for the custom pack to land (deploy_verify step 5 compares stamp+md5)"
# LoaderActivity re-unpacks jak1_custom.zip (57 members, ~194MB raw) on a version
# change; that can outlast the render-marker wait, and deploy_verify step 5 would
# then see a stale files/.custom_pack_stamp_jak1 and fail. Poll for the match.
CUS_VER=$(grep -E '^version=' "android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties" 2>/dev/null | cut -d= -f2)
if [ -n "${CUS_VER:-}" ]; then
  echo "  built custom-pack version=$CUS_VER"
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 420 ]; do
    DEV_STAMP=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
    [ "$DEV_STAMP" = "$CUS_VER" ] && { echo "  ok: device stamp matches after $(( $(date +%s) - t0 ))s"; break; }
    echo "  ... device stamp='${DEV_STAMP:-<none>}' (waiting, $(( $(date +%s) - t0 ))s)"
    sleep 10
  done
fi

say "5. deploy_verify — the exact orchestrator close-gate"
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee "$OUT/a26_deploy_verify.log"
DV=${PIPESTATUS[0]}
[ "$DV" -eq 0 ] || die "deploy_verify exit $DV — see $OUT/a26_deploy_verify.log"

echo
echo "[a26-redeploy] DONE — device $S provably runs the fresh HEAD libgk (${B:0:16}), booted=$booted."
