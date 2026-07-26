#!/usr/bin/env bash
# gpbrf_r21_ab.sh — ROUND 21 device A/B on the Redmi (eae4df44). 2026-07-26.
#
# WHAT IS NEW vs r20 (the cell mechanics are r20's, verbatim — only the CELL SET and the METRICS
# change):
#   * r20 asked "is the displaced feature the right SIZE?".  r21 asks two different questions:
#       (1) ALIGNMENT — does the tessellation sample the height map in the SAME coordinate system
#           the base colour is sampled in?  bisect bit 65536 restores the OLD world-plane
#           projection, so ALIGNED and LEGACY come from the same boot, same vantage, same frames.
#       (2) PARALLAX REVIVAL — the round-21 POM law (feature-scaled depth, grazing FLOOR) against
#           the shipped one (bisect bit 33554432 = 3 cm world clamp + un-faded 0.08 UV cap).
#   * per-cell pull of files/pbr_tan_diag.txt, which now carries the NEW [pom] and [cover] blocks.
#   * FPS is taken from the A35-RENDER render_ms counter (per 60 frames), not only AOPERF fps.
#
# CELLS (one boot, one vantage, props only):
#   OFF        displacement 0  bisect 0           flat reference == the checker ALBEDO
#   T_ALIGNED  displacement 2  bisect 0           NEW aligned tess height lookup (uv3.xy)
#   T_LEGACY   displacement 2  bisect 65536       OLD world-projection lookup
#   P_NEW      displacement 1  bisect 0           NEW feature-scaled POM law
#   P_LEGACY   displacement 1  bisect 33554432    OLD POM caps (3 cm world clamp / 0.08 uv)
#   OFF2       displacement 0  bisect 0           REPEAT of OFF = this boot's DRIFT/NOISE FLOOR
#
# Cell mechanics (unchanged from r18/r19/r20 and still the thing that makes or breaks a cell):
# TFragment gates the tessellation PROGRAM on the SETTING pbr-displacement == 2; the prop only
# drives the uniform inside it. So settings.ini must carry pbr-displacement = 2 BEFORE launch, and
# then prop displacement=2 -> real tessellation | =1 -> parallax | =0 -> no displacement.
# Every adb logcat is `timeout`-wrapped (harness rule). screencap is black on the GL surface, so
# stills come from screenrecord + ffmpeg with black-frame/empty-mp4 retries. Every frame is
# preceded AND followed by an mCurrentFocus assertion.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
export ANDROID_SERIAL=$S
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/r21; mkdir -p "$OUT"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"
WARP_POS="${WARP_POS:--111.98 41.96 204.99}"
CONT="${CONT:-village1-hut}"
RELIEF="${RELIEF:-2.0}"
# >= 300 rendered frames are needed for the [cover] generation to advance (kCoverPublishEveryFrames);
# the device runs ~10 fps at this vantage, so 40 s is the floor for a per-cell coverage number.
FPS_WIN="${FPS_WIN:-40}"
TESS_LEGACY_BIT=65536       # tese: world-plane projection height lookup (the misaligned one)
POM_LEGACY_BIT=33554432     # frag: legacy POM caps (grazing fade off, 0.08 uv cap, raw height_scale)

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r21-ab FAIL] $*" >&2; exit 1; }
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

# The NEW diag file. Written by pc_set_pbr_isolate() whenever the [cover] generation advances
# (every 300 completed frames) or the material set changes — so it is only live after the cell has
# rendered long enough. Pulled PER CELL because [cover] is per-frame state and [pom] echoes the
# ACTIVE displacement/bisect.
pull_diag(){ local label="$1"
  timeout 40 "$ADB" -s "$S" shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null \
    | tr -d '\r' > "$OUT/diag_$label.txt" || true
  local fr
  fr=$(grep -a '^\[cover\] frame=' "$OUT/diag_$label.txt" | head -1 | sed -e 's/.*frame=\([0-9]*\).*/\1/')
  echo "  diag[$label]: $(wc -l < "$OUT/diag_$label.txt") lines, [cover] frame=${fr:-<none>}, [pom] rows=$(grep -ac '^\[pom\] mat=' "$OUT/diag_$label.txt")"
  echo "$label cover_frame=${fr:-none} pom_rows=$(grep -ac '^\[pom\] mat=' "$OUT/diag_$label.txt")" >> "$OUT/diag_index.txt"
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
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r21_$label.mp4" >/dev/null 2>&1 || true
    timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 "/sdcard/r21_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 60 "$ADB" -s "$S" pull "/sdcard/r21_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r21_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r21_fr; mkdir -p /tmp/r21_fr
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=1 /tmp/r21_fr/f_%03d.png
    L=$(ls /tmp/r21_fr/f_*.png 2>/dev/null | tail -1)
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
  rm -rf /tmp/r21_fr

  if [ "${FPS_WIN}" -gt 0 ]; then
    local T0
    T0=$(timeout 20 "$ADB" -s "$S" shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')
    sleep "$FPS_WIN"
    timeout 240 "$ADB" -s "$S" logcat -d -t "$T0" opengoal-gk:I '*:S' 2>/dev/null \
      | grep -aE 'AOPERF|A35-RENDER frame=' > "$OUT/fps_$label.txt" || true
    local nR meanR nA meanA
    nR=$(grep -ac 'render_ms=' "$OUT/fps_$label.txt" || true)
    meanR=$(grep -a 'render_ms=' "$OUT/fps_$label.txt" | sed -e 's/.*render_ms=\([0-9.]*\).*/\1/' \
        | awk '{f+=$1; n++} END{ if(n>0) printf "%.2f", f/n; else print "nan" }')
    nA=$(grep -ac 'AOPERF' "$OUT/fps_$label.txt" || true)
    meanA=$(grep -a 'AOPERF' "$OUT/fps_$label.txt" | sed -e 's/.*fps=//' -e 's/ .*//' \
        | awk '{f+=$1; n++} END{ if(n>0) printf "%.2f", f/n; else print "nan" }')
    echo "  A35-RENDER lines=$nR mean render_ms=$meanR | AOPERF lines=$nA mean fps=$meanA"
    printf '%-11s render_ms_n=%-4s mean_render_ms=%-8s aoperf_n=%-3s mean_fps=%-7s (disp=%s bisect=%s)\n' \
      "$label" "$nR" "$meanR" "$nA" "$meanA" "$disp" "$bis" >> "$OUT/fps_summary.txt"
  fi
  pull_diag "$label"
  fg_require "${label}_post"
  [ -n "${POSREF:-}" ] && pos_assert "$label" "$POSREF" 0.30
  return 0
}

seed_settings(){
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > "$OUT/settings_orig.ini" 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' "$OUT/settings_orig.ini" || die "settings.ini has no pbr-materials? key"
  cp "$OUT/settings_orig.ini" /tmp/r21_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e "s/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = ${RELIEF}000/" \
    -e "s/^pbr-displacement = [0-9]*/pbr-displacement = ${SEED_DISP:-2}/" \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r21_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/r21_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  local BACK
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = ${SEED_DISP:-2}" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done
  case "$BACK" in *"pbr-texture-relief = ${RELIEF}"*) : ;; *) die "seed readback relief != $RELIEF: $BACK";; esac
}

boot_with(){ # $1 = boot tag, $2 = testpattern prop value
  local tag="$1" tp="$2"
  say "BOOT $tag — testpattern=$tp relief=$RELIEF hour=$HOUR warp=$CONT"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
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
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=|pbr-tess|pbr uv density|pbr height stat|pbr TESTPATTERN|pbr binding|PBR material|shader.*[Ee]rror|link.*[Ff]ail|GL_INVALID' >> "$LOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 340 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot $tag (see $LOG)"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 340s (boot $tag)"
  # HARNESS RULE: wait PAST the ND logo. The spawn marker fires while the intro logo is still up;
  # 90 s of settle is both the logo wait and the r19-established follow-cam DRIFT FLOOR settle.
  echo "  spawned. SETTLING 90 s (past the ND logo, and to let the follow-cam stop drifting)"
  sleep 90
  fg_require "post_settle_$tag"
  grep -a 'pbr uv density' "$LOG" | tee "$OUT/uvdensity_$tag.txt"
  grep -a 'pbr height stat' "$LOG" | tee "$OUT/heightstat_$tag.txt"
  grep -a 'pbr TESTPATTERN' "$LOG" | head -20 | tee "$OUT/testpattern_$tag.txt"
  grep -a 'pbr-tess' "$LOG" | tee "$OUT/tess_capability_$tag.txt"
  kill_loggers
  POSREF=$(pos_now); export POSREF
  echo "  POSREF[$tag] = $POSREF"
}

case "${1:?stage (deploy|C|P|metrics|all)}" in

deploy|all)
  say "0. freshness of the SHIPPED binary — including the .tese/.tesc the redeploy script's glob omits"
  timeout 60 "$ADB" -s "$S" wait-for-device || die "device not present"
  SO=build-android/lib/arm64-v8a/libgk.so
  [ -f "$SO" ] || die "libgk.so not built"
  NEWER=$(find game/graphics game/kernel android common/custom_data -type f \
      \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' -o -name '*.tese' -o -name '*.tesc' \) \
      -newer "$SO" -printf '%p\n' | head -20)
  { echo "libgk.so mtime: $(date -d @$(stat -c %Y "$SO") '+%F %T')";
    echo "sources newer than libgk.so (incl .tese/.tesc):"; echo "${NEWER:-<none>}"; } | tee "$OUT/freshness.txt"
  [ -z "$NEWER" ] || die "sources newer than libgk.so: $NEWER"
  # the GLES shader blob is a GENERATED source; it must be newer than every shader it embeds
  BLOB=build-android/shaders/shaders_android_blob.h
  BNEWER=$(find game/graphics/opengl_renderer/shaders -type f \
      \( -name '*.vert' -o -name '*.frag' -o -name '*.tese' -o -name '*.tesc' -o -name 'preprocess.py' \) \
      -newer "$BLOB" -printf '%p\n' | head)
  echo "shader sources newer than the generated blob: ${BNEWER:-<none>}" | tee -a "$OUT/freshness.txt"
  [ -z "$BNEWER" ] || die "shader blob stale vs $BNEWER"
  for M in "[cover] renderer=" "[pom] mat=" "u_pbr_uv_per_m" "pbr TESTPATTERN"; do
    C=$(strings -a "$SO" | grep -cF -- "$M"); echo "  marker '$M' = $C" | tee -a "$OUT/freshness.txt"
    [ "$C" -gt 0 ] || die "libgk missing marker '$M' (stale build)"
  done
  say "0b. redeploy (build->APK->device sha chain + deploy_verify)"
  bash .autoport/gpbrf_redeploy_freshbuild.sh 2>&1 | tee "$OUT/redeploy_r21.log" | tail -12
  grep -q 'DEPLOY-VERIFY PASS' "$OUT/redeploy_r21.log" || die "deploy_verify did NOT pass"
  BSHA=$(sha256sum "$SO" | cut -d' ' -f1)
  DEVSO=$(timeout 40 "$ADB" -s "$S" shell "pm path $PKG" | head -1 | tr -d '\r' | sed -e 's|package:||' -e 's|/base.apk||')
  DSHA=$(timeout 60 "$ADB" -s "$S" shell "sha256sum $DEVSO/lib/arm64/libgk.so 2>/dev/null" | awk '{print $1}' | tr -d '\r')
  echo "libgk local=$BSHA" | tee -a "$OUT/freshness.txt"
  echo "libgk device=$DSHA ($DEVSO/lib/arm64/libgk.so)" | tee -a "$OUT/freshness.txt"
  if [ -n "$DSHA" ]; then
    [ "$BSHA" = "$DSHA" ] || die "device libgk.so sha != local ($DSHA vs $BSHA)"
    echo "  device .so sha == local .so sha" | tee -a "$OUT/freshness.txt"
  else
    echo "  WARN: could not sha the extracted device .so (path $DEVSO) — deploy_verify chain stands" | tee -a "$OUT/freshness.txt"
  fi
  : > "$OUT/focus_all.txt"; : > "$OUT/props_per_cell.txt"; : > "$OUT/fps_summary.txt"
  : > "$OUT/pos_track.txt"; : > "$OUT/diag_index.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

C|all)
  seed_settings
  boot_with C 1             # the in-build CHECKERBOARD on every PBR material
  cell OFF       0 0
  cell T_ALIGNED 2 0
  cell T_LEGACY  2 $TESS_LEGACY_BIT
  cell P_NEW     1 0
  cell P_LEGACY  1 $POM_LEGACY_BIT
  cell OFF2      0 0        # repeat of OFF == the drift/noise floor of every delta above
  say "crash sweep"
  timeout 240 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|signal 11|signal 6|signal 4|GK-DIAG sig=|GL_INVALID' | tail -30 > "$OUT/crash_sweep.txt" || true
  if [ -s "$OUT/crash_sweep.txt" ]; then echo "  !! signals/GL errors:"; cat "$OUT/crash_sweep.txt"; else echo "  clean: no Fatal signal / signal 11|6|4 / GK-DIAG sig= / GL_INVALID in the buffer"; fi
  say "final diag pull"
  pull_diag final
  cp "$OUT/diag_final.txt" "$OUT/pbr_tan_diag_r21.txt"
  echo; cat "$OUT/fps_summary.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

P|all)
  # PARALLAX-VALID BOOT. In boot C the settings.ini carried pbr-displacement = 2, which is what the
  # phase mandate asked for — but TFragment picks the PROGRAM from that SETTING
  # (TFragment.cpp:629 use_tess = gs.recharged_pbr_displacement == 2), while the prop only rewrites
  # the UNIFORM inside first_tfrag_draw_setup. So with setting=2 + prop=1 every tfrag draw is bound
  # to the TESS program, the tese displacement branch is closed (u_pbr_displacement != 2) AND
  # tfrag3.frag's POM is closed (u_pbr_tess_active != 0): the tfrag draws are FLAT, not parallaxed.
  # boot C's own [cover] block proves it (disp_tess=0 disp_pom=0 disp_none=14 for renderer=tfrag).
  # This boot therefore ships settings.ini pbr-displacement = 1 so TFragment binds the PLAIN
  # program and the fragment POM actually runs on tfrag. Same vantage, same cell mechanics.
  SEED_DISP=1 seed_settings
  boot_with P 1
  cell POFF      0 0
  cell PP_NEW    1 0
  cell PP_LEGACY 1 $POM_LEGACY_BIT
  cell POFF2     0 0
  say "crash sweep (boot P)"
  timeout 240 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|signal 11|signal 6|signal 4|GK-DIAG sig=|GL_INVALID' | tail -30 > "$OUT/crash_sweep_P.txt" || true
  if [ -s "$OUT/crash_sweep_P.txt" ]; then echo "  !! signals/GL errors:"; cat "$OUT/crash_sweep_P.txt"; else echo "  clean (boot P)"; fi
  pull_diag finalP
  cp "$OUT/diag_finalP.txt" "$OUT/pbr_tan_diag_r21_bootP.txt"
  echo; cat "$OUT/fps_summary.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

metrics|all)
  say "R21 METRICS — displacement delta + ALIGNMENT correlation, GROUND and WALL bands"
  python3 .autoport/gpbrf_r21_metrics.py "$OUT" | tee "$OUT/metrics_r21.txt"
  ;;
esac
