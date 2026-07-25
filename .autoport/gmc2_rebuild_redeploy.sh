#!/usr/bin/env bash
# gmc2_rebuild_redeploy.sh — Grecharged-mesh-consolidation attempt-2 CLOSE-GATE fix.
#
# ROOT CAUSE of attempt-1 fail (diagnosed, not guessed):
#   build-android/lib/arm64-v8a/libgk.so linked 02:05:17, and its objects for the two
#   TUs below were compiled 02:05:11 / 02:05:16 — but the sources were edited AFTER:
#       common/custom_data/MeshConsolidate.cpp            02:17:11
#       game/graphics/opengl_renderer/loader/Loader.cpp   02:20:08
#   Both landed in work commit 23a2fd2993 (02:26). So the .so on the device was built
#   from a PRE-final source tree => deploy_verify FRESHNESS check failed, AND the device
#   evidence captured at 02:14-02:15 predates the final code.
#   No goal_src file is newer than out/jak1-arm64-full/iso/GAME.CGO (12:45), so the CGO
#   set is unchanged => this is the FAST libgk-ONLY redeploy, not a 30-min consistent
#   CGO rebuild. (See feedback_deploy_verify_freshness_gate.)
#
# This script: hash-before -> rebuild gk -> hash-after (proves whether the late edits
# were substantive) -> assemble APK -> prove build==APK -> install (MIUI recipe, keeps
# app data so device CGOs + custom pack persist).
# It does NOT launch or run deploy_verify — gmc_boot_audit.sh launches (which lets
# LoaderActivity re-unpack any bumped custom pack) and deploy_verify runs after that.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
GMC_SERIAL=eae4df44
GMC_PKG=org.opengoal.gk.jak1
GMC_APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
GMC_SO=build-android/lib/arm64-v8a/libgk.so
OUT=.autoport/reports/Grecharged-mesh-consolidation/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gmc2 FAIL] $*" >&2; exit 1; }

say "0. BEFORE: record the stale artifacts so the rebuild delta is measurable"
[ -f "$GMC_SO" ] || die "no libgk.so at $GMC_SO"
SO_BEFORE=$(sha256sum "$GMC_SO" | cut -d' ' -f1)
O_MC=build-android/android/CMakeFiles/gk.dir/__/common/custom_data/MeshConsolidate.cpp.o
O_LD=build-android/android/CMakeFiles/gk.dir/__/game/graphics/opengl_renderer/loader/Loader.cpp.o
MC_BEFORE=$(sha256sum "$O_MC" 2>/dev/null | cut -d' ' -f1)
LD_BEFORE=$(sha256sum "$O_LD" 2>/dev/null | cut -d' ' -f1)
echo "  libgk.so          BEFORE mtime=$(date -d @$(stat -c %Y "$GMC_SO") +%T) sha=${SO_BEFORE:0:16}"
echo "  MeshConsolidate.o BEFORE mtime=$(stat -c %y "$O_MC" 2>/dev/null | cut -d' ' -f2 | cut -d. -f1) sha=${MC_BEFORE:0:16}"
echo "  Loader.o          BEFORE mtime=$(stat -c %y "$O_LD" 2>/dev/null | cut -d' ' -f2 | cut -d. -f1) sha=${LD_BEFORE:0:16}"

say "1. rebuild gk (incremental: ninja header/source dep tracking recompiles the 2 stale TUs)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tee "$OUT/android-build-attempt2.log" | tail -12
grep -qE 'Linking CXX shared library lib/arm64-v8a/libgk.so' "$OUT/android-build-attempt2.log" \
  || die "libgk.so was not relinked — build produced no link step (see $OUT/android-build-attempt2.log)"
grep -qiE '\berror\b|FAILED:' "$OUT/android-build-attempt2.log" && die "build reported errors"

say "2. AFTER: prove the rebuild actually changed the binary (were the late edits substantive?)"
SO_AFTER=$(sha256sum "$GMC_SO" | cut -d' ' -f1)
MC_AFTER=$(sha256sum "$O_MC" | cut -d' ' -f1)
LD_AFTER=$(sha256sum "$O_LD" | cut -d' ' -f1)
echo "  libgk.so          AFTER mtime=$(date -d @$(stat -c %Y "$GMC_SO") +%T) sha=${SO_AFTER:0:16}"
echo "  MeshConsolidate.o AFTER sha=${MC_AFTER:0:16}  changed=$([ "$MC_BEFORE" != "$MC_AFTER" ] && echo YES || echo no)"
echo "  Loader.o          AFTER sha=${LD_AFTER:0:16}  changed=$([ "$LD_BEFORE" != "$LD_AFTER" ] && echo YES || echo no)"
echo "  libgk.so changed=$([ "$SO_BEFORE" != "$SO_AFTER" ] && echo YES || echo no)"
{
  echo "STALE-BUILD DELTA (attempt-1 close-gate root cause, measured)"
  echo "  MeshConsolidate.cpp.o  $MC_BEFORE -> $MC_AFTER  changed=$([ "$MC_BEFORE" != "$MC_AFTER" ] && echo YES || echo no)"
  echo "  Loader.cpp.o           $LD_BEFORE -> $LD_AFTER  changed=$([ "$LD_BEFORE" != "$LD_AFTER" ] && echo YES || echo no)"
  echo "  libgk.so               $SO_BEFORE -> $SO_AFTER  changed=$([ "$SO_BEFORE" != "$SO_AFTER" ] && echo YES || echo no)"
} > "$OUT/stale-build-delta.txt"

say "3. FRESHNESS re-check (the exact deploy_verify check-1 predicate)"
SO_MTIME=$(stat -c %Y "$GMC_SO")
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
echo "  libgk.so=$(date -d @$SO_MTIME +%T)  newest_src=$(date -d @$NEWEST_SRC +%T)"
[ "$SO_MTIME" -ge "$NEWEST_SRC" ] || die "STILL stale: newest source is $(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -newer "$GMC_SO" -print | head -3 | tr '\n' ' ')"
echo "  ok: freshness predicate satisfied"

say "4. assemble APK (bundles fresh libgk + unchanged CGOs + custom pack)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$GMC_APK" ] || die "APK not produced at $GMC_APK"

say "5. chain part 1: build libgk == APK-bundled libgk"
A=$(unzip -p "$GMC_APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
echo "  build=$SO_AFTER"; echo "  apk  =$A"
[ "$SO_AFTER" = "$A" ] || die "APK bundled a STALE libgk — assemble did not pick up the fresh .so"

say "6. gradle must not have re-staled the freshness predicate (it writes under android/)"
SO_MTIME2=$(stat -c %Y "$GMC_SO")
NEWEST_SRC2=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
if [ "$SO_MTIME2" -lt "$NEWEST_SRC2" ]; then
  echo "  WARN gradle wrote a newer scanned source:"
  find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -newer "$GMC_SO" -printf '    %T+ %p\n' | head -5
  die "post-assemble staleness — the gate would fail again"
fi
echo "  ok: still fresh after assemble"

say "7. install on $GMC_SERIAL (MIUI unblock recipe; -r keeps app data => device CGOs + pack persist)"
"$ADB" -s "$GMC_SERIAL" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"$ADB" -s "$GMC_SERIAL" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
TEMP=$("$ADB" -s "$GMC_SERIAL" shell dumpsys battery 2>/dev/null | grep -i temperature | grep -oE '[0-9]+' | head -1)
[ -n "$TEMP" ] && echo "  device temp=$((TEMP/10))C"
"$ADB" -s "$GMC_SERIAL" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
"$ADB" -s "$GMC_SERIAL" shell pm trim-caches 999G 2>/dev/null || true
"$ADB" -s "$GMC_SERIAL" install -r -d -t -i com.android.vending "$GMC_APK" 2>&1 | tail -3 || die "apk install failed"

say "8. chain part 2: APK == DEVICE libgk"
DP=$("$ADB" -s "$GMC_SERIAL" shell pm path "$GMC_PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || die "package not installed on device (if lsusb still shows the phone: adb kill-server && adb start-server)"
mkdir -p .autoport/tmp
TMPD=$(mktemp -d .autoport/tmp/gmc2.XXXXXX); trap "rm -rf $TMPD" EXIT
"$ADB" -s "$GMC_SERIAL" pull "$DP" "$TMPD/dev.apk" >/dev/null 2>&1 || die "could not pull device APK"
D=$(unzip -p "$TMPD/dev.apk" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
echo "  device=$D"
[ "$A" = "$D" ] || die "APK != DEVICE libgk — stale install"
echo "  ok: chain build==APK==device (${D:0:16})"

echo
echo "[gmc2] REBUILD+INSTALL DONE. Next: gmc_boot_audit.sh (launch, re-unpack pack, capture), then deploy_verify.sh"
