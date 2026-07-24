#!/usr/bin/env bash
# gpbrf_plate_ab.sh — SUPERVISOR LIVE A/B FIX round (2026-07-24).
#
# The supervisor proved on the owner's Honor that the ground is SMOOTH at
# debug.opengoal.pbr.relief=0 and grows HARD BRIGHTNESS PLATES at relief=2.5, i.e. the plates are
# created by the NORMAL-MAP APPLICATION and scale with relief. Root cause found offline:
#   (a) every shipped _normal map carries a non-zero DC (mean surface gradient) — a CONSTANT TILT
#       of the whole material, x7.5 at relief 2.5 (leafyground = 61 deg), which re-aims mapped
#       regions relative to their unmapped neighbours (only 8 of 716 village1 bindings have maps);
#   (b) each chunk decodes that tilt in ITS OWN UV frame — measured over the welded cross-chunk
#       vertex groups: 40.2% of pairs rotated >30 deg, 27% outright MIRRORED;
#   (c) the macro lit/shadow terminator ran off the normal-MAPPED normal through a near-binary
#       smoothstep, so the tilt could flip a whole region between the lit and shadow multiplier.
# Fixes (tfrag3.frag + LoaderStages + PbrDrawBinder), each with an A/B killswitch BIT so this
# script can restore the exact old behaviour LIVE, in the SAME BUILD, at the SAME vantage:
#   8192 = DC removal off   16384 = terminator back on Nm   32768 = per-chunk UV frame back
# LEGACY = 8192|16384|32768 = 57344.
#
# Protocol: ONE boot at the owner's vantage, TOD frozen at noon, full PBR stack ON, then a 4-cell
# LIVE matrix (props are re-read every frame): {LEGACY, FIXED} x {relief 0, relief 2.5}.
# The gate is the owner's own criterion, measured: relief 0 -> 2.5 must change SURFACE DETAIL
# (high-frequency) and NOT flat brightness patches (low-frequency).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/plate_ab; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"                                   # noon: baked stable AND PBR visible
WARP_POS="${WARP_POS:--112.0 42.0 205.0}"            # owner vantage (his pos_dump: -111.98 41.96 204.99)
CONT="${CONT:-village1-hut}"
LEGACY=57344
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo; echo "######## $* ########"; }
die(){ echo "[plate-ab FAIL] $*" >&2; exit 1; }
fg_require(){ local f; f=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  echo "  focus: $f"; echo "$f" > "$OUT/focus.txt"
  case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }

case "${1:?stage (build|boot|matrix|metrics|cleanup|all)}" in

build|all)
  say "0. adb server refresh (wedged daemon => false 'package not installed')"
  "$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
  timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

  say "1. build android libgk (shaders are compiled INTO the .so via shaders_android_blob.h)"
  cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
  [ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
  # Freshness: the three fix markers must be present in the shipped binary.
  for M in u_pbr_normal_dc stable_frame "pbr normal DC"; do
    C=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c -- "$M")
    echo "  marker '$M' = $C"
    [ "$C" -gt 0 ] || die "libgk missing marker '$M' (stale build — the fix is not in the .so)"
  done

  say "2. assemble APK + sha match (stale gradle cache is a known false-pass)"
  ( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
  BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
  ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
  echo "  libgk sha build=$BSHA apk=$ASHA"
  [ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk"

  say "3. install + deploy_verify"
  timeout 30 adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 30 adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
  timeout 30 adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  timeout 30 adb shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
  timeout 60 adb shell pm trim-caches 999G 2>/dev/null || true
  timeout 300 adb install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify failed"
  [ "${1:-}" = "all" ] || exit 0
  ;&

boot)
  say "4. seed the FULL PBR STACK in settings.ini (owner: no more blind captures)"
  # pbr-isolate MUST be 0 (BOTH): the device was left on 2 = PARALLAX ONLY, which seeds
  # u_pbr_bisect with bit 64 and disables the very normal map under test.
  adb shell "cat $SETTINGS_DEV" > /tmp/plate_settings.ini 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' /tmp/plate_settings.ini || die "settings.ini has no pbr-materials? key"
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = 1.5000/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 1/' \
    /tmp/plate_settings.ini
  adb push /tmp/plate_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  BACK=$(adb shell "cat $SETTINGS_DEV" 2>/dev/null | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  case "$BACK" in *"pbr-materials? = #t"*) : ;; *) die "seed readback: pbr-materials? not #t";; esac
  case "$BACK" in *"realtime-lighting? = #t"*) : ;; *) die "seed readback: realtime-lighting? not #t";; esac
  case "$BACK" in *"pbr-isolate = 0"*) : ;; *) die "seed readback: pbr-isolate not 0 (normal map would be bisected OFF)";; esac

  say "5. boot to the owner vantage ($WARP_POS), TOD frozen at $HOUR"
  adb shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  pkill -f "$ADB -s $S logcat" 2>/dev/null || true; sleep 1
  adb shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
  adb logcat -c >/dev/null 2>&1 || true
  adb shell "setprop debug.opengoal.cpad_inject neutral"
  adb shell setprop debug.opengoal.level.warp "$CONT"
  adb shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  adb shell "setprop debug.opengoal.tod.hour '$HOUR'"
  adb shell "setprop debug.opengoal.tod.fast ''"
  adb shell setprop debug.opengoal.renderscale.native 1
  adb shell "setprop debug.opengoal.pbr.kill 0"
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.relief ''"
  adb shell "setprop debug.opengoal.pbr.debug ''"
  adb shell "setprop debug.opengoal.pbr.nstrength ''"
  adb shell "setprop debug.opengoal.mesh.weld 1"
  LOG="$OUT/boot-logcat.log"; : > "$LOG"
  ( timeout 240 adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|pbr binding|pbr normal DC|custom pbr|Fatal signal|GK-DIAG sig=|shader.*[Ee]rror|link.*[Ff]ail|pbr-tess' >> "$LOG" ) 2>/dev/null &
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 300s"
  echo "  spawned at vantage; settling 25s (past the ND logo / level load)"; sleep 25
  fg_require
  say "5b. device-truth: the measured normal-map DC per material (new load-time log)"
  grep -a 'pbr normal DC' "$LOG" | sed 's/^.*pbr normal DC/pbr normal DC/' | sort -u | tee "$OUT/normal_dc.txt"
  [ -s "$OUT/normal_dc.txt" ] || echo "  (no DC lines yet — maps may load later)"
  [ "${1:-}" = "all" ] || exit 0
  ;&

matrix|all)
  say "6. LIVE 4-cell matrix: {LEGACY=$LEGACY, FIXED=0} x {relief 0, relief 2.5}"
  shoot(){ # $1 = label, $2 = bisect, $3 = relief
    adb shell "setprop debug.opengoal.pbr.bisect $2"
    adb shell "setprop debug.opengoal.pbr.relief $3"
    sleep 4
    adb shell rm -f /sdcard/plate_$1.mp4 >/dev/null 2>&1 || true
    adb shell screenrecord --time-limit 4 --bit-rate 12000000 /sdcard/plate_$1.mp4 >/dev/null 2>&1 || die "screenrecord $1"
    sleep 1
    adb pull /sdcard/plate_$1.mp4 "$OUT/$1.mp4" >/dev/null 2>&1 || die "pull $1"
    adb shell rm -f /sdcard/plate_$1.mp4 >/dev/null 2>&1 || true
    rm -rf /tmp/plate_fr; mkdir -p /tmp/plate_fr
    ffmpeg -y -loglevel error -i "$OUT/$1.mp4" -vf fps=1 /tmp/plate_fr/f_%03d.png
    L=$(ls /tmp/plate_fr/f_*.png 2>/dev/null | tail -1); [ -n "$L" ] || die "no frames $1"
    cp "$L" "$OUT/$1.png"; rm -rf /tmp/plate_fr
    echo "  $1 (bisect=$2 relief=$3) -> $OUT/$1.png"
  }
  shoot legacy_r0   $LEGACY 0
  shoot legacy_r25  $LEGACY 2.5
  shoot fixed_r0    0       0
  shoot fixed_r25   0       2.5
  fg_require
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.relief ''"
  say "6b. pull the cross-seam tangent-frame diag (the mandate's UV-frame measurement)"
  adb shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$OUT/pbr_tan_diag.txt" || true
  grep -aE 'tan_frame_|mesh_weld_enabled=|global_cross_chunk' "$OUT/pbr_tan_diag.txt" 2>/dev/null | head -12 || echo "  (diag missing)"
  [ "${1:-}" = "all" ] || exit 0
  ;&

metrics|all)
  say "7. METRICS — the owner's criterion, measured"
  python3 .autoport/gpbrf_plate_metrics.py "$OUT" | tee "$OUT/plate_matrix.txt"
  ;;

cleanup)
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.relief ''"
  adb shell "setprop debug.opengoal.level.warp '\"\"'"
  adb shell "setprop debug.opengoal.level.warp.pos '\"\"'"
  echo "[plate-ab] cleaned"
  ;;
*) die "unknown stage ${1:-}";;
esac
