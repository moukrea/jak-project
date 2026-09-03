#!/usr/bin/env bash
# Gecho-pool BEFORE capture: reach the misty NEW-GAME intro cinematic via the
# PROVEN Gd1/Gcine-camfov nav (start -> down x2/up x2 -> X NEW GAME -> down x4 -> X),
# which reached the misty cutscene CRASH-FREE on 2026-06-21. Arm ONLY gecho.gen=1
# (a pure-printf generic-bucket census; cannot itself crash). Goal: determine in
# ONE run whether (a) the cinematic plays with the dark-eco pool ABSENT (bucket
# l1-tfrag-generic id=18 has 0 darkeco draws) = BEFORE confirmed, or (b) the
# current build crashes at the misty VIS swap.
#   Usage: bash .autoport/Gecho_before.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
INJECT="/data/data/$PKG/files/cpad_inject"
RUN="${1:-110}"
RDIR=.autoport/reports/Gecho-pool; mkdir -p "$RDIR"
L="$RDIR/before-run${RUN}.log"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[Gecho-before FAIL] $*" >&2; exit 1; }
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
inject(){ printf '%s' "$1" | $ADB -s $S shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject: '$1'"; }
clear_inject(){ inject ""; }
cap(){ $ADB -s $S shell screencap -p /sdcard/eb.png >/dev/null 2>&1 || true; $ADB -s $S pull /sdcard/eb.png "$RDIR/before-run${RUN}-$1.png" >/dev/null 2>&1 || true;
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "    [$1] focus=${foc##*mCurrentFocus=} ($(stat -c %s "$RDIR/before-run${RUN}-$1.png" 2>/dev/null||echo 0)B)"; }

say "1. build libgk + assemble APK"
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

say "3. props: gecho.gen ON; all other gecho/echo/f1 instrumentation OFF"
for kv in gecho.gen:1 gecho.merc:0 echo.intro:0 echo.oob:0 f1.warp:0 f1.census:0 a40.dproc:0 a38.tripwire:0; do
  $ADB -s $S shell setprop "debug.opengoal.${kv%:*}" "${kv#*:}"
done
for p in gecho.gen echo.intro f1.warp; do echo "  $p=$($ADB -s $S shell getprop debug.opengoal.$p|tr -d '\r')"; done

say "4. launch + PROVEN Gd1 nav to NEW GAME intro cinematic"
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell am force-stop "$p" >/dev/null 2>&1 || true; $ADB -s $S shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done
$ADB -s $S shell svc power stayon true 2>/dev/null || true
$ADB -s $S shell am force-stop "$PKG" 2>/dev/null || true
clear_inject
$ADB -s $S logcat -G 64M 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
$ADB -s $S logcat -v threadtime > "$L" 2>&1 &
LOGCAT_PID=$!
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  warmup 40s (title flythrough settles)"; sleep 40; cap "01-title"
echo "  START -> progress menu"; inject "start"; sleep 1.2; clear_inject; sleep 4; cap "02-menu"
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5; cap "03-newgame-sel"
echo "  X (NEW GAME) -> save-file screen"; inject "x"; sleep 0.6; clear_inject; sleep 3; cap "04-savefile"
echo "  down x4 -> CONTINUE WITHOUT SAVING"; for i in 1 2 3 4; do inject "down"; sleep 0.4; clear_inject; sleep 1; done; cap "05-continue-sel"
echo "  X (start new game)"; inject "x"; sleep 0.6; clear_inject; sleep 6; cap "06-newgame-start"
CONFIRM_OFS=$(wc -l < "$L" 2>/dev/null || echo 0); echo "  post-confirm log offset: $CONFIRM_OFS"

say "5. cinematic window (~5min) — watch misty, pool draws, crash"
MISTY=""
for t in 30 60 90 120 150 180 210 240 270 300; do
  sleep 30; cap "07-cine-t${t}"
  mis=$(grep -ac 'Displaying level misty' "$L" 2>/dev/null||echo 0)
  swap=$(grep -ac 'Swapping in mis VIS' "$L" 2>/dev/null||echo 0)
  gen18=$(grep -ac 'GECHO-GEN.*tfrag-generic' "$L" 2>/dev/null||echo 0)
  dark=$(grep -aiEc 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater)' "$L" 2>/dev/null||echo 0)
  sig=$(grep -ac 'GK-DIAG sig=' "$L" 2>/dev/null||echo 0)
  fm=$(grep -aoE 'A35-RENDER frame [0-9]+' "$L" 2>/dev/null|tail -1)
  echo "   t=${t}s misty=$mis vis-swap=$swap gen-tfrag=$gen18 DARKECO=$dark sig=$sig ${fm}"
  [ "${mis:-0}" -ge 1 ] && MISTY=yes
  if [ "${sig:-0}" -ge 1 ]; then echo "   >>> CRASH at t=${t}s"; sleep 2; break; fi
  if [ "${dark:-0}" -ge 1 ]; then echo "   >>> DARKECO POOL DRAW SEEN at t=${t}s"; fi
done
kill ${LOGCAT_PID:-0} 2>/dev/null || true
for p in "${INTERLOPERS[@]}"; do $ADB -s $S shell pm enable "$p" >/dev/null 2>&1 || true; done

say "6. HARVEST ($L = $(wc -l <"$L" 2>/dev/null||echo 0) lines)"
M=$(grep -an 'Displaying level misty' "$L" | head -1 | cut -d: -f1); M=${M:-1}
echo "--- level sequence ---"; grep -aoE 'Displaying level [a-z0-9]+' "$L" | uniq -c
echo "--- crash (if any) ---"; grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest' "$L" | head -6
echo "--- generic buckets that fired post-misty (GECHO-GEN) ---"
tail -n +"$M" "$L" | grep -a 'GECHO-GEN' | sed -E 's/.*GECHO-GEN //; s/ verts=.*//' | sort | uniq -c | head
echo "--- DARKECO/water pool draws post-misty (KEY) ---"
tail -n +"$M" "$L" | grep -aiE 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater|water)' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//' | sort | uniq -c | head -15
echo "--- ALL distinct tfrag-generic bucket-18 draws post-misty ---"
tail -n +"$M" "$L" | grep -aE 'GECHO-DRAW.*tfrag-generic' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//' | sort | uniq -c | head -20
say "Gecho-before DONE (run $RUN) — log $L"
