#!/usr/bin/env bash
# Gecho-pool capture 3: arm the code-band write probe (debug.opengoal.echo.oob=1)
# to NAME the mips2c builder that scatters float writes into the kernel/engine
# code bands during the misty intro cinematic (the unified root: crash + pool drop).
# Rebuilds libgk (probe added), deploys, runs new-game (warp cleared), harvests
# GECHO-OOB frames and addr2line's them against the unstripped libgk.so.
#   Usage: bash .autoport/Gecho_capture3.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SO=build-android/lib/arm64-v8a/libgk.so
RUN="${1:-102}"
A2L=$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-addr2line 2>/dev/null | head -1)
say(){ echo; echo "######## $* ########"; }
die(){ echo "[Gecho-cap3 FAIL] $*" >&2; exit 1; }

say "1. build libgk (probe) + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f "$SO" ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install + restore known-good CGOs + deploy_verify"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "apk install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -2 || die "restore failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -3 || die "deploy_verify failed"

say "3. props: CLEAR warp/census, ARM echo.oob; gecho gen/merc OFF (clean log)"
$ADB -s $S shell setprop debug.opengoal.f1.warp 0
$ADB -s $S shell setprop debug.opengoal.f1.census 0
$ADB -s $S shell setprop debug.opengoal.gecho.gen 0
$ADB -s $S shell setprop debug.opengoal.gecho.merc 0
$ADB -s $S shell setprop debug.opengoal.echo.oob 1
for p in debug.opengoal.f1.warp debug.opengoal.echo.oob; do echo "  $p=$($ADB -s $S shell getprop $p|tr -d '\r')"; done

say "4. drive NEW-GAME -> intro cinematic (no warp)"
FLOW=newgame bash .autoport/f1d_run.sh "$RUN" skip || echo "  (f1d returned $?)"

L=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
say "5. HARVEST (log $L, $(wc -l <"$L" 2>/dev/null||echo 0) lines)"
echo "--- GECHO-OOB armed? ---"; grep -ac 'GECHO-OOB armed' "$L"
echo "--- A37-CSP canary stomp (engine band) ---"; grep -aE 'A37-CSP (canary armed|CANARY-STOMP)' "$L" | head
echo "--- crash ---"; grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest' "$L" | head -4
echo "--- level sequence ---"; grep -aoE 'Displaying level [a-z0-9]+ ?\[[a-z-]+\]' "$L" | uniq -c
echo "--- GECHO-OOB lines (the scatter writes + frames) ---"
grep -a 'GECHO-OOB #' "$L" | sed -E 's/^.*GECHO-OOB/GECHO-OOB/' | sort -u | head -40

say "6. addr2line the distinct frame offsets -> name the scattering builder"
if [ -n "$A2L" ] && [ -f "$SO" ]; then
  OFFS=$(grep -a 'GECHO-OOB #' "$L" | grep -oE '0x[0-9a-f]+' | sort -u | head -60)
  echo "  (using $A2L on $SO)"
  for o in $OFFS; do
    fn=$("$A2L" -f -C -e "$SO" "$o" 2>/dev/null | tr '\n' ' ')
    echo "    $o -> $fn"
  done
else
  echo "  addr2line not found ($A2L) or no libgk; frames are libgk-relative offsets above"
fi
say "Gecho-capture3 DONE (run $RUN)"
