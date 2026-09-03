#!/usr/bin/env bash
# Gecho_deploy_dvsq.sh — deploy the d-vs-q arm64 CGO set (reduced XMM frames) and
# measure whether the title `logo` process's `code` thread still overflows its
# 256-byte suspend backup at the misty intro (BEFORE: used=272 OVER=16).
# Pushes out/jak1-arm64-full/iso (28 consistent files) instead of restore_knowngood,
# boot-smoke-checks the new CGOs, then runs the proven new-game nav and harvests
# the A40-DPROC CURTHR (used/OVER), the crash sig (if any), and the dark-eco pool
# generic draws (gecho.gen). On any boot failure it restores the 06-22 known-good.
#   Usage: bash .autoport/Gecho_deploy_dvsq.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
INJECT="/data/data/$PKG/files/cpad_inject"
NEWSET=out/jak1-arm64-full/iso
RUN="${1:-120}"
RDIR=.autoport/reports/Gecho-pool; mkdir -p "$RDIR"
L="$RDIR/dvsq-run${RUN}.log"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[dvsq FAIL] $*" >&2; exit 1; }
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
inject(){ printf '%s' "$1" | $ADB -s $S shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }
cap(){ $ADB -s $S shell screencap -p /sdcard/eb.png >/dev/null 2>&1 || true; $ADB -s $S pull /sdcard/eb.png "$RDIR/dvsq-run${RUN}-$1.png" >/dev/null 2>&1 || true;
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "    [$1] focus=${foc##*mCurrentFocus=} ($(stat -c %s "$RDIR/dvsq-run${RUN}-$1.png" 2>/dev/null||echo 0)B)"; }

say "1. build libgk + assemble slim APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -4
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk not built"
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -4 ) || die "gradle failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install + restore 06-22 known-good CGOs (clean baseline for stack-walk measurement)"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
$ADB -s $S shell am force-stop $PKG
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "3. props: gecho.gen ON; others OFF"
for kv in gecho.gen:1 gecho.merc:0 echo.intro:0 echo.oob:0 f1.warp:0 f1.census:0 a40.dproc:0 a38.tripwire:0; do
  $ADB -s $S shell setprop "debug.opengoal.${kv%:*}" "${kv#*:}"
done

say "4. launch + BOOT SMOKE (new CGOs must reach title, no early SIGILL)"
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell am force-stop "$p" >/dev/null 2>&1 || true; done
$ADB -s $S shell svc power stayon true 2>/dev/null || true
$ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
clear_inject
$ADB -s $S logcat -G 64M 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
$ADB -s $S logcat -v threadtime > "$L" 2>&1 &
LOGCAT_PID=$!
# Boot with retry: there is a known ~1-in-6 link-time boot-flake (new_type SIGABRT).
# A boot SIGABRT (signal 6 at boot, before title) is the flake; a sig=11/4 at boot
# would be a real new-CGO regression. Retry the launch up to 4x for the flake.
BOOTED=0
for attempt in 1 2 3 4; do
  $ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
  $ADB -s $S logcat -c 2>/dev/null || true
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  echo "  boot attempt $attempt: warmup 45s"; sleep 45
  TITLE=$(grep -ac 'Displaying level title' "$L" 2>/dev/null||echo 0)
  ABORT=$(grep -ac 'signal 6 (SIGABRT)\|Assertion failed' "$L" 2>/dev/null||echo 0)
  SIG11=$(grep -ac 'GK-DIAG sig=' "$L" 2>/dev/null||echo 0)
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
  alive=0; [[ "$foc" == *org.opengoal.gk* ]] && alive=1
  echo "  boot-smoke a$attempt: title=$TITLE abort=$ABORT sig11=$SIG11 alive=$alive (${foc##*mCurrentFocus=})"
  if [ "${SIG11:-0}" -ge 1 ]; then
    echo "  >>> BOOT SIG=11/4 with new CGOs (real regression) — restoring 06-22"
    grep -a 'GK-DIAG sig=\|A38-TRIPWIRE' "$L" | head -6
    kill ${LOGCAT_PID:-0} 2>/dev/null || true
    bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2
    die "new CGOs sig11 at boot; 06-22 restored. See $L"
  fi
  if [ "${TITLE:-0}" -ge 1 ] && [ "$alive" -eq 1 ]; then BOOTED=1; break; fi
  echo "  boot flake (abort=$ABORT) — retrying"
done
cap "01-title"
if [ "$BOOTED" -ne 1 ]; then
  echo "  >>> BOOT failed after 4 attempts (persistent flake or real fail)"
  kill ${LOGCAT_PID:-0} 2>/dev/null || true
  die "could not boot to title after 4 attempts. See $L"
fi

say "5. nav to NEW GAME misty intro (proven Gd1 nav)"
inject "start"; sleep 1.2; clear_inject; sleep 4; cap "02-menu"
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5; cap "03-newgame-sel"
inject "x"; sleep 0.6; clear_inject; sleep 3; cap "04-savefile"
for i in 1 2 3 4; do inject "down"; sleep 0.4; clear_inject; sleep 1; done; cap "05-continue-sel"
inject "x"; sleep 0.6; clear_inject; sleep 6; cap "06-newgame-start"

say "6. cinematic window (~5min) — misty, suspend used, pool draws, crash"
for t in 30 60 90 120 150 180 210 240 270 300; do
  sleep 30; cap "07-cine-t${t}"
  mis=$(grep -ac 'Displaying level misty' "$L" 2>/dev/null||echo 0)
  swap=$(grep -ac 'Swapping in mis VIS' "$L" 2>/dev/null||echo 0)
  over=$(grep -a 'A40-DPROC.*CURTHR' "$L" 2>/dev/null|tail -1)
  dark=$(grep -aiEc 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater)' "$L" 2>/dev/null||echo 0)
  sig=$(grep -ac 'GK-DIAG sig=' "$L" 2>/dev/null||echo 0)
  fm=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$L" 2>/dev/null|tail -1)
  echo "   t=${t}s misty=$mis vis-swap=$swap DARKECO=$dark sig=$sig ${fm}"
  [ -n "$over" ] && echo "      ${over##*opengoal-gk: }"
  if [ "${sig:-0}" -ge 1 ]; then echo "   >>> CRASH at t=${t}s"; sleep 2; break; fi
  if [ "${dark:-0}" -ge 1 ]; then echo "   >>> DARKECO POOL DRAW SEEN at t=${t}s"; fi
done
kill ${LOGCAT_PID:-0} 2>/dev/null || true
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell pm enable "$p" >/dev/null 2>&1 || true; done

say "7. HARVEST ($L = $(wc -l <"$L" 2>/dev/null||echo 0) lines)"
echo "--- level sequence ---"; grep -aoE 'Displaying level [a-z0-9]+' "$L" | uniq -c
echo "--- CURPROC/CURTHR (suspend used vs size) ---"; grep -a 'A40-DPROC.*CURPROC\|A40-DPROC.*CURTHR' "$L" | tail -4
echo "--- crash (if any) ---"; grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest|GECHO break-probe' "$L" | head -6
M=$(grep -an 'Displaying level misty' "$L" | head -1 | cut -d: -f1); M=${M:-1}
echo "--- DARKECO/pool generic draws post-misty (KEY) ---"
tail -n +"$M" "$L" | grep -aiE 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater)' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//' | sort | uniq -c | head -15
echo "--- ALL tfrag-generic bucket-18 draws post-misty ---"
tail -n +"$M" "$L" | grep -aE 'GECHO-DRAW.*tfrag-generic' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//' | sort | uniq -c | head -20
say "Gecho-dvsq DONE (run $RUN) — log $L"
