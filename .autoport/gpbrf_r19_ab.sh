#!/usr/bin/env bash
# gpbrf_r19_ab.sh — ROUND 19 device A/B: does the OFFLINE PRE-SUBDIVISION make the tessellation
# displacement visible on the GROUND? 2026-07-25.
#
# The supervisor measured, at the owner's vantage, that tessellation moved the ground band by
# 0.77/255 (4.6% of pixels) against displacement-OFF while the parallax it replaces moved 2.27
# (14.5%). Its harness did not survive, so this measures BOTH configurations itself, in the same
# build, at the same vantage, with the same metric — a self-contained comparison instead of a
# number nobody can re-derive.
#
#   BOOT A: debug.opengoal.mesh.subdiv 0      -> pre-subdivision OFF
#           debug.opengoal.pbr.tessseg 0.06   -> the 6 cm target the supervisor measured
#   BOOT B: (both props cleared)              -> pre-subdivision 1.6 m ON, 2.5 cm target
#
# TWO boots are required and cannot be collapsed into one: the subdivision runs in Loader.cpp when
# the LEVEL is loaded, so it can only change across a level load, unlike the per-frame props.
#
# THE MECHANIC (from gpbrf_r18_ab.sh, unchanged and still the thing that makes or breaks a cell):
# TFragment.cpp gates the tessellation PROGRAM on the SETTING pbr-displacement == 2, not on the
# prop; the prop drives the u_pbr_displacement UNIFORM inside that program. So settings.ini must
# carry pbr-displacement = 2 before launch, and then within one boot:
#     prop displacement=2 -> real tessellation           (the tess cell)
#     prop displacement=1 -> tesc passes through at level 1, fragment POM runs   (the parallax cell)
#     prop displacement=0 -> no displacement at all      (the reference cell)
#
# Every adb logcat is `timeout`-wrapped (harness rule: an un-timeouted logcat has zombied this
# phase's captures five times). screencap is ALL BLACK on the GL surface, so stills come from
# screenrecord + ffmpeg with the black-frame/empty-mp4 retries.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/r19; mkdir -p "$OUT"
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"
WARP_POS="${WARP_POS:--111.98 41.96 204.99}"
CONT="${CONT:-village1-hut}"
RELIEF="${RELIEF:-2.0}"
FPS_WIN="${FPS_WIN:-45}"

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r19-ab FAIL] $*" >&2; exit 1; }
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

cell(){ # $1 = label, $2 = displacement prop
  local label="$1" disp="$2"
  say "CELL $label  (displacement=$disp)"
  timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
  local rb
  rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement" | tr -d '\r')
  echo "  props readback: displacement=$rb"
  echo "$label disp=$disp readback=$rb" >> "$OUT/props_per_cell.txt"
  [ "$rb" = "$disp" ] || die "prop readback mismatch for $label: $rb"
  sleep 6
  fg_require "$label"

  local try mp4sz L; L=""
  for try in 1 2 3; do
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r19_$label.mp4" >/dev/null 2>&1 || true
    timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 "/sdcard/r19_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 60 "$ADB" -s "$S" pull "/sdcard/r19_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r19_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r19_fr; mkdir -p /tmp/r19_fr
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=1 /tmp/r19_fr/f_%03d.png
    L=$(ls /tmp/r19_fr/f_*.png 2>/dev/null | tail -1)
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
  rm -rf /tmp/r19_fr

  local T0
  T0=$(timeout 20 "$ADB" -s "$S" shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')
  echo "  fps window ${FPS_WIN}s from $T0 ..."
  sleep "$FPS_WIN"
  timeout 90 "$ADB" -s "$S" logcat -d -t "$T0" opengoal-gk:I '*:S' 2>/dev/null \
    | grep -aE 'AOPERF|\[dyn-rs\]' > "$OUT/fps_$label.txt" || true
  local n mean bmean
  n=$(grep -ac 'AOPERF' "$OUT/fps_$label.txt" || true)
  read -r mean bmean < <(grep -a 'AOPERF' "$OUT/fps_$label.txt" | sed -e 's/.*fps=//' -e 's/busy_ms=//' \
      | awk '{f+=$1; b+=$2; n++} END{ if(n>0) printf "%.2f %.2f\n", f/n, b/n; else print "nan nan" }')
  echo "  AOPERF lines=$n mean fps=$mean mean busy_ms=$bmean"
  printf '%-10s lines=%-3s mean_fps=%-7s mean_busy_ms=%-7s (disp=%s)\n' \
    "$label" "$n" "$mean" "$bmean" "$disp" >> "$OUT/fps_summary.txt"
  fg_require "${label}_post"
  [ -n "${POSREF:-}" ] && pos_assert "$label" "$POSREF" 0.30
}

seed_settings(){
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > "$OUT/settings_orig.ini" 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' "$OUT/settings_orig.ini" || die "settings.ini has no pbr-materials? key"
  cp "$OUT/settings_orig.ini" /tmp/r19_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e "s/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = ${RELIEF}000/" \
    -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 2/' \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r19_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/r19_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  local BACK
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = 2" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done
}

boot_with(){ # $1 = boot tag, $2 = mesh.subdiv prop value ("" = clear), $3 = pbr.tessseg ("" = clear)
  local tag="$1" subdiv="$2" seg="$3"
  say "BOOT $tag — mesh.subdiv='${subdiv:-<default>}' pbr.tessseg='${seg:-<default 0.025>}'"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.pbr.kill 0" \
           "debug.opengoal.pbr.bisect 0" "debug.opengoal.pbr.displacement 2" \
           "debug.opengoal.pbr.relief $RELIEF" "debug.opengoal.rt.light 1" \
           "debug.opengoal.mesh.weld 1" "debug.opengoal.dump.pos 1" \
           "debug.opengoal.tod.hour $HOUR"; do
    timeout 20 "$ADB" -s "$S" shell "setprop $P" || die "setprop $P"
  done
  # NOTE: adb cannot CLEAR a property (setprop '' errors), so boot B uses the sentinel -1, which
  # mesh_subdiv_config_from_env()/the tess-seg clamp both read as "not set, use the default".
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.mesh.subdiv ${subdiv:--1}" || die "setprop subdiv"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.tessseg ${seg:--1}" || die "setprop tessseg"
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.mesh.subdiv; getprop debug.opengoal.pbr.tessseg; getprop debug.opengoal.tod.hour; getprop debug.opengoal.level.warp.pos" \
    | tr -d '\r' | tee "$OUT/props_boot_$tag.txt"

  local LOG="$OUT/boot-logcat-$tag.log"; : > "$LOG"
  ( timeout 420 "$ADB" -s "$S" logcat -T 1 -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=|pbr-tess|mesh-subdiv|PRE-SUBDIVISION|A35-RENDER FBO|shader.*[Ee]rror|link.*[Ff]ail' >> "$LOG" ) 2>/dev/null &
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
  grep -a 'pbr-tess' "$LOG" | tail -3 | tee "$OUT/tess_capability_$tag.txt"
  grep -aE 'mesh-subdiv|PRE-SUBDIVISION' "$LOG" | tail -12 | tee "$OUT/subdiv_$tag.txt"
  kill_loggers
  POSREF=$(pos_now); export POSREF
  echo "  POSREF[$tag] = $POSREF"
}

case "${1:?stage (deploy|A|B|metrics|all)}" in

deploy|all)
  say "0. assemble + install the round-19 build, then deploy_verify"
  timeout 60 "$ADB" -s "$S" wait-for-device || die "device not present"
  [ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
  for M in "PRE-SUBDIVISION" TESS_SEG_EXP mesh-subdiv; do
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

A|all)
  seed_settings
  boot_with A 0 0.06        # pre-subdivision OFF, 6 cm target == the supervisor's configuration
  cell A_tess  2
  cell A_off   0
  cell A_pom   1
  cell A_tess2 2            # REPEAT of the first cell, captured last = this boot's DRIFT FLOOR
  [ "${1:-}" = "all" ] || exit 0
  ;&

B|all)
  seed_settings
  boot_with B "" ""         # pre-subdivision 1.6 m ON, 2.5 cm target = round 19
  cell B_tess  2
  cell B_off   0
  cell B_pom   1
  cell B_tess2 2
  say "crash sweep"
  timeout 90 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|GK-DIAG sig=|libgk.*SIG' | tail -20 > "$OUT/crash_sweep.txt" || true
  if [ -s "$OUT/crash_sweep.txt" ]; then echo "  !! signals:"; cat "$OUT/crash_sweep.txt"; else echo "  no Fatal signal / GK-DIAG sig= in the buffer"; fi
  echo; cat "$OUT/fps_summary.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

metrics|all)
  say "GROUND BAND METRICS"
  python3 .autoport/gpbrf_r19_ground.py "$OUT" | tee "$OUT/ground_metrics.txt"
  ;;
esac
