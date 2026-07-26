#!/usr/bin/env bash
# gpbrf_redeploy_freshbuild.sh — attempt-23 CLOSE-GATE fix.
# Root cause of attempt-22 fail: the Android libgk.so on device was built 18:28,
# BEFORE STEP 5c split-by-UV (TFrag3Data.cpp, committed 18:38) and the pos-dump
# (kmachine.cpp, 18:50) landed => deploy_verify FRESHNESS check failed (stale .so).
# This is a libgk-ONLY change (no goal_src since the 12:45 CGO staging), so we do
# the FAST libgk-only redeploy: rebuild gk -> reassemble APK (same bundled CGOs +
# custom pack) -> reinstall (keeps app data => device CGOs/pack persist) ->
# launch once (re-unpack pack, prove render) -> deploy_verify -> boot proof.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; GAME=jak1
ACT_MAIN="$PKG/org.opengoal.gk.MainActivity"
ACT_LOAD="$PKG/.LoaderActivity"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SO=build-android/lib/arm64-v8a/libgk.so
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf-redeploy FAIL] $*" >&2; exit 1; }

say "0. libgk.so freshness + ogflags"
[ -f "$SO" ] || die "no libgk.so — build first"
SO_MTIME=$(stat -c %Y "$SO")
# ROUND 23: the extension list is part of the FRESHNESS GATE, so a missing extension is a silent
# stale-binary hole, not a cosmetic omission. *.glsl was absent even though round 22 moved the
# entire fused PBR path into pbr_fused/pbr_helpers/pbr_uniforms.glsl — editing the shared chunks and
# nothing else would have passed this gate against a .so built before them. *.tese/*.tesc were the
# same hole for the tessellation tier (it cost round 21 a manual catch). All five now scanned.
NEWEST_SRC=$(find game/graphics game/kernel android common/custom_data -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' -o -name '*.glsl' -o -name '*.tesc' -o -name '*.tese' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
echo "  libgk.so mtime=$(date -d @$SO_MTIME +%H:%M:%S)  newest_src=$(date -d @$NEWEST_SRC +%H:%M:%S)"
[ "$SO_MTIME" -ge "$NEWEST_SRC" ] || die "libgk.so still older than newest source — rebuild did not run"
SO_FLAGS=$(strings "$SO" | grep -m1 '^ogflags:' || true)
echo "  libgk ogflags: ${SO_FLAGS:-<none>}"

say "1. assemble APK (bundles fresh libgk + unchanged CGOs + unchanged custom pack)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced at $APK"

say "2. verify build libgk == APK-bundled libgk (chain part 1)"
B=$(sha256sum "$SO" | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
echo "  build=$B"; echo "  apk  =$A"
[ "$B" = "$A" ] || die "APK bundled a STALE libgk (build!=apk) — assemble did not pick up fresh .so"

say "3. install APK on $S (MIUI unblock recipe)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. launch once (LoaderActivity re-unpacks custom pack; prove render), then settle"
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/redeploy-boot-logcat.log"; : > "$LOG"
( timeout 200 $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|A42-TFTREE|master-mode=game|Setup failed|jak1_assets|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$ACT_MAIN" >/dev/null 2>&1 || \
  $ADB -s $S shell am start -W -n "$ACT_LOAD" >/dev/null 2>&1 || true
t0=$(date +%s); booted=0
while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
  if grep -aqE 'Setup failed|jak1_assets' "$LOG" 2>/dev/null; then die "app shows 'Setup failed' — asset unpack failed"; fi
  if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  WARN crash marker seen"; fi
  rf=$(grep -acE 'A35-RENDER frame=|A42-TFTREE|master-mode=game' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 8 ] 2>/dev/null && { booted=1; echo "  render markers=$rf -> booted"; break; }
  sleep 4
done
kill ${LCP:-0} 2>/dev/null || true
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus=$FOCUS  booted=$booted"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) echo "  WARN focus not jak1 yet (may still be loading)";; esac

say "5. deploy_verify (the exact close-gate check)"
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee "$OUT/redeploy-deploy_verify.log"
DV=${PIPESTATUS[0]}
[ "$DV" -eq 0 ] || die "deploy_verify exit $DV — see $OUT/redeploy-deploy_verify.log"

echo
echo "[gpbrf-redeploy] DONE — fresh libgk (STEP 5c + pos-dump) on device, deploy_verify PASS, booted=$booted."
