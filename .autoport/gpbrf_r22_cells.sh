#!/usr/bin/env bash
# gpbrf_r22_cells.sh — ROUND 22 device capture on the Redmi (eae4df44). 2026-07-26.
# Cell mechanics are r21's verbatim. Two boots, because TFragment picks the tfrag PROGRAM from the
# SETTING pbr-displacement (TFragment.cpp:629) and Loader.cpp:489 gates the mesh pre-subdivision on
# the same SETTING: a "parallax" cell taken while settings.ini says 2 binds the TESS program, whose
# tese branch is closed at prop=1 AND whose frag POM is closed (u_pbr_tess_active != 0) => flat.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
export ANDROID_SERIAL=$S
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/r22; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR=12
WARP_POS="-111.98 41.96 204.99"
CONT="village1-hut"
SETTLE="${SETTLE:-42}"   # >= 300 rendered frames for a fresh [cover] block at ~10 fps
KEEPMP4="wide_T wide_P"

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r22 FAIL] $*" >&2; exit 1; }
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

pos_dist(){ awk -v A="$1" -v B="$2" 'BEGIN{split(A,a," ");split(B,b," ");d=0;for(i=1;i<=3;i++){x=a[i]-b[i];d+=x*x};printf "%.3f", sqrt(d)}'; }

pull_diag(){ local label="$1"
  timeout 40 "$ADB" -s "$S" shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null \
    | tr -d '\r' > "$OUT/diag_$label.txt" || true
  local fr; fr=$(grep -a '^\[cover\] frame=' "$OUT/diag_$label.txt" | head -1 | sed -e 's/.*frame=\([0-9]*\).*/\1/')
  echo "  diag[$label]: $(wc -l < "$OUT/diag_$label.txt") lines, [cover] frame=${fr:-<none>}, [pom] rows=$(grep -ac '^\[pom\] mat=' "$OUT/diag_$label.txt")"
  echo "$label cover_frame=${fr:-none} pom_rows=$(grep -ac '^\[pom\] mat=' "$OUT/diag_$label.txt")" >> "$OUT/diag_index.txt"
}

cell(){ # $1 label  $2 pbr.debug  $3 pbr.displacement  $4 pbr.relief
  local label="$1" dbg="$2" disp="$3" rel="$4"
  say "CELL $label  (debug=$dbg displacement=$disp relief=$rel)"
  timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.debug $dbg"        || die "setprop debug"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.relief $rel"        || die "setprop relief"
  local rd rb rr
  rd=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.debug" | tr -d '\r')
  rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement" | tr -d '\r')
  rr=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.relief" | tr -d '\r')
  echo "  props readback: debug=$rd displacement=$rb relief=$rr"
  echo "$label debug=$dbg/$rd disp=$disp/$rb relief=$rel/$rr" >> "$OUT/props_per_cell.txt"
  [ "$rd" = "$dbg" ]  || die "debug readback mismatch $label: $rd"
  [ "$rb" = "$disp" ] || die "disp readback mismatch $label: $rb"
  [ "$rr" = "$rel" ]  || die "relief readback mismatch $label: $rr"
  echo "  settling ${SETTLE}s (>=300 frames for a fresh [cover])"
  sleep "$SETTLE"
  fg_require "$label"

  local try mp4sz L; L=""
  for try in 1 2 3; do
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r22_$label.mp4" >/dev/null 2>&1 || true
    timeout 90 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 20000000 "/sdcard/r22_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 90 "$ADB" -s "$S" pull "/sdcard/r22_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r22_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r22_fr; mkdir -p /tmp/r22_fr
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=1 /tmp/r22_fr/f_%03d.png
    L=$(ls /tmp/r22_fr/f_*.png 2>/dev/null | tail -1)
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
  rm -rf /tmp/r22_fr
  case " $KEEPMP4 " in *" $label "*) : ;; *) rm -f "$OUT/$label.mp4";; esac

  pull_diag "$label"
  fg_require "${label}_post"
  local now d
  now=$(pos_now); d=$(pos_dist "$POSREF" "$now")
  echo "  pos[$label]: $now  (drift ${d} m from POSREF)"
  echo "[$label] $now drift=${d}m" >> "$OUT/pos_track.txt"
  awk -v d="$d" 'BEGIN{exit !(d+0 <= 0.60)}' || die "CHARACTER MOVED ${d} m at [$label] — capture invalid"
  return 0
}

seed_settings(){ # $1 = pbr-displacement value to SEED
  local sd="$1"
  [ -f "$OUT/settings_orig.ini" ] || {
    timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > "$OUT/settings_orig.ini" 2>/dev/null || die "cannot read device settings.ini"
    grep -qa 'pbr-materials?' "$OUT/settings_orig.ini" || die "settings.ini has no pbr-materials? key"
    echo "  backed up original settings.ini -> $OUT/settings_orig.ini"; }
  cp "$OUT/settings_orig.ini" /tmp/r22_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e "s/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = 2.0000/" \
    -e "s/^pbr-displacement = [0-9]*/pbr-displacement = ${sd}/" \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r22_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/r22_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  local BACK
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" >> "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = ${sd}" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "pbr-texture-relief = 2.0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done
}

boot_with(){ # $1 boot tag, $2 boot-time displacement prop
  local tag="$1" dprop="$2"
  say "BOOT $tag — testpattern=CHECKER relief=2.0 hour=$HOUR warp=$CONT disp_prop=$dprop"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.pbr.kill 0" \
           "debug.opengoal.pbr.bisect 0" "debug.opengoal.pbr.displacement $dprop" \
           "debug.opengoal.pbr.relief 2.0" "debug.opengoal.pbr.debug 0" \
           "debug.opengoal.rt.light 1" "debug.opengoal.mesh.weld 1" "debug.opengoal.dump.pos 1" \
           "debug.opengoal.mesh.subdiv -1" "debug.opengoal.pbr.tessseg -1" \
           "debug.opengoal.pbr.testpattern 1" "debug.opengoal.pbr.testsquares 8" \
           "debug.opengoal.tod.hour $HOUR"; do
    timeout 20 "$ADB" -s "$S" shell "setprop $P" || die "setprop $P"
  done
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.cont '$CONT'"   # mandate spelling; the code reads level.warp
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.testpattern; getprop debug.opengoal.pbr.relief; getprop debug.opengoal.tod.hour; getprop debug.opengoal.level.warp; getprop debug.opengoal.level.warp.pos; getprop debug.opengoal.pbr.debug" \
    | tr -d '\r' | tee "$OUT/props_boot_$tag.txt"

  local LOG="$OUT/boot-logcat-$tag.log"; : > "$LOG"
  ( timeout 420 "$ADB" -s "$S" logcat -T 1 -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|LEVEL-WARP-FAIL|Fatal signal|GK-DIAG sig=|pbr-tess|pbr uv density|pbr height stat|pbr TESTPATTERN|pbr binding|PBR material|shader.*[Ee]rror|[Ff]ailed to (compile|link)|link.*[Ff]ail|GL_INVALID' >> "$LOG" ) 2>/dev/null &
  timeout 90 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 340 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot $tag (see $LOG)"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 340s (boot $tag)"
  echo "  spawned. SETTLING 90 s (past the ND logo + follow-cam drift floor)"
  sleep 90
  fg_require "post_settle_$tag"
  grep -a 'pbr uv density' "$LOG" | tee "$OUT/uvdensity_$tag.txt" >/dev/null
  grep -a 'pbr height stat' "$LOG" | tee "$OUT/heightstat_$tag.txt" >/dev/null
  grep -a 'pbr-tess' "$LOG" | tee "$OUT/tess_capability_$tag.txt"
  grep -aiE 'failed to (compile|link)|shader.*error|GL_INVALID' "$LOG" | tee "$OUT/shader_errors_$tag.txt"
  kill_loggers
  POSREF=$(pos_now); export POSREF
  echo "  POSREF[$tag] = $POSREF"
  # ARRIVAL CHECK. level.warp.pos teleports Jak to the literal coordinate and then GRAVITY drops
  # him to the ground: the y of the settled position is ~7.6 m below the requested 41.96 at this
  # vantage. So the landing test is HORIZONTAL (xz) against the target, plus an exact-match test
  # against the settled position r21 recorded at this same warp (-111.70 34.39 204.78), which is
  # the real reproducibility anchor between rounds.
  local d dxz dr21
  d=$(pos_dist "$WARP_POS" "$POSREF")
  dxz=$(awk -v A="$WARP_POS" -v B="$POSREF" 'BEGIN{split(A,a," ");split(B,b," ");x=a[1]-b[1];z=a[3]-b[3];printf "%.3f", sqrt(x*x+z*z)}')
  dr21=$(pos_dist "-111.70 34.39 204.78" "$POSREF")
  echo "  arrival: POSREF=$POSREF  3d_delta_from_target=${d} m  xz_delta=${dxz} m  delta_from_r21_anchor=${dr21} m" | tee -a "$OUT/pos_track.txt"
  awk -v d="$dxz" 'BEGIN{exit !(d+0 <= 2.0)}' || die "WARP DID NOT LAND: xz ${dxz} m from target (POSREF=$POSREF)"
  awk -v d="$dr21" 'BEGIN{exit !(d+0 <= 1.0)}' || die "VANTAGE DRIFT vs r21 anchor: ${dr21} m (POSREF=$POSREF)"
}

restore_settings(){
  if [ -f "$OUT/settings_orig.ini" ]; then
    timeout 30 "$ADB" -s "$S" push "$OUT/settings_orig.ini" "$SETTINGS_DEV" >/dev/null 2>&1 \
      && echo "  settings.ini RESTORED" || echo "  WARN settings.ini restore failed"
  fi
}

STAGE="${1:-all}"

case "$STAGE" in
T|all)
  : > "$OUT/focus_all.txt"; : > "$OUT/props_per_cell.txt"; : > "$OUT/pos_track.txt"
  : > "$OUT/diag_index.txt"; : > "$OUT/settings_seeded.txt"
  seed_settings 2
  boot_with T 2
  cell cov_prog   30 2 2.0
  cell cov_disp_T 31 2 2.0
  cell wide_T      0 2 2.0
  cell noise_T     0 2 2.0
  cell amp_T_10    0 2 1.0
  cell amp_T_30    0 2 3.0
  cp "$OUT/diag_wide_T.txt" "$OUT/diag_T.txt" 2>/dev/null || true
  say "crash/GL sweep (boot T)"
  timeout 240 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|signal [0-9]+ \(SIG|GL_INVALID|Failed to compile|Failed to link|failed to compile|failed to link' | tail -40 > "$OUT/crash_sweep_T.txt" || true
  if [ -s "$OUT/crash_sweep_T.txt" ]; then echo "  !! hits:"; cat "$OUT/crash_sweep_T.txt"; else echo "  clean (boot T)"; fi
  [ "$STAGE" = "all" ] || { restore_settings; exit 0; }
  ;&
P|all)
  seed_settings 1
  boot_with P 1
  cell cov_prog_P 30 1 2.0
  cell cov_disp_P 31 1 2.0
  cell wide_P      0 1 2.0
  cell noise_P     0 1 2.0
  cell amp_P_10    0 1 1.0
  cell amp_P_30    0 1 3.0
  cp "$OUT/diag_wide_P.txt" "$OUT/diag_P.txt" 2>/dev/null || true
  say "crash/GL sweep (boot P)"
  timeout 240 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|signal [0-9]+ \(SIG|GL_INVALID|Failed to compile|Failed to link|failed to compile|failed to link' | tail -40 > "$OUT/crash_sweep_P.txt" || true
  if [ -s "$OUT/crash_sweep_P.txt" ]; then echo "  !! hits:"; cat "$OUT/crash_sweep_P.txt"; else echo "  clean (boot P)"; fi
  restore_settings
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
  kill_loggers
  say "R22 CELLS DONE"
  ls -la "$OUT"/*.png
  ;;
esac
