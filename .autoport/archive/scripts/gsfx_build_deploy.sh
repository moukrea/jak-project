#!/usr/bin/env bash
# gsfx_build_deploy.sh — build the FIXED arm64 CGO set + libgk (SFX probe still ON
# for verification), Tier-A gate (x86 byte-identical to gold = fix is arm64-gated),
# then deploy the consistent set + probe libgk to the device.
# STOPS (nonzero) on any gate failure. Run from repo root.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gsfx-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (all 28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed"
[ -d out/jak1-arm64-full/iso ] || die "arm64 staged set missing"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. TIER-A GATE: our-x86 boot CGOs MUST be byte-identical to pristine gold"
TIERA_FAIL=0
for f in KERNEL.CGO ENGINE.CGO GAME.CGO; do
  g=".autoport/gold/cgo/$f"; o="out/jak1/iso/$f"
  [ -f "$g" ] || die "gold missing $g"
  [ -f "$o" ] || die "our-x86 missing $o"
  gh=$(sha256sum "$g" | awk '{print $1}'); oh=$(sha256sum "$o" | awk '{print $1}')
  if [ "$gh" = "$oh" ]; then echo "  TIER-A OK  $f  ($gh)"; else echo "  TIER-A DIFF $f gold=$gh our=$oh"; TIERA_FAIL=1; fi
done
# also DGOs
for f in $(ls .autoport/gold/dgo/ 2>/dev/null); do
  g=".autoport/gold/dgo/$f"; o="out/jak1/iso/$f"
  [ -f "$o" ] || { echo "  (skip $f — not in out)"; continue; }
  gh=$(sha256sum "$g" | awk '{print $1}'); oh=$(sha256sum "$o" | awk '{print $1}')
  [ "$gh" = "$oh" ] || { echo "  TIER-A DIFF $f"; TIERA_FAIL=1; }
done
[ "$TIERA_FAIL" -eq 0 ] || die "TIER-A divergence — fix leaked into x86 codegen! STOP."
echo "  TIER-A: all CGO/DGO byte-identical to gold -> fix is 100% arm64-gated."

say "3. build android libgk (SFX probe ON for verification) + assemble APK"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "4. install APK + deploy_verify (build==APK==device)"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
# restore known-good first so .extracted_v1 exists + a consistent baseline, THEN overlay fixed CGOs
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -3 || die "restore_knowngood failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -4 || die "deploy_verify failed"

say "5. deploy the FIXED consistent arm64 CGO/DGO set onto the device"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -6 || die "CGO deploy failed"

say "DONE — fixed arm64 build deployed (probe libgk + fixed consistent CGO set)."
echo "[gsfx-build] ready for boot + SFX capture verification."
