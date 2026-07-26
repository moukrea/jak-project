#!/usr/bin/env bash
# gpbrf_a27_redeploy.sh — attempt-4 CLOSE-GATE fix (deploy_verify chain).
#
# ROOT CAUSE of the attempt-3 close-gate failure (diagnosed 2026-07-26 21:0x):
#   NOT a stale build. The local half of the chain was already correct:
#     build-android/lib/arm64-v8a/libgk.so == jniLibs == app-jak1-debug.apk == 0a6830c1
#   The DEVICE was carrying 0e4f3e92 — which is not an old binary at all, it is
#   build-android-checker/lib/arm64-v8a/libgk.so, the CHECKER-DEBUG variant, installed
#   at 19:55 because the owner's standing rule makes the checker build the one that gets
#   played. deploy_verify audits the NORMAL build's sha chain (it hardcodes build-android),
#   so a device holding the checker variant reads as "STALE install" even though both .so
#   were linked from the same HEAD sources minutes apart and carry the SAME flag set
#   (ogflags:465b53fe1394:android-arm64 on both).
#
#   So this is an artifact-ROUTING bug, not a freshness bug:
#     - the OWNER's deliverable is .autoport/dist/app-jak1-CHECKER-DEBUG.apk (checker ON) —
#       he has no adb, the pattern must be armed out of the box; that stays untouched;
#     - the DEV Redmi (eae4df44) is the smoke/verify device and is what deploy_verify
#       audits, so it must carry the NORMAL APK — the exact artifact of the sha chain.
#   Fixing it by teaching deploy_verify to also accept build-android-checker would be
#   changing the instrument to make the metric move. Refused. We move the artifact.
#
# The checker build has ALREADY been smoke-tested on this device: it was the install from
# 19:55 and r26_smoke.mp4/.png (20:40) were captured through it. This script smoke-tests the
# NORMAL build too, so both halves of the pair are proven to boot before the phase closes.
#
# libgk-ONLY redeploy: `install -r` keeps app data, so the unpacked device CGOs, the custom
# pack and the seeded settings all persist. No goal_src changed => the CGO pack still matches.
#
# Usage: gpbrf_a27_redeploy.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${ANDROID_SERIAL:-eae4df44}"; PKG=org.opengoal.gk.jak1; GAME=jak1
ACT_MAIN="$PKG/org.opengoal.gk.MainActivity"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
CHK_APK=.autoport/dist/app-jak1-CHECKER-DEBUG.apk
SO=build-android/lib/arm64-v8a/libgk.so
CHK_SO=build-android-checker/lib/arm64-v8a/libgk.so
JNI=android/app/src/main/jniLibs/arm64-v8a/libgk.so
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[a27-redeploy FAIL] $*" >&2; exit 1; }

say "0. local chain: build == jniLibs == APK (device-independent, NORMAL variant)"
[ -f "$SO" ]  || die "no libgk.so at $SO"
[ -f "$APK" ] || die "no APK at $APK"
B=$(sha256sum "$SO"  | cut -d' ' -f1)
J=$(sha256sum "$JNI" | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
C=$(sha256sum "$CHK_SO" 2>/dev/null | cut -d' ' -f1)
K=$(unzip -p "$CHK_APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "  normal  build   = ${B:0:16}  ($(stat -c '%y' "$SO" | cut -c1-19))"
echo "  normal  jniLibs = ${J:0:16}"
echo "  normal  apk     = ${A:0:16}  ($(stat -c '%y' "$APK" | cut -c1-19))"
echo "  checker build   = ${C:0:16}  ($(stat -c '%y' "$CHK_SO" | cut -c1-19))"
echo "  checker apk     = ${K:0:16}  ($(stat -c '%y' "$CHK_APK" | cut -c1-19))  [owner deliverable]"
[ "$B" = "$J" ] || die "jniLibs stale — run ./gradlew assembleJak1Debug"
[ "$B" = "$A" ] || die "APK bundled a STALE libgk — run ./gradlew assembleJak1Debug"
[ "$B" != "$C" ] || die "checker libgk is byte-identical to the normal one — the define did not take"
[ "$C" = "$K" ] || die "the parked checker APK does not bundle the checker libgk"
# the two variants must be flag-set siblings, else the device CGOs pair with only one of them
FB=$(strings "$SO" | grep -m1 '^ogflags:'); FC=$(strings "$CHK_SO" | grep -m1 '^ogflags:')
echo "  flagset normal=$FB  checker=$FC"
[ "$FB" = "$FC" ] || die "the two variants carry different flag sets — they are not siblings"
echo "  ok: build==jniLibs==APK, checker variant is a distinct sibling of the same flag set"

say "0b. freshness vs source (deploy_verify check 1, pre-flight; incl. glsl/tesc/tese)"
STALE=$(find game/graphics game/kernel android/src -type f \
  \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
     -o -name '*.tesc' -o -name '*.tese' \) -newer "$SO" -print -quit 2>/dev/null)
[ -z "$STALE" ] || die "normal libgk is OLDER than $STALE — rebuild before deploying"
STALE=$(find game/graphics game/kernel android/src -type f \
  \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
     -o -name '*.tesc' -o -name '*.tese' \) -newer "$CHK_SO" -print -quit 2>/dev/null)
[ -z "$STALE" ] || die "checker libgk is OLDER than $STALE — rebuild before shipping"
echo "  ok: both variants newer than every renderer source"

say "1. device $S present (adb-server wedge recovery: lsusb discriminates)"
st=$("$ADB" -s "$S" get-state 2>/dev/null | tr -d '\r')
if [ "$st" != "device" ]; then
  lsusb | grep -qi 'Xiaomi' && { "$ADB" kill-server >/dev/null 2>&1; sleep 2; "$ADB" start-server >/dev/null 2>&1; sleep 3; }
  st=$("$ADB" -s "$S" get-state 2>/dev/null | tr -d '\r')
fi
[ "$st" = "device" ] || die "device $S not in 'device' state (state='$st'); lsusb: $(lsusb | grep -ci Xiaomi) Xiaomi node(s)"
echo "  ok: device present"

say "1b. what the device is running RIGHT NOW (the mismatch, before the fix)"
DP=$("$ADB" -s "$S" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || die "package not installed (check lsusb: absent phone vs wedged adb)"
mkdir -p .autoport/tmp; T=$(mktemp -d .autoport/tmp/a27.XXXXXX); trap "rm -rf $T" EXIT
"$ADB" -s "$S" pull "$DP" "$T/before.apk" >/dev/null 2>&1 || die "could not pull device APK"
DB=$(unzip -p "$T/before.apk" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
echo "  device libgk BEFORE = ${DB:0:16}"
case "$DB" in
  "$C") echo "  -> it is the CHECKER variant (as diagnosed): the owner build, not the audited one";;
  "$B") echo "  -> it is ALREADY the normal variant; the chain should have passed";;
  *)    echo "  -> it is NEITHER current variant: a genuinely old install";;
esac

say "2. device sanity (no reboot — feedback_device_reboot_locks_out)"
"$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"$ADB" -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock (do NOT reboot)"
TEMP=$("$ADB" -s "$S" shell dumpsys battery 2>/dev/null | grep -i temperature | grep -oE '[0-9]+' | head -1)
[ -n "${TEMP:-}" ] && echo "  battery temp=$((TEMP/10))C (LEVEL is bogus on this unit — ignored)"

say "3. install the NORMAL APK (MIUI unblock recipe; -r keeps data => CGO/custom pack persist)"
"$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
"$ADB" -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
"$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. launch + prove render (smoke only — owner banned agent-side visual measurement)"
"$ADB" -s "$S" shell svc power stayon true >/dev/null 2>&1 || true
"$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
"$ADB" -s "$S" logcat -c >/dev/null 2>&1 || true
LOG="$OUT/a27_normal_boot.log"; : > "$LOG"
( timeout 240 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|A42-TFTREE|master-mode=game|Setup failed|jak1_assets|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true; rm -rf $T' EXIT
"$ADB" -s "$S" shell am start -W -n "$ACT_MAIN" >/dev/null 2>&1 || true
t0=$(date +%s); booted=0
while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
  grep -aqE 'Setup failed|jak1_assets' "$LOG" 2>/dev/null && die "app shows 'Setup failed' — asset unpack failed"
  rf=$(grep -acE 'A35-RENDER frame=|A42-TFTREE|master-mode=game' "$LOG" 2>/dev/null); rf=${rf:-0}
  if [ "$rf" -ge 8 ] 2>/dev/null; then booted=1; echo "  render markers=$rf after $(( $(date +%s) - t0 ))s -> booted"; break; fi
  sleep 4
done
[ "$booted" -eq 1 ] || die "no render markers within 180s — the normal build does not boot"

say "4b. crash check (narrow sig pattern; SIGKILL on background pids is NOT our crash)"
CRASH=$(grep -aE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" | head -3)
[ -z "$CRASH" ] || die "crash signature in the boot log: $CRASH"
echo "  ok: no sig11/6/4 in the boot window"

say "4c. focus + smoke capture (screenrecord: screencap is black on the GL surface)"
FOCUS=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  $FOCUS"
echo "$FOCUS" > "$OUT/a27_normal_focus.txt"
case "$FOCUS" in *org.opengoal.gk.jak1*) echo "  ok: jak1 has focus";; *) die "focus is not jak1: $FOCUS";; esac
"$ADB" -s "$S" shell screenrecord --time-limit 16 /sdcard/a27_smoke.mp4 >/dev/null 2>&1 &
SRP=$!
sleep 20; kill -INT $SRP 2>/dev/null || true; wait $SRP 2>/dev/null || true
sleep 3
"$ADB" -s "$S" pull /sdcard/a27_smoke.mp4 "$OUT/a27_normal_smoke.mp4" >/dev/null 2>&1 || echo "  WARN: no mp4 pulled"
"$ADB" -s "$S" shell rm -f /sdcard/a27_smoke.mp4 >/dev/null 2>&1 || true
if [ -s "$OUT/a27_normal_smoke.mp4" ]; then
  ffmpeg -y -ss 8 -i "$OUT/a27_normal_smoke.mp4" -frames:v 1 "$OUT/a27_normal_smoke.png" >/dev/null 2>&1 \
    || echo "  WARN: frame extract failed"
  ls -la "$OUT/a27_normal_smoke.mp4" "$OUT/a27_normal_smoke.png" 2>/dev/null
fi
# focus must still be jak1 AFTER the capture (shared device: the parallel project can steal it)
FOCUS2=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  post-capture $FOCUS2"
echo "$FOCUS2" >> "$OUT/a27_normal_focus.txt"
case "$FOCUS2" in *org.opengoal.gk.jak1*) echo "  ok: still jak1 at end of capture";; *) die "focus lost during capture: $FOCUS2";; esac

say "4d. custom pack landing (deploy_verify step 5 compares stamp + per-member md5)"
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
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee "$OUT/a27_deploy_verify.log"
DV=${PIPESTATUS[0]}
[ "$DV" -eq 0 ] || die "deploy_verify exit $DV — see $OUT/a27_deploy_verify.log"

echo
echo "[a27-redeploy] DONE"
echo "  dev Redmi $S  : NORMAL  libgk ${B:0:16}  (audited chain, booted, no crash)"
echo "  owner deliver : CHECKER libgk ${C:0:16}  -> $CHK_APK"
