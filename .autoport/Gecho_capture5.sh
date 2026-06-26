#!/usr/bin/env bash
# Gecho-pool capture 5: reach the misty intro cinematic via the ECHO-INTRO WARP
# (initialize! *game-info* 'game #f "intro-start", direct, NO title-menu nav),
# to test whether the ~36s reset-and-call crash is f1d-navigation-specific. Arms
# the pool census (gecho.gen/merc) to capture the dark-eco pool draws if reached.
#   Usage: bash .autoport/Gecho_capture5.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
RUN="${1:-104}"
RDIR=.autoport/reports; L="$RDIR/F1d-routed-logcat-run${RUN}.log"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[Gecho-cap5 FAIL] $*" >&2; exit 1; }
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)

say "1. build libgk (echo-warp) + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install + restore + deploy_verify"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "3. props: ARM echo.intro (direct intro warp), pool census on, f1.warp OFF, a40.dproc on"
for kv in f1.warp:0 f1.census:0 echo.oob:0 echo.intro:1 gecho.gen:1 gecho.merc:1 a40.dproc:1; do
  $ADB -s $S shell setprop "debug.opengoal.${kv%:*}" "${kv#*:}"
done
for p in echo.intro gecho.gen f1.warp; do echo "  $p=$($ADB -s $S shell getprop debug.opengoal.$p|tr -d '\r')"; done

say "4. launch app (NO menu navigation) + capture logcat ~4min while the intro warp fires"
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell am force-stop "$p" >/dev/null 2>&1 || true; $ADB -s $S shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done
device_stayon_on 2>/dev/null || $ADB -s $S shell svc power stayon true 2>/dev/null || true
$ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
$ADB -s $S logcat -G 32M 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
$ADB -s $S logcat -v threadtime > "$L" 2>&1 &
LOGCAT_PID=$!
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
for t in 30 60 90 120 150 180 210 240; do
  sleep 30
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
  $ADB -s $S shell screencap -p /sdcard/e5.png >/dev/null 2>&1 || true
  $ADB -s $S pull /sdcard/e5.png "$RDIR/Gecho-run${RUN}-t${t}.png" >/dev/null 2>&1 || true
  warp=$(grep -ac 'ECHO-INTRO-WARP' "$L" 2>/dev/null); mis=$(grep -ac 'Displaying level misty' "$L" 2>/dev/null); sig=$(grep -ac 'GK-DIAG sig=' "$L" 2>/dev/null)
  echo "  t=${t}s warp=$warp misty=$mis sig=$sig focus=${foc##*mCurrentFocus=}"
done
kill ${LOGCAT_PID:-0} 2>/dev/null || true
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell pm enable "$p" >/dev/null 2>&1 || true; done

say "5. HARVEST (log $L, $(wc -l <"$L" 2>/dev/null||echo 0) lines)"
echo "--- ECHO-INTRO-WARP fired? ---"; grep -aE 'ECHO-INTRO-WARP' "$L" | head
echo "--- level sequence ---"; grep -aoE 'Displaying level [a-z0-9]+ ?\[[a-z-]+\]' "$L" | uniq -c
echo "--- crash (if any) ---"; grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest' "$L" | head -4
MISTY=$(grep -an 'Displaying level misty' "$L" | head -1 | cut -d: -f1); MISTY=${MISTY:-1}
echo "--- misty at line $MISTY of $(wc -l <"$L") ---"
echo "--- POOL: water-anim-misty-dark-eco-pool seen? ---"; grep -ac 'water-anim-misty-dark-eco-pool' "$L"
echo "--- GECHO-DRAW darkeco/water during misty (KEY) ---"
tail -n +"$MISTY" "$L" | grep -aiE 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater|water)' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//' | sort | uniq -c | head -15
echo "--- GECHO-MERC poolish during misty ---"
tail -n +"$MISTY" "$L" | grep -aE 'GECHO-MERC.*poolish=1' | sed -E 's/.*GECHO-MERC //' | sort | uniq -c | head
echo "--- distinct GECHO-GEN buckets during misty ---"
tail -n +"$MISTY" "$L" | grep -a 'GECHO-GEN' | sed -E 's/.*GECHO-GEN //; s/ verts=.*//' | sort | uniq -c | head
say "Gecho-capture5 DONE (run $RUN)"
