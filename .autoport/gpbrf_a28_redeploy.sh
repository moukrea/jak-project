#!/usr/bin/env bash
# gpbrf_a28_redeploy.sh — CLOSE-GATE fix, round 28 attempt 1.
#
# TWO ROOT CAUSES, both distinct from the a27 one. Read both before editing.
#
# CAUSE 1 (why deploy_verify said "STALE install"):
#   The local chain was already correct and FRESH:
#     build-android/lib/arm64-v8a/libgk.so == jniLibs == app-jak1-debug.apk == 6df69de5 (09:57/09:59)
#   The device was carrying fb30348f, installed 09:07:41 — i.e. ~52 min BEFORE the .so was even
#   linked. So unlike a27 this was NOT the checker-sibling routing case (the device held NEITHER
#   current variant); it was a genuinely old install that simply never received the 09:59 APK.
#   No source (checked WIDER than deploy_verify's own scan: game/graphics game/kernel android/src
#   PLUS common/ and goalc/, which is what matters for a DATA round) is newer than either libgk.
#   => The fix is a REINSTALL, not a rebuild. Do not rebuild.
#
# CAUSE 2 (why a27 could not have finished this one, and why it is NOT a27's fault):
#   a27 launches MainActivity DIRECTLY (am start -n $PKG/org.opengoal.gk.MainActivity), which
#   BYPASSES LoaderActivity. But LoaderActivity is the LAUNCHER (AndroidManifest.xml:51-62) and is
#   the ONLY writer of files/.custom_pack_stamp_<game> (LoaderActivity.java:1050, via
#   unpackCustomPackIfNeeded -> writeStamp). deploy_verify step 5 compares that stamp + every
#   member md5 against the built pack, so bypassing the loader makes step 5 unpassable.
#   a27 got away with it on rounds 26/28-earlier because the custom pack had NOT changed between
#   builds, so the stamp already matched and the skip-path was harmless. Round 28 is a DATA round:
#   it regenerates the .meshweld sidecars, which ARE members of the custom pack (57 files,
#   191 MB), so the pack version legitimately moved (built ca7bd7e3c71ab vs device cd58feac43f7b)
#   and MUST be re-unpacked.
#   => Launch through the LAUNCHER (LoaderActivity), never MainActivity, whenever the pack moved.
#      unpackCustomPackIfNeeded is version-stamped wipe->unpack->stamp-LAST, so it self-heals; the
#      CGO pack (unpackCgoPackIfNeeded) refreshes on the same pass, which also keeps
#      deploy_verify's step-4 flag-set pairing honest.
#
# The APK is installed with `install -r` (keeps app data), then relaunched through LoaderActivity
# so both packs re-unpack. 191 MB of unpack on this Redmi is not instant — hence the long stamp
# wait. Owner rule: no agent-side visual measurement; the device is used only to prove it installs,
# boots, does not crash, and lands the packs.
#
# Usage: gpbrf_a28_redeploy.sh   [env: ANDROID_SERIAL, ADB]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${ANDROID_SERIAL:-eae4df44}"; PKG=org.opengoal.gk.jak1; GAME=jak1
ACT_LOADER="$PKG/$PKG.LoaderActivity"   # the LAUNCHER alias (manifest activity-alias)
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SO=build-android/lib/arm64-v8a/libgk.so
CHK_SO=build-android-checker/lib/arm64-v8a/libgk.so
JNI=android/app/src/main/jniLibs/arm64-v8a/libgk.so
CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[a28-redeploy FAIL] $*" >&2; exit 1; }

say "0. local chain: build == jniLibs == APK (device-independent, NORMAL variant)"
[ -f "$SO" ]  || die "no libgk.so at $SO"
[ -f "$APK" ] || die "no APK at $APK"
B=$(sha256sum "$SO"  | cut -d' ' -f1)
J=$(sha256sum "$JNI" | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum | cut -d' ' -f1)
C=$(sha256sum "$CHK_SO" 2>/dev/null | cut -d' ' -f1)
echo "  normal  build   = ${B:0:16}  ($(stat -c '%y' "$SO" | cut -c1-19))"
echo "  normal  jniLibs = ${J:0:16}"
echo "  normal  apk     = ${A:0:16}  ($(stat -c '%y' "$APK" | cut -c1-19))"
echo "  checker build   = ${C:0:16}  ($(stat -c '%y' "$CHK_SO" | cut -c1-19))"
[ "$B" = "$J" ] || die "jniLibs stale — run ./gradlew assembleJak1Debug"
[ "$B" = "$A" ] || die "APK bundled a STALE libgk — run ./gradlew assembleJak1Debug"
[ "$B" != "$C" ] || die "checker libgk is byte-identical to the normal one — the define did not take"
echo "  ok: build==jniLibs==APK, checker is a distinct sibling"

say "0b. freshness vs source — WIDER than deploy_verify (adds common/ + goalc/, the DATA-round path)"
for V in "$SO" "$CHK_SO"; do
  STALE=$(find game/graphics game/kernel android/src common goalc -type f \
    \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
       -o -name '*.tesc' -o -name '*.tese' \) -newer "$V" -print -quit 2>/dev/null)
  [ -z "$STALE" ] || die "$(basename $(dirname $(dirname $(dirname $V)))) libgk is OLDER than $STALE — rebuild"
done
echo "  ok: both variants newer than every source (incl. common/, where MeshSubdivide/MeshConsolidate live)"

say "1. device $S present (lsusb discriminates wedged adb from an unplugged phone)"
st=$("$ADB" -s "$S" get-state 2>/dev/null | tr -d '\r')
if [ "$st" != "device" ]; then
  lsusb | grep -qi 'Xiaomi' && { "$ADB" kill-server >/dev/null 2>&1; sleep 2; "$ADB" start-server >/dev/null 2>&1; sleep 3; }
  st=$("$ADB" -s "$S" get-state 2>/dev/null | tr -d '\r')
fi
[ "$st" = "device" ] || die "device $S not in 'device' state (state='$st'); lsusb: $(lsusb | grep -ci Xiaomi) Xiaomi node(s)"
"$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"$ADB" -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock (do NOT reboot)"
TEMP=$("$ADB" -s "$S" shell dumpsys battery 2>/dev/null | grep -i temperature | grep -oE '[0-9]+' | head -1)
[ -n "${TEMP:-}" ] && echo "  battery temp=$((TEMP/10))C (LEVEL is bogus on this unit — ignored)"
[ -n "${TEMP:-}" ] && [ "$((TEMP/10))" -ge 45 ] && die "device at $((TEMP/10))C — cool down first"
echo "  ok: device present"

say "2. install the NORMAL APK if the device is not already on it (MIUI recipe; -r keeps data)"
mkdir -p .autoport/tmp; T=$(mktemp -d .autoport/tmp/a28.XXXXXX); trap 'kill ${LCP:-0} 2>/dev/null || true; rm -rf $T' EXIT
DP=$("$ADB" -s "$S" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || die "package not installed (check lsusb: absent phone vs wedged adb)"
"$ADB" -s "$S" pull "$DP" "$T/before.apk" >/dev/null 2>&1 || die "could not pull device APK"
DB=$(unzip -p "$T/before.apk" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
echo "  device libgk BEFORE = ${DB:0:16}"
if [ "$DB" = "$B" ]; then
  echo "  -> already the audited NORMAL variant; skipping install (pack landing still verified below)"
else
  case "$DB" in
    "$C") echo "  -> CHECKER variant (the a27 routing case): replacing with the audited NORMAL build";;
    *)    echo "  -> NEITHER current variant: a genuinely old install";;
  esac
  "$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
  "$ADB" -s "$S" shell pm trim-caches 999G >/dev/null 2>&1 || true
  "$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
fi
rm -f "$T/before.apk"

say "3. relaunch through the LAUNCHER (LoaderActivity) so BOTH packs re-unpack — CAUSE 2"
CUS_VER=$(grep -E '^version=' "$CUS_MAN" 2>/dev/null | cut -d= -f2)
CUS_FC=$(grep -E '^file_count=' "$CUS_MAN" 2>/dev/null | cut -d= -f2)
echo "  built custom pack version=$CUS_VER  file_count=$CUS_FC"
"$ADB" -s "$S" shell svc power stayon true >/dev/null 2>&1 || true
"$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
"$ADB" -s "$S" logcat -c >/dev/null 2>&1 || true
LOG="$OUT/a28_normal_boot.log"; : > "$LOG"
( timeout 900 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I GKLoader:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|A42-TFTREE|master-mode=game|Setup failed|jak1_assets|custom pack|CGO pack|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
"$ADB" -s "$S" shell am start -W -n "$ACT_LOADER" >/dev/null 2>&1 || die "could not start LoaderActivity ($ACT_LOADER)"

say "3b. wait for the custom-pack stamp to reach the built version (191 MB unpack, be patient)"
if [ -n "${CUS_VER:-}" ] && [ "${CUS_FC:-0}" -gt 0 ]; then
  t0=$(date +%s); landed=0
  while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
    grep -aqE 'Setup failed|jak1_assets' "$LOG" 2>/dev/null && die "app shows 'Setup failed' — asset unpack failed"
    DEV_STAMP=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
    if [ "$DEV_STAMP" = "$CUS_VER" ]; then landed=1; echo "  ok: stamp=$DEV_STAMP after $(( $(date +%s) - t0 ))s"; break; fi
    echo "  ... stamp='${DEV_STAMP:-<none>}' want='$CUS_VER' ($(( $(date +%s) - t0 ))s)"
    sleep 15
  done
  [ "$landed" -eq 1 ] || die "custom pack never reached version $CUS_VER in 900s (LoaderActivity did not unpack)"
else
  echo "  (no custom pack in this build — nothing to wait for)"
fi

say "4. prove it renders (smoke only — owner banned agent-side visual measurement)"
t0=$(date +%s); booted=0
while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
  grep -aqE 'Setup failed|jak1_assets' "$LOG" 2>/dev/null && die "app shows 'Setup failed' — asset unpack failed"
  rf=$(grep -acE 'A35-RENDER frame=|A42-TFTREE|master-mode=game' "$LOG" 2>/dev/null); rf=${rf:-0}
  if [ "$rf" -ge 8 ] 2>/dev/null; then booted=1; echo "  render markers=$rf after $(( $(date +%s) - t0 ))s -> booted"; break; fi
  sleep 5
done
[ "$booted" -eq 1 ] || die "no render markers within 300s of the pack landing — the build does not boot"

say "4b. crash check (narrow sig pattern; SIGKILL on background pids is NOT our crash)"
CRASH=$(grep -aE "Fatal signal|signal (11|6|4) \(SIG" "$LOG" | head -3)
[ -z "$CRASH" ] || die "crash signature in the boot log: $CRASH"
echo "  ok: no sig11/6/4 in the boot window"

say "4c. focus + smoke capture (screenrecord: screencap is black on the GL surface)"
FOCUS=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  $FOCUS"; echo "$FOCUS" > "$OUT/a28_normal_focus.txt"
case "$FOCUS" in *org.opengoal.gk.jak1*) echo "  ok: jak1 has focus";; *) die "focus is not jak1: $FOCUS";; esac
"$ADB" -s "$S" shell screenrecord --time-limit 16 /sdcard/a28_smoke.mp4 >/dev/null 2>&1 &
SRP=$!; sleep 20; kill -INT $SRP 2>/dev/null || true; wait $SRP 2>/dev/null || true; sleep 3
"$ADB" -s "$S" pull /sdcard/a28_smoke.mp4 "$OUT/a28_normal_smoke.mp4" >/dev/null 2>&1 || echo "  WARN: no mp4 pulled"
"$ADB" -s "$S" shell rm -f /sdcard/a28_smoke.mp4 >/dev/null 2>&1 || true
if [ -s "$OUT/a28_normal_smoke.mp4" ]; then
  ffmpeg -y -ss 8 -i "$OUT/a28_normal_smoke.mp4" -frames:v 1 "$OUT/a28_normal_smoke.png" >/dev/null 2>&1 || echo "  WARN: frame extract failed"
  ls -la "$OUT/a28_normal_smoke.mp4" "$OUT/a28_normal_smoke.png" 2>/dev/null
fi
FOCUS2=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  post-capture $FOCUS2"; echo "$FOCUS2" >> "$OUT/a28_normal_focus.txt"
case "$FOCUS2" in *org.opengoal.gk.jak1*) echo "  ok: still jak1 at end of capture";; *) die "focus lost during capture: $FOCUS2";; esac

say "5. deploy_verify — the exact orchestrator close-gate"
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee "$OUT/a28_deploy_verify.log"
DV=${PIPESTATUS[0]}
[ "$DV" -eq 0 ] || die "deploy_verify exit $DV — see $OUT/a28_deploy_verify.log"

echo
echo "[a28-redeploy] DONE"
echo "  dev Redmi $S  : NORMAL  libgk ${B:0:16} (audited chain, booted, packs landed, no crash)"
echo "  owner deliver : CHECKER libgk ${C:0:16} + NORMAL ${B:0:16} (same commit, both in .autoport/dist)"
