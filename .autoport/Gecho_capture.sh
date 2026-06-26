#!/usr/bin/env bash
# Gecho-pool capture: build current-HEAD instrumented libgk, deploy, arm BOTH
# gecho census props (gen=Generic2, merc=Merc2), drive NEW-GAME -> intro
# cinematic, harvest the dark-eco-pool draw evidence. Run from repo root.
#   Usage: bash .autoport/Gecho_capture.sh <run#>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
RUN="${1:-100}"
OUT=.autoport/reports/Gecho-pool; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[Gecho-capture FAIL] $*" >&2; exit 1; }

say "1. build current-HEAD android libgk + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install APK + restore known-good CGO baseline + deploy_verify"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -3 || die "restore_knowngood failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -4 || die "deploy_verify failed"

say "3. arm BOTH gecho census props"
$ADB -s $S shell setprop debug.opengoal.gecho.gen 1
$ADB -s $S shell setprop debug.opengoal.gecho.merc 1
echo "  gen=$($ADB -s $S shell getprop debug.opengoal.gecho.gen | tr -d '\r') merc=$($ADB -s $S shell getprop debug.opengoal.gecho.merc | tr -d '\r')"

say "4. drive NEW-GAME -> intro cinematic (skip reinstall; f1d already-installed path)"
FLOW=newgame bash .autoport/f1d_run.sh "$RUN" skip || echo "  (f1d returned $?)"

L=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
say "5. HARVEST  (log: $L, $(wc -l <"$L" 2>/dev/null || echo 0) lines)"
MISTY=$(grep -an 'Displaying level misty' "$L" | head -1 | cut -d: -f1); MISTY=${MISTY:-1}
echo "--- crash signature (if any) ---"
grep -aE 'GK-DIAG sig=|A38-TRIPWIRE (pc|lr) nearest-fn' "$L" | head -6
echo "--- misty displayed at line: $MISTY of $(wc -l <"$L") ---"
echo "--- did pool MODEL ever render (Merc2 or Generic)? ---"
grep -ac 'water-anim-misty-dark-eco-pool' "$L" | sed 's/^/  water-anim-misty-dark-eco-pool lines: /'
echo "--- GECHO-MERC poolish models DURING misty (after line $MISTY) ---"
tail -n +"$MISTY" "$L" | grep -aE 'GECHO-MERC.*poolish=1' | sed -E 's/.*GECHO-MERC //' | sort | uniq -c | head
echo "--- GECHO-GEN buckets DURING misty ---"
tail -n +"$MISTY" "$L" | grep -a 'GECHO-GEN' | sed -E 's/.*GECHO-GEN //; s/ verts=.*//' | sort | uniq -c | head
echo "--- GECHO-DRAW darkeco/eco/water textures DURING misty ---"
tail -n +"$MISTY" "$L" | grep -aiE 'GECHO-DRAW.*(darkeco|environment-darkeco|darkecowater|eco|water)' | sed -E 's/.*GECHO-DRAW //; s/ idx=[0-9]+//; s/ tris=[0-9]+//' | sort | uniq -c | head -20
echo "--- ALL distinct GECHO-DRAW buckets DURING misty ---"
tail -n +"$MISTY" "$L" | grep -aoE 'GECHO-DRAW bucket=[^ ]+ id=[0-9]+' | sort | uniq -c | sort -rn | head
echo "--- misty cinematic models seen in Merc2 (crate-darkeco/darkecocan/sidekick/babak/bonelurker/eichar) ---"
tail -n +"$MISTY" "$L" | grep -aoE 'GECHO-MERC model=[^ ]+' | sort | uniq -c | sort -rn | head -20
echo "--- A37 ripple fallback ---"
grep -aoE 'A37-MIPS2C-FALLBACK ripple[^ ]*' "$L" | sort -u
say "Gecho-capture DONE (run $RUN)"
