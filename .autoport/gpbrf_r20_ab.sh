#!/usr/bin/env bash
# gpbrf_r20_ab.sh — ROUND 20 device A/B: the owner's CHECKERBOARD verification, in-build, plus the
# real-material ground delta. 2026-07-25.
#
# ROUND 20 fixes a SCALE defect, so every cell here is about scale:
#   * the tessellation sampled the height map in a WORLD projection at a hardcoded 0.5 tiles/m
#     (one tile every 2 m) and displaced by a constant 14336 game units;
#   * the AUTHORED tiles on village1 are 2.28 m (wallplaster) to 7.90 m (leafyground) --
#     measured offline, tools/tess_audit Section U -- so the displaced feature was 1.14x to 3.95x
#     SMALLER than the painted one, per material. "the geometry makes waves but does not follow
#     the height map".
#   * now the lookup rate comes from the material's MEASURED uv density and the amplitude from the
#     height map's MEASURED feature wavelength.
#
# BOOT C = debug.opengoal.pbr.testpattern 1 -> the in-build checkerboard (base + height + normal +
#          roughness) on every material that has PBR maps. This is the owner's method, one prop away.
# BOOT R = testpattern 0 -> the real recharged materials, for the ground-band delta in r19's units.
#
# Within each boot, the LEGACY cell is live: bisect bit 67108864 restores the shipped constants
# (WORLD_TILES_PER_M 0.5 + TESS_DISP_K 14336), so before/after come from the same boot, same vantage,
# same frames -- not from a remembered number.
#
# Cell mechanics (unchanged from r18/r19 and still the thing that makes or breaks a cell):
# TFragment gates the tessellation PROGRAM on the SETTING pbr-displacement == 2; the prop only drives
# the uniform inside it. So settings.ini must carry pbr-displacement = 2 before launch, and then
#     prop displacement=2 -> real tessellation | =1 -> parallax | =0 -> no displacement.
# Every adb logcat is `timeout`-wrapped (harness rule). screencap is black on the GL surface, so
# stills come from screenrecord + ffmpeg with black-frame/empty-mp4 retries.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/r20; mkdir -p "$OUT"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"
WARP_POS="${WARP_POS:--111.98 41.96 204.99}"
CONT="${CONT:-village1-hut}"
RELIEF="${RELIEF:-2.0}"
FPS_WIN="${FPS_WIN:-20}"
LEGACY_BIT=67108864

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r20-ab FAIL] $*" >&2; exit 1; }
kill_loggers(){ pkill -f "$ADB -s $S logcat" 2>/dev/null || true; sleep 1; }

fg_require(){ local f
  f=$(timeout 30 "$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  echo "  focus[$1]: $f"; echo "[$1] $f" >> "$OUT/focus_all.txt"
  case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground at [$1]: $f";; esac
}

pos_now(){ local i v=""
  for i in 1 2 3; do
    v=$(timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pos_dump.txt" 2>/dev/null | tr -d '\r' | head -1)
    case "$v" in *[0-9]*) break;; esac
    sleep 2
  done
  echo "$v"; }

pos_assert(){ local now dist
  now=$(pos_now)
  dist=$(awk -v A="$2" -v B="$now" 'BEGIN{split(A,a," ");split(B,b," ");d=0;for(i=1;i<=3;i++){x=a[i]-b[i];d+=x*x};printf "%.3f", sqrt(d)}')
  echo "  pos[$1]: $now  (drift ${dist} m)"; echo "[$1] $now drift=${dist}m" >> "$OUT/pos_track.txt"
  awk -v d="$dist" -v t="$3" 'BEGIN{exit !(d+0 <= t+0)}' \
    || die "CHARACTER MOVED ${dist} m at [$1] (tolerance $3 m) — capture invalid"
}

cell(){ # $1 = label, $2 = displacement prop, $3 = bisect mask
  local label="$1" disp="$2" bis="${3:-0}"
  say "CELL $label  (displacement=$disp bisect=$bis)"
  timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $bis" || die "setprop bisect"
  local rb rbb
  rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement" | tr -d '\r')
  rbb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.bisect" | tr -d '\r')
  echo "  props readback: displacement=$rb bisect=$rbb"
  echo "$label disp=$disp/$rb bisect=$bis/$rbb" >> "$OUT/props_per_cell.txt"
  [ "$rb" = "$disp" ] || die "prop readback mismatch for $label: $rb"
  [ "$rbb" = "$bis" ] || die "bisect readback mismatch for $label: $rbb"
  sleep 6
  fg_require "$label"

  local try mp4sz L; L=""
  for try in 1 2 3; do
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r20_$label.mp4" >/dev/null 2>&1 || true
    timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 "/sdcard/r20_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 60 "$ADB" -s "$S" pull "/sdcard/r20_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r20_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r20_fr; mkdir -p /tmp/r20_fr
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=1 /tmp/r20_fr/f_%03d.png
    L=$(ls /tmp/r20_fr/f_*.png 2>/dev/null | tail -1)
    if [ -n "$L" ]; then
      if python3 -c "import sys;from PIL import Image;import numpy as np;sys.exit(0 if np.asarray(Image.open('$L').convert('L'),dtype=float).mean()>2.0 else 1)"; then break; fi
      echo "  ($label: BLACK frame, retry $try)"; L=""
    else
      echo "  ($label: empty capture ${mp4sz}B, retry $try)"
    fi
    timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    sleep 12
  done
  [ -n "$L" ] || die "no usable frames $label"
  cp "$L" "$OUT/$label.png"
  echo "  still -> $OUT/$label.png ($(stat -c%s "$OUT/$label.png") B, mp4 ${mp4sz} B)"
  rm -rf /tmp/r20_fr

  if [ "${FPS_WIN}" -gt 0 ]; then
    local T0
    T0=$(timeout 20 "$ADB" -s "$S" shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')
    sleep "$FPS_WIN"
    timeout 90 "$ADB" -s "$S" logcat -d -t "$T0" opengoal-gk:I '*:S' 2>/dev/null \
      | grep -aE 'AOPERF' > "$OUT/fps_$label.txt" || true
    local n mean
    n=$(grep -ac 'AOPERF' "$OUT/fps_$label.txt" || true)
    mean=$(grep -a 'AOPERF' "$OUT/fps_$label.txt" | sed -e 's/.*fps=//' \
        | awk '{f+=$1; n++} END{ if(n>0) printf "%.2f", f/n; else print "nan" }')
    echo "  AOPERF lines=$n mean fps=$mean"
    printf '%-12s lines=%-3s mean_fps=%-7s (disp=%s bisect=%s)\n' "$label" "$n" "$mean" "$disp" "$bis" \
      >> "$OUT/fps_summary.txt"
  fi
  fg_require "${label}_post"
  [ -n "${POSREF:-}" ] && pos_assert "$label" "$POSREF" 0.30
}

seed_settings(){
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > "$OUT/settings_orig.ini" 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' "$OUT/settings_orig.ini" || die "settings.ini has no pbr-materials? key"
  cp "$OUT/settings_orig.ini" /tmp/r20_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e "s/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = ${RELIEF}000/" \
    -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 2/' \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r20_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/r20_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  local BACK
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = 2" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done
}

boot_with(){ # $1 = boot tag, $2 = testpattern prop value
  local tag="$1" tp="$2"
  say "BOOT $tag — testpattern=$tp relief=$RELIEF hour=$HOUR"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.pbr.kill 0" \
           "debug.opengoal.pbr.bisect 0" "debug.opengoal.pbr.displacement 2" \
           "debug.opengoal.pbr.relief $RELIEF" "debug.opengoal.rt.light 1" \
           "debug.opengoal.mesh.weld 1" "debug.opengoal.dump.pos 1" \
           "debug.opengoal.mesh.subdiv -1" "debug.opengoal.pbr.tessseg -1" \
           "debug.opengoal.pbr.testpattern $tp" "debug.opengoal.pbr.testsquares 8" \
           "debug.opengoal.tod.hour $HOUR"; do
    timeout 20 "$ADB" -s "$S" shell "setprop $P" || die "setprop $P"
  done
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.testpattern; getprop debug.opengoal.pbr.testsquares; getprop debug.opengoal.pbr.relief; getprop debug.opengoal.tod.hour; getprop debug.opengoal.level.warp.pos" \
    | tr -d '\r' | tee "$OUT/props_boot_$tag.txt"

  local LOG="$OUT/boot-logcat-$tag.log"; : > "$LOG"
  ( timeout 420 "$ADB" -s "$S" logcat -T 1 -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=|pbr-tess|pbr uv density|pbr height stat|pbr TESTPATTERN|pbr binding|PBR material|shader.*[Ee]rror|link.*[Ff]ail' >> "$LOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 340 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot $tag (see $LOG)"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 340s (boot $tag)"
  echo "  spawned. SETTLING 90 s"
  sleep 90
  fg_require "post_settle_$tag"
  grep -a 'pbr uv density' "$LOG" | tee "$OUT/uvdensity_$tag.txt"
  grep -a 'pbr height stat' "$LOG" | tee "$OUT/heightstat_$tag.txt"
  grep -a 'pbr TESTPATTERN' "$LOG" | head -20 | tee "$OUT/testpattern_$tag.txt"
  grep -a 'pbr-tess' "$LOG" | tail -3 | tee "$OUT/tess_capability_$tag.txt"
  kill_loggers
  POSREF=$(pos_now); export POSREF
  echo "  POSREF[$tag] = $POSREF"
}

case "${1:?stage (deploy|C|R|metrics|all)}" in

deploy|all)
  say "0. assemble + install the round-20 build, then deploy_verify"
  timeout 60 "$ADB" -s "$S" wait-for-device || die "device not present"
  [ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
  for M in "pbr TESTPATTERN" "pbr uv density" "u_pbr_uv_per_m" "u_pbr_height_lambda"; do
    C=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c -- "$M")
    echo "  marker '$M' = $C"
    [ "$C" -gt 0 ] || die "libgk missing marker '$M' (stale build)"
  done
  ( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -4 ) || die "gradle assemble failed"
  BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
  ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
  echo "  libgk sha build=$BSHA apk=$ASHA"; echo "libgk build=$BSHA apk=$ASHA" > "$OUT/sha.txt"
  [ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk"
  timeout 30 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
  timeout 30 "$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  timeout 30 "$ADB" -s "$S" shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
  timeout 60 "$ADB" -s "$S" shell pm trim-caches 999G 2>/dev/null || true
  timeout 300 "$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tee "$OUT/deploy_verify.log" | tail -5
  grep -q 'DEPLOY-VERIFY PASS' "$OUT/deploy_verify.log" || die "deploy_verify did NOT pass"
  : > "$OUT/focus_all.txt"; : > "$OUT/props_per_cell.txt"; : > "$OUT/fps_summary.txt"; : > "$OUT/pos_track.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

C|all)
  seed_settings
  boot_with C 1             # the in-build CHECKERBOARD on every PBR material
  cell C_tess    2 0
  cell C_off     0 0
  cell C_pom     1 0
  cell C_tessleg 2 $LEGACY_BIT   # the shipped constants restored, same boot/vantage
  cell C_tess2   2 0             # repeat of the first cell = this boot's DRIFT FLOOR
  [ "${1:-}" = "all" ] || exit 0
  ;&

R|all)
  seed_settings
  boot_with R 0             # the REAL recharged materials
  cell R_tess    2 0
  cell R_off     0 0
  cell R_pom     1 0
  cell R_tessleg 2 $LEGACY_BIT
  cell R_tess2   2 0
  say "crash sweep"
  timeout 90 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|GK-DIAG sig=|libgk.*SIG' | tail -20 > "$OUT/crash_sweep.txt" || true
  if [ -s "$OUT/crash_sweep.txt" ]; then echo "  !! signals:"; cat "$OUT/crash_sweep.txt"; else echo "  no Fatal signal / GK-DIAG sig= in the buffer"; fi
  echo; cat "$OUT/fps_summary.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

F|all)
  # THE CLEAN CHECKERBOARD TEST. testpattern 3 = the same checker maps with a FLAT base colour, and
  # every cell runs with bisect bit 64 = normal map isolated OFF. The albedo then carries no spatial
  # frequency and the normal map contributes none either, so the only thing that can put a periodic
  # pattern on the ground is the DISPLACED GEOMETRY. Its measured period is therefore the displaced
  # feature's period, with no confound — which the albedo-checker boot could not give, because
  # displacing a surface also moves the texture painted on it.
  #   F_flat = displacement OFF  -> the control: there must be (almost) no pattern at all
  #   F_tess = round-20 law      -> period must equal the PAINTED period measured in boot C
  #   F_leg  = legacy law        -> period must be the old 2.0 m/tile one, i.e. clearly finer
  seed_settings
  boot_with F 3
  cell F_flat 0 64
  cell F_tess 2 64
  cell F_leg  2 $((64 + LEGACY_BIT))
  cell F_tess2 2 64
  [ "${1:-}" = "all" ] || exit 0
  ;&

metrics|all)
  say "CHECKERBOARD PERIOD MATCH (boot C)"
  python3 .autoport/gpbrf_r20_checker.py "$OUT" C_off C_tess C_tessleg | tee "$OUT/checker_metrics.txt"
  say "GROUND BAND DELTA, drift-cancelled (boot R, real materials)"
  python3 .autoport/gpbrf_r20_ground.py "$OUT" | tee "$OUT/ground_metrics.txt"
  ;;
esac
