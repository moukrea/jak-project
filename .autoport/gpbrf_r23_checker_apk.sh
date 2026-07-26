#!/usr/bin/env bash
# gpbrf_r23_checker_apk.sh — package the CHECKER-DEBUG variant APK alongside the normal one.
#
# OWNER STANDING RULE: the checkerboard is the acceptance test until it is perfect, and the owner
# has NO adb — so every build handed to him must ship a second APK whose pattern is already ON out
# of the box. That is the compile flag OG_PBR_CHECKER_DEBUG, which only moves the DEFAULT of
# pbr_testpattern::mode() (the prop still overrides it either way, so headless A/B is unaffected).
#
# HOW THE APK GETS ITS libgk, and why the obvious approach does NOT work. app/build.gradle.kts
# defines three chained tasks: configureNativeLibs -> buildNativeLibs -> copyNativeLibs, where
# buildNativeLibs literally runs `cmake --build build-android --target gk` and copyNativeLibs then
# copies build-android/lib/arm64-v8a/libgk.so into src/main/jniLibs/arm64-v8a.
# So dropping the checker .so into build-android and assembling CANNOT work: buildNativeLibs sees a
# changed output, RE-LINKS it from the normal object files, and the checker binary is gone before
# copyNativeLibs ever looks at it. (Observed: the APK came out with a third sha — a fresh normal
# link, differing from the previous normal one only by link nondeterminism.)
# THE WORKING APPROACH, which is also the one the gradle file's own comment recommends: keep the
# checker configure in its OWN build dir (build-android-checker, -DOG_PBR_CHECKER_DEBUG=ON), place
# its .so directly into jniLibs, and assemble with the three native tasks EXCLUDED so nothing
# rebuilds or overwrites it. The normal APK is then re-assembled the ordinary way, letting gradle
# rebuild, so it is produced by exactly the standard path.
#
# The restore is in an EXIT trap: an interrupted run must never leave the checker .so sitting in
# jniLibs, because the next ordinary assemble would silently ship a checker build to the device and
# every subsequent measurement would be taken through a checkerboard.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
NORM_SO=build-android/lib/arm64-v8a/libgk.so
CHK_SO=build-android-checker/lib/arm64-v8a/libgk.so
OUTDIR=android/app/build/outputs/apk/jak1/debug
APK=$OUTDIR/app-jak1-debug.apk
# NOT in $OUTDIR: gradle's package task CLEANS its own output directory, so a renamed APK left
# there is deleted by the very next assemble (observed — the checker APK vanished during the normal
# re-assemble). Park it outside anything gradle manages.
DIST=.autoport/dist; mkdir -p "$DIST"
CHK_APK=$DIST/app-jak1-CHECKER-DEBUG.apk
BAK=$(mktemp -u /tmp/libgk_normal_XXXX.so)

die(){ echo "[checker-apk FAIL] $*" >&2; exit 1; }
restore(){
  if [ -f "$BAK" ]; then
    cp -p "$BAK" "$NORM_SO" && echo "  restored normal libgk into build-android"
    rm -f "$BAK"
  fi
}
trap restore EXIT

[ -f "$NORM_SO" ] || die "no normal libgk at $NORM_SO"
# SUPERVISOR FIX 2026-07-26: this script used to REUSE whatever libgk was already sitting in
# build-android-checker. A shader edited after the last checker build therefore shipped a stale
# checker APK while the normal APK was fresh — the exact stale-artifact trap, caught by the owner.
# Always rebuild the checker variant before packaging it.
cmake --build build-android-checker --target gk -j"$(nproc)" >/dev/null 2>&1 \
  || die "checker libgk rebuild failed (build-android-checker)"
[ -f "$CHK_SO" ]  || die "no checker libgk at $CHK_SO — build build-android-checker first"

NSHA=$(sha256sum "$NORM_SO" | cut -d' ' -f1)
CSHA=$(sha256sum "$CHK_SO"  | cut -d' ' -f1)
echo "  normal  libgk ${NSHA:0:16}"
echo "  checker libgk ${CSHA:0:16}"
[ "$NSHA" != "$CSHA" ] || die "checker libgk is byte-identical to the normal one — the define did not take"

# The define must be visible at INSTRUCTION level, not merely in a cmake cache: prove the checker
# binary stores a literal 1 as mode()'s default where the normal binary does not.
OD=$(ls "$HOME"/Android/android-ndk-*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump 2>/dev/null | head -1)
if [ -x "$OD" ]; then
  for pair in "$NORM_SO:normal" "$CHK_SO:checker"; do
    so=${pair%%:*}; tag=${pair##*:}
    a=$(nm -C --defined-only "$so" | awk '/pbr_testpattern::mode\(\)$/{print $1}')
    echo "  --- $tag pbr_testpattern::mode() @ 0x$a ---"
    "$OD" -d --start-address=0x"$a" --stop-address=$((0x$a + 0x2c)) "$so" 2>/dev/null | tail -3
  done
fi

JNI=android/app/src/main/jniLibs/arm64-v8a/libgk.so
cp -p "$JNI" "$BAK" || die "backup failed"
restore(){
  if [ -f "$BAK" ]; then
    cp -p "$BAK" "$JNI" && echo "  restored the pre-run libgk into jniLibs"
    rm -f "$BAK"
  fi
}

echo; echo "  == assembling CHECKER-DEBUG APK (native tasks excluded so nothing relinks) =="
cp "$CHK_SO" "$JNI" || die "checker -> jniLibs failed"
( cd android && ./gradlew assembleJak1Debug \
    -x configureNativeLibs -x buildNativeLibs -x copyNativeLibs 2>&1 | tail -3 ) \
  || die "gradle (checker) failed"
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
[ "$A" = "$CSHA" ] || die "checker APK bundled ${A:0:16}, expected ${CSHA:0:16}"
mv "$APK" "$CHK_APK" || die "rename failed"
echo "  -> $CHK_APK  (libgk ${CSHA:0:16})"

echo; echo "  == re-assembling the NORMAL APK =="
restore
trap - EXIT
# ROUND 26 — SECOND STALENESS HOLE, distinct from the one 674e0ed715 fixed (which was the CHECKER
# half reusing an existing .so). The comment this line replaced said "gradle rebuilds + copies".
# IT DOES NOT. gradle does not track the C++/GLSL sources, so `buildNativeLibs` is judged
# up-to-date and `cmake --build build-android` never runs: observed this round as
# "39 actionable tasks: 6 executed, 33 up-to-date" in 15 s, leaving the normal libgk at a
# 100-minute-old link with `strings libgk.so | grep -c pom_carve` == 0 while the checker half was
# correct. The normal APK would then ship silently stale — the exact class of defect that sank
# attempt 22 (deploy_verify FRESHNESS). Build it explicitly, the same way line ~53 does for the
# checker half, and let gradle only package.
cmake --build build-android --target gk -j"$(nproc)" >/dev/null 2>&1 \
  || die "normal libgk rebuild failed (build-android)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -3 ) || die "gradle (normal) failed"
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
J=$(sha256sum "$JNI" | cut -d' ' -f1)
[ "$A" = "$J" ] || die "normal APK ${A:0:16} != jniLibs ${J:0:16}"
[ "$A" != "$CSHA" ] || die "normal APK still carries the CHECKER libgk — restore failed"
# FRESHNESS GATE on both halves: a libgk older than the newest renderer source is stale by
# definition, and neither half may ship that way.
NEWEST_SRC=$(find game/graphics game/kernel android/src -type f \
  \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
     -o -name '*.tesc' -o -name '*.tese' \) -newer "$NORM_SO" -print -quit 2>/dev/null)
[ -z "$NEWEST_SRC" ] || die "normal libgk is OLDER than $NEWEST_SRC — stale build, refusing to ship"
NEWEST_SRC=$(find game/graphics game/kernel android/src -type f \
  \( -name '*.cpp' -o -name '*.h' -o -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \
     -o -name '*.tesc' -o -name '*.tese' \) -newer "$CHK_SO" -print -quit 2>/dev/null)
[ -z "$NEWEST_SRC" ] || die "checker libgk is OLDER than $NEWEST_SRC — stale build, refusing to ship"
NSHA=$A
echo "  -> $APK  (libgk ${NSHA:0:16})"

echo
echo "CHECKER-APK: PASS"
echo "  normal  $APK              libgk ${NSHA:0:16}"
echo "  checker $CHK_APK  libgk ${CSHA:0:16}"
[ -f "$CHK_APK" ] || die "checker APK disappeared from $CHK_APK"
FINAL=$(unzip -p "$CHK_APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
[ "$FINAL" = "$CSHA" ] || die "parked checker APK bundles ${FINAL:0:16}, expected ${CSHA:0:16}"
echo "  re-verified AFTER the normal re-assemble: checker APK still bundles ${FINAL:0:16}"
ls -la "$APK" "$CHK_APK"
