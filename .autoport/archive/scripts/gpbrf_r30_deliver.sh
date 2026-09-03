#!/usr/bin/env bash
# gpbrf_r30_deliver.sh — ROUND 30: prove the DELIVERY path end to end.
#
# What this round changed and therefore what has to be proven:
#   1. The derived data (26 .fr3 + 26 .meshweld + 3 .grassbake + 28 recharged textures + 11 HUD PNGs)
#      now ships INSIDE the APK's custom pack. The external base pack keeps only the untouched dump.
#   2. One resolver (file_util::resolve_fr3_asset) decides every derived path, package-copy-first, and
#      journals the decision to files/asset_route.txt — readable on a phone with no logcat.
#   3. mesh_consolidate_apply_bake() now prints the PATH it opened plus the md5 of the bytes it read.
#
# The gate is therefore ONE equality: the md5 the RUNTIME logs for village1.meshweld must equal
# `md5sum out/jak1/fr3/village1.meshweld` on the host. That is the check that would have caught rounds
# 28 and 29 two rounds earlier.
#
# Owner rule in force: NO agent-side visual measurement. The device is used only to prove it installs,
# boots, does not crash, lands the packs, and opens the file we shipped.
#
# Usage: .autoport/gpbrf_r30_deliver.sh   [env: ADB, ANDROID_SERIAL]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${ANDROID_SERIAL:-eae4df44}"
PKG=org.opengoal.gk.jak1
GAME=jak1
ACT_LOADER="$PKG/$PKG.LoaderActivity"     # the LAUNCHER alias — sole writer of the custom-pack stamp
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SO=build-android/lib/arm64-v8a/libgk.so
JNI=android/app/src/main/jniLibs/arm64-v8a/libgk.so
PACK="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.zip"
CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
O=.autoport/reports/Grecharged-pbr-realtime-fusion/r30
D=.autoport/reports/Grecharged-pbr-realtime-fusion/device
mkdir -p "$O" "$D"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r30 FAIL] $*" >&2; exit 1; }
A(){ "$ADB" -s "$S" "$@"; }

say "1. build libgk (arm64) from the current tree"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ -f "$SO" ] || die "libgk.so not built"
NEWEST_SRC=$(find game/graphics game/kernel android common goalc -type f \
  \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
     -o -name '*.tesc' -o -name '*.tese' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
SO_T=$(stat -c %Y "$SO")
[ "$SO_T" -ge "$NEWEST_SRC" ] || die "libgk.so older than newest source — the build did not take"
echo "  libgk $(stat -c '%y' "$SO" | cut -c1-19)  sha=$(sha256sum "$SO" | cut -c1-16)"

say "2. libgk really carries the round-30 code (strings, not assumptions)"
for pat in 'asset-route' 'STALE-BUNDLE' 'bake_version=' 'asset_route.txt'; do
  n=$(strings -a "$SO" | grep -cF "$pat")
  echo "  '$pat' strings=$n"
  [ "$n" -gt 0 ] || die "libgk.so has no '$pat' — the round-30 C++ is NOT in this binary"
done

say "3. the custom pack carries the derived data"
[ -f "$PACK" ] || die "no custom pack at $PACK"
PACK_VER=$(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)
N_FR3=$(unzip -Z1 "$PACK" | grep -cE '^fr3/[^/]*\.fr3$')
N_MW=$(unzip -Z1 "$PACK" | grep -cE '^fr3/[^/]*\.meshweld$')
echo "  pack version=$PACK_VER  stock fr3=$N_FR3  sidecars=$N_MW  zip=$(stat -c %s "$PACK")B"
[ "$N_FR3" -eq 26 ] || die "expected 26 stock fr3 members, got $N_FR3 (the structural move did not take)"
[ "$N_MW"  -eq 26 ] || die "expected 26 sidecar members, got $N_MW"
HOST_MW_MD5=$(md5sum out/${GAME}/fr3/village1.meshweld | cut -d' ' -f1)
PACK_MW_MD5=$(unzip -p "$PACK" fr3/village1.meshweld | md5sum | cut -d' ' -f1)
echo "  village1.meshweld host=$HOST_MW_MD5  in-pack=$PACK_MW_MD5"
[ "$HOST_MW_MD5" = "$PACK_MW_MD5" ] || die "the pack carries a DIFFERENT village1.meshweld than out/ — packaging guard bug"

say "4. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
B=$(sha256sum "$SO" | cut -d' ' -f1)
J=$(sha256sum "$JNI" | cut -d' ' -f1)
Aa=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
Pz=$(sha256sum "$PACK" | cut -d' ' -f1)
Pa=$(unzip -p "$APK" "assets/bundle/${GAME}_custom.zip" | sha256sum | cut -d' ' -f1)
echo "  libgk build=${B:0:16} jniLibs=${J:0:16} apk=${Aa:0:16}"
echo "  pack  built=${Pz:0:16} apk=${Pa:0:16}"
echo "  APK size=$(stat -c %s "$APK")B  $(stat -c '%y' "$APK" | cut -c1-19)"
[ "$B" = "$J" ]  || die "jniLibs stale vs build"
[ "$B" = "$Aa" ] || die "APK bundled a STALE libgk"
[ "$Pz" = "$Pa" ] || die "APK bundled a STALE custom pack — this is the round-30 bug class itself"
echo "  ok: build == jniLibs == APK for BOTH the binary and the data"

say "5. device present (lsusb discriminates a wedged adb daemon from an unplugged phone)"
st=$(A get-state 2>/dev/null | tr -d '\r')
if [ "$st" != "device" ]; then
  lsusb | grep -qi 'Xiaomi' && { "$ADB" kill-server >/dev/null 2>&1; sleep 2; "$ADB" start-server >/dev/null 2>&1; sleep 3; }
  st=$(A get-state 2>/dev/null | tr -d '\r')
fi
[ "$st" = "device" ] || die "device $S not available (state=$st)"
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
echo "  free space before install:"; A shell df -h /data/user/0 2>&1 | tail -1

say "6. install (keeps app data; LoaderActivity will re-unpack the moved pack)"
A shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
A shell pm trim-caches 999G 2>/dev/null || true
A install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3
A shell pm path "$PKG" | tee "$O/installed_apk_path.txt"

say "6b. make the two copies DISTINGUISHABLE, so the md5 gate actually proves PRECEDENCE"
# Both copies of village1.meshweld are byte-identical right now (the supervisor pushed the corrected
# sidecars to external storage), so an md5 match on its own would NOT say which file was opened —
# either answer would look identical. From this round on the external copy is inert (the base pack no
# longer ships derived data and the packaged copy wins), so it is safe to give it a distinct
# fingerprint: append one byte, keeping a backup. If precedence works the runtime journals the HOST
# md5; if it regressed to the external copy the journal shows the decoy md5, or a load failure naming
# the external path. Either way the winner is named rather than assumed.
EXT_MW="/storage/emulated/0/OpenGOAL/${GAME}/assets/fr3/village1.meshweld"
EXT_BAK="${EXT_MW}.r30bak"
DECOY=0
restore_decoy(){
  if [ "$DECOY" = 1 ]; then
    A shell "cp -f '$EXT_BAK' '$EXT_MW' && rm -f '$EXT_BAK'" >/dev/null 2>&1 \
      && echo "  [restore] external village1.meshweld put back ($(A shell md5sum "$EXT_MW" 2>/dev/null | awk '{print $1}'))" \
      || echo "  [restore] WARNING could not restore $EXT_MW from $EXT_BAK — do it by hand"
  fi
}
trap restore_decoy EXIT
if A shell "[ -f '$EXT_MW' ]" 2>/dev/null; then
  A shell "cp -f '$EXT_MW' '$EXT_BAK'" >/dev/null 2>&1 || die "could not back up $EXT_MW"
  A shell "printf 'X' >> '$EXT_MW'" >/dev/null 2>&1 || die "could not write the decoy byte"
  DECOY=1
  EXT_MD5=$(A shell md5sum "$EXT_MW" 2>/dev/null | awk '{print $1}')
  EXT_SZ=$(A shell stat -c %s "$EXT_MW" 2>/dev/null | tr -d '\r')
  echo "  external decoy: md5=$EXT_MD5 size=${EXT_SZ}B"
  echo "  packaged/host : md5=$HOST_MW_MD5 size=$(stat -c %s out/${GAME}/fr3/village1.meshweld)B"
  [ "$EXT_MD5" != "$HOST_MW_MD5" ] || die "the decoy did not change the external md5 — the gate would be vacuous"
else
  echo "  no external copy present — precedence is trivially satisfied (there is nothing to lose to)"
fi

say "7. arm the deterministic village1 vantage (no visual measurement — this is just how the level loads)"
A shell setprop debug.opengoal.level.warp village1-hut >/dev/null 2>&1 || true
A shell "setprop debug.opengoal.level.warp.pos '-156.0 34.0 188.0'" >/dev/null 2>&1 || true

say "8. clear the previous journal, then launch through the LAUNCHER (LoaderActivity)"
A shell run-as "$PKG" rm -f files/asset_route.txt files/mesh_audit.txt 2>/dev/null || true
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
sleep 2
A shell am start -n "$ACT_LOADER" >/dev/null 2>&1 || die "am start failed"

say "9. wait for the custom pack to unpack (420 MB — the stamp is written LAST, so it means done)"
STAMP_OK=0
for i in $(seq 1 120); do
  # run-as lands in /data/user/0/<pkg>, so the stamp needs the files/ prefix. Without it this poll
  # times out after 20 min on a perfectly successful unpack.
  cur=$(A shell run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
  if [ "$cur" = "$PACK_VER" ]; then STAMP_OK=1; echo "  stamp=$cur after ~$((i*10))s"; break; fi
  sleep 10
done
[ "$STAMP_OK" = 1 ] || die "custom-pack stamp never reached $PACK_VER (unpack failed or was interrupted)"
A shell run-as "$PKG" du -sm "files/custom/${GAME}" 2>/dev/null | tee "$O/unpacked_size.txt"

say "10. wait for village1 to load and be journalled"
VILL=0
for i in $(seq 1 90); do
  # The remote command must be ONE quoted string: the host shell eats the inner quotes otherwise, the
  # device shell re-splits on the space in 'level=village1 OPENED', and the poll can never match
  # (measured: it burned the full 900 s while the line had been journalled after ~30 s).
  if A shell "run-as $PKG grep -c 'level=village1 OPENED' files/asset_route.txt" 2>/dev/null | grep -qE '^[1-9]'; then
    VILL=1; echo "  village1 sidecar journalled after ~$((i*10))s"; break
  fi
  sleep 10
done

say "11. harvest the evidence"
A shell run-as "$PKG" cat files/asset_route.txt > "$O/device_asset_route.txt" 2>/dev/null || true
A shell run-as "$PKG" cat files/mesh_audit.txt > "$O/device_mesh_audit.txt" 2>/dev/null || true
A shell dumpsys window | grep -i mCurrentFocus | tee "$O/focus.txt"
A logcat -d -v time > "$O/logcat.txt" 2>/dev/null || true
grep -aiE 'asset-route|mesh-consolidate|STALE-BUNDLE' "$O/logcat.txt" > "$O/logcat_route.txt" 2>/dev/null || true
echo "  free space after install:"; A shell df -h /data/user/0 2>&1 | tail -1 | tee "$O/df_after.txt"
# screenrecord: screencap goes black on the GL surface, so record and extract a frame
A shell screenrecord --time-limit 8 /sdcard/r30_smoke.mp4 >/dev/null 2>&1 || true
A pull /sdcard/r30_smoke.mp4 "$D/r30_delivery_smoke.mp4" >/dev/null 2>&1 || true
A shell rm -f /sdcard/r30_smoke.mp4 >/dev/null 2>&1 || true
# No -sseof: screenrecord on a GL surface writes very few frames (measured: 4 frames over 6.5 s), so
# seeking to the last 2 s finds nothing and ffmpeg exits 0 having written no file. Take the first frame.
if [ -f "$D/r30_delivery_smoke.mp4" ]; then
  ffmpeg -y -loglevel error -i "$D/r30_delivery_smoke.mp4" -frames:v 1 "$D/r30_delivery_smoke.png" >/dev/null 2>&1 || true
  [ -s "$D/r30_delivery_smoke.png" ] || echo "  WARNING: no still extracted from the recording"
fi

say "12. THE GATE: the md5 the RUNTIME logged == the md5 on the host"
echo "  host  md5(out/${GAME}/fr3/village1.meshweld) = $HOST_MW_MD5"
DEV_LINE=$(grep -a 'level=village1 OPENED' "$O/device_asset_route.txt" 2>/dev/null | tail -1)
echo "  device journal line: ${DEV_LINE:-<none>}"
DEV_MD5=$(printf '%s' "$DEV_LINE" | grep -oE 'md5=[0-9a-f]{32}' | head -1 | cut -d= -f2)
ROUTE_LINE=$(grep -a 'village1.meshweld ->' "$O/device_asset_route.txt" 2>/dev/null | tail -1)
echo "  route line: ${ROUTE_LINE:-<none>}"
if [ -z "$DEV_MD5" ]; then
  echo "  RESULT: village1 sidecar was NOT opened in this run (VILL=$VILL) — see $O/device_asset_route.txt"
  exit 3
fi
[ "$DEV_MD5" = "$HOST_MW_MD5" ] || die "MD5 MISMATCH: runtime opened $DEV_MD5, host has $HOST_MW_MD5"
case "$ROUTE_LINE" in
  *"(custom-pack)"*) echo "  precedence: the APK's packaged copy WON (custom-pack)";;
  *) echo "  WARNING: village1.meshweld did NOT resolve to the custom pack — route says: $ROUTE_LINE";;
esac
if [ "$DECOY" = 1 ]; then
  [ "$DEV_MD5" != "${EXT_MD5:-}" ] \
    || die "the runtime opened the EXTERNAL decoy ($DEV_MD5) — precedence is NOT working"
  echo "  discriminator: the external decoy ($EXT_MD5) was NOT what the runtime read — precedence proven,"
  echo "                 not inferred from an md5 that both copies happened to share"
fi
echo
echo "RESULT: OK — runtime-opened md5 == host md5 == in-pack md5 = $DEV_MD5"
