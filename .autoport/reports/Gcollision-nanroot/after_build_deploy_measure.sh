#!/usr/bin/env bash
# Gcollision-nanroot AFTER build: rebuild the arm64 CGO set with the fmin/fmax
# codegen fix, deploy fixed CGOs + instrumented libgk, then re-measure the vftoi0
# NaN counter during the same Geyser warp+drive. Expect vftoi0_nan to collapse
# from ~25067 (BEFORE) to ~0 (== x86 oracle), proving fmin/fmax was the NaN root.
#
# Prereqs: build-arm64/goalc/goalc already rebuilt with the IR.cpp fix.
# Usage: bash .autoport/reports/Gcollision-nanroot/after_build_deploy_measure.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gcollision-nanroot
A(){ "$ADB" -s "$S" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > files/cpad_inject'" >/dev/null 2>&1 || true; }
say(){ echo "[after] $*"; }

# 1. full-consistent arm64 CGO build (writes out/jak1-arm64-full/iso, restores x86 oracle)
say "build_arm64_full_consistent (this rebuilds all 28 CGOs with the fmin/fmax fix)..."
bash .autoport/build_arm64_full_consistent.sh || { echo "[after] CGO build FAILED"; exit 1; }

# 2. instrumented libgk (keeps the NANROOT counter for the AFTER measurement)
say "build instrumented libgk..."
cmake --build build-android --target gk -j"$(nproc)" || { echo "[after] libgk build FAILED"; exit 1; }

# 3. package APK + install + deploy_verify (libgk chain)
say "assemble + install APK..."
( cd android && ./gradlew assembleJak1Debug ) || { echo "[after] gradle FAILED"; exit 1; }
APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
A install -r "$APK" || { echo "[after] install FAILED"; exit 1; }
bash .autoport/lib/deploy_verify.sh "$S" || { echo "[after] deploy_verify FAILED"; exit 1; }

# 4. push the 28 fixed CGOs into files/iso_data/jak1 (sha256-verified)
say "push fixed CGOs..."
bash .autoport/Gconsolidate_deploy_cgos.sh || { echo "[after] CGO push FAILED"; exit 1; }

# 5. warp + nanroot + drive, capture dev_after.log
say "warp + drive + measure..."
A shell setprop debug.opengoal.f1.warp 1
A shell setprop debug.opengoal.nanroot 1
A shell setprop debug.opengoal.pad_replay ""
inj ""
A shell am force-stop $PKG; sleep 2
A logcat -c
( A logcat -v time GK_STDOUT:I '*:S' > "$OUT/dev_after.log" 2>&1 ) & LC=$!
trap 'kill $LC 2>/dev/null || true; inj ""; A shell setprop debug.opengoal.nanroot 0 >/dev/null 2>&1 || true; A shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true' EXIT
A shell am start -n $PKG/.LoaderActivity
for i in $(seq 1 60); do grep -aq "F1-SPAWN" "$OUT/dev_after.log" && break; sleep 2; done
grep -aq "F1-SPAWN" "$OUT/dev_after.log" || echo "[after] WARN: no F1-SPAWN"
sleep 4
# same forward-into-walls drive pattern as BEFORE, ~90s
for pass in 1 2 3 4 5 6; do
  for steer in "" "lx=70" "lx=185" "lx=40" "lx=210"; do
    inj "ly=20 ${steer}"; sleep 1.0
    inj "ly=20 ${steer} x"; sleep 0.7
    inj "ly=20 ${steer}"; sleep 1.2
    inj ""; sleep 0.6
  done
done
inj ""; sleep 4
kill $LC 2>/dev/null || true

echo "== AFTER ANALYSIS =="
echo -n "F1-SPAWN: "; grep -a "F1-SPAWN" "$OUT/dev_after.log" | head -1
echo -n "FIRST-NONFINITE count: "; grep -ac "NANROOT FIRST-NONFINITE" "$OUT/dev_after.log"
echo -n "MAX vftoi0_nan: "; grep -a "NANROOT HEARTBEAT" "$OUT/dev_after.log" | grep -oE 'vftoi0_nan=[0-9]+' | sort -t= -k2 -n | tail -1
echo "last heartbeat:"; grep -a "NANROOT HEARTBEAT" "$OUT/dev_after.log" | tail -1
echo -n "foreground: "; A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PKG"
echo "[after] DONE (BEFORE max was 25067; expect AFTER ~0)"
