#!/usr/bin/env bash
# gpbrf_r24_cells.sh — ROUND 24 device capture: the EFFECT metric, not the capability metric.
#
# WHY THIS SCRIPT EXISTS (round-24 reopen). r22/r23 counted a pixel as "displaced" when the
# program that drew it COULD displace it (a height map bound + the tier active). The owner then
# looked at his device and saw flat geometry while the report said 99.22%. Both were true: the
# metric measured capability. This script captures, at ONE vantage and in ONE boot, the pairs that
# let the EFFECT be measured instead:
#
#   off1  displacement prop = 0     (same program, same mesh, amplitude zero)
#   on    displacement prop = TIER  (2 = tessellation, 1 = parallax)
#   off2  displacement prop = 0     — captured AFTER `on`, so the two OFF cells BRACKET it in time
#                                     and |off1-off2| is a MEASURED drift floor, not a postulate.
#   mask  u_pbr_debug = 32          — white iff the material has a HEIGHT map: the DENOMINATOR,
#                                     which is the owner's own framing of the question.
#   prog  u_pbr_debug = 30          — program tag, for attributing dead pixels to a renderer.
#   diag  u_pbr_debug = 33          — R = tess displacement applied here (cm/10), G = POM offset
#                                     (world cm/10), B = distance/40 m: the dead-zone explanation.
#
# The ON/OFF pair is a PROP flip inside one boot on purpose: the tfrag PROGRAM and the mesh
# pre-subdivision are chosen from the SETTING at boot (TFragment.cpp:629, Loader.cpp:489), so
# flipping the prop changes the amplitude and NOTHING else — no program swap, no mesh swap, no
# reload. Any pixel that differs therefore differs because of displacement.
#
# Usage:
#   VLABEL=va VPOS="-111.98 41.96 204.99" TIER=2 TP=1 R24OUT=r24 bash .autoport/gpbrf_r24_cells.sh
#   (TIER 2 = tessellation boot, TIER 1 = parallax boot; TP = checker test-pattern mode.)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
export ANDROID_SERIAL=$S
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/${R24OUT:-r24}; mkdir -p "$OUT"
TP="${TP:-1}"
TIER="${TIER:-2}"
VLABEL="${VLABEL:-va}"
VPOS="${VPOS:--111.98 41.96 204.99}"
CONT="${CONT:-village1-hut}"
RELIEF="${RELIEF:-2.0}"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR=12
SETTLE="${SETTLE:-25}"
ARRIVE_XZ="${ARRIVE_XZ:-6.0}"
APKPATH="${APKPATH:-android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk}"
TAG="${VLABEL}_t${TIER}"

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r24 FAIL] $*" >&2; exit 1; }
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

cell(){ # $1 label  $2 pbr.debug  $3 pbr.displacement  [$4 pbr.bisect, default 0]
  local label="${TAG}_$1" dbg="$2" disp="$3" bis="${4:-0}"
  say "CELL $label  (debug=$dbg displacement=$disp relief=$RELIEF)"
  timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.debug $dbg"        || die "setprop debug"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.relief $RELIEF"     || die "setprop relief"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $bis"        || die "setprop bisect"
  local rd rb rr rx
  rx=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.bisect" | tr -d '\r')
  [ "$rx" = "$bis" ] || die "bisect readback mismatch $label: $rx"
  rd=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.debug" | tr -d '\r')
  rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement" | tr -d '\r')
  rr=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.relief" | tr -d '\r')
  echo "$label debug=$dbg/$rd disp=$disp/$rb relief=$RELIEF/$rr" >> "$OUT/props_per_cell.txt"
  [ "$rd" = "$dbg" ]  || die "debug readback mismatch $label: $rd"
  [ "$rb" = "$disp" ] || die "disp readback mismatch $label: $rb"
  [ "$rr" = "$RELIEF" ] || die "relief readback mismatch $label: $rr"
  sleep "$SETTLE"
  fg_require "$label"

  local try mp4sz L; L=""
  for try in 1 2 3; do
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r24_$label.mp4" >/dev/null 2>&1 || true
    timeout 90 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 32000000 "/sdcard/r24_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 90 "$ADB" -s "$S" pull "/sdcard/r24_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r24_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r24_fr; mkdir -p /tmp/r24_fr
    # ROUND 24 — TEMPORAL AVERAGING. The still is the MEAN of the last NAVG frames, not one frame.
    # Reason, measured: the ON-vs-OFF signal on the shipped materials is a few percent of a dark
    # surface's luminance, while a single H.264 frame off screenrecord carries compression noise of
    # the same order — the drift floor came out at 7% relative (p95) on STATIC stone wall, i.e. the
    # instrument was noisier than the thing being measured. Averaging is applied IDENTICALLY to the
    # ON and the two OFF cells, so it cannot bias the comparison; it only makes the floor small
    # enough for the effect to be resolvable. It lowers the NOISE, never the bar.
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=10 /tmp/r24_fr/f_%03d.png
    L=$(ls /tmp/r24_fr/f_*.png 2>/dev/null | tail -1)
    if [ -n "$L" ]; then
      python3 - "$L" "${NAVG:-24}" <<'PYAVG'
import sys, glob, os
import numpy as np
from PIL import Image
last, navg = sys.argv[1], int(sys.argv[2])
fs = sorted(glob.glob(os.path.join(os.path.dirname(last), "f_*.png")))[-navg:]
acc = None
for f in fs:
    a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float64)
    acc = a if acc is None else acc + a
Image.fromarray(np.rint(acc / len(fs)).clip(0, 255).astype(np.uint8)).save(last + ".avg.png")
print(f"  averaged {len(fs)} frames -> {os.path.basename(last)}.avg.png")
PYAVG
      [ -f "$L.avg.png" ] && L="$L.avg.png"
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
  echo "  still -> $OUT/$label.png ($(stat -c%s "$OUT/$label.png") B)"
  rm -rf /tmp/r24_fr
  case " ${KEEPMP4:-} " in *" $1 "*) : ;; *) rm -f "$OUT/$label.mp4";; esac

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
  cp "$OUT/settings_orig.ini" /tmp/r24_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e "s/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = ${RELIEF}000/" \
    -e "s/^pbr-displacement = [0-9]*/pbr-displacement = ${sd}/" \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r24_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/r24_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  local BACK
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" >> "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = ${sd}" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done
}

# ---------------------------------------------------------------------------------------------
# BINARY GUARD. The Redmi is SHARED (a parallel project + the supervisor both install on it). One
# such install landed at 14:08 in the middle of a capture: it force-stopped the app mid-cell and
# left a DIFFERENT libgk on the device. A capture taken against an unknown binary is worthless —
# worse, it is silently worthless — so every run now pins the expected libgk sha, re-installs if
# the device does not match, and re-checks at the end so an install DURING the run invalidates it.
dev_libgk_sha(){
  local p
  p=$(timeout 30 "$ADB" -s "$S" shell pm path $PKG 2>/dev/null | tr -d '\r' | sed 's/package://' | head -1)
  [ -n "$p" ] || { echo "NO_PACKAGE"; return; }
  timeout 300 "$ADB" -s "$S" shell "unzip -p $p lib/arm64-v8a/libgk.so 2>/dev/null | sha256sum" 2>/dev/null \
    | tr -d '\r' | cut -c1-32
}
require_binary(){
  local want dev
  want=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-32)
  dev=$(dev_libgk_sha)
  echo "  libgk on device=$dev  expected=$want"
  if [ "$dev" != "$want" ]; then
    echo "  !! device runs a FOREIGN build — reinstalling $APKPATH"
    timeout 30 "$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
    timeout 900 "$ADB" -s "$S" install -r -d -t -i com.android.vending "$APKPATH" 2>&1 | tail -2
    dev=$(dev_libgk_sha)
    [ "$dev" = "$want" ] || die "cannot pin the binary: device=$dev want=$want"
    echo "  re-pinned: device libgk == build libgk ($want)"
  fi
  EXPECT_SHA="$want"; export EXPECT_SHA
  echo "$TAG libgk=$want" >> "$OUT/binary_pin.txt"
}

boot_with(){
  say "BOOT $TAG — vantage '$VLABEL' pos='$VPOS' tier=$TIER TP=$TP relief=$RELIEF hour=$HOUR"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.pbr.kill 0" \
           "debug.opengoal.pbr.bisect 0" "debug.opengoal.pbr.displacement $TIER" \
           "debug.opengoal.pbr.relief $RELIEF" "debug.opengoal.pbr.debug 0" \
           "debug.opengoal.rt.light 1" "debug.opengoal.mesh.weld 1" "debug.opengoal.dump.pos 1" \
           "debug.opengoal.mesh.subdiv -1" "debug.opengoal.pbr.tessseg -1" \
           "debug.opengoal.pbr.testpattern $TP" "debug.opengoal.pbr.testsquares 8" \
           "debug.opengoal.tod.hour $HOUR"; do
    timeout 20 "$ADB" -s "$S" shell "setprop $P" || die "setprop $P"
  done
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$VPOS'"
  timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.testpattern; getprop debug.opengoal.pbr.relief; getprop debug.opengoal.tod.hour; getprop debug.opengoal.level.warp; getprop debug.opengoal.level.warp.pos" \
    | tr -d '\r' | tee "$OUT/props_boot_$TAG.txt"

  local LOG="$OUT/boot-logcat-$TAG.log"; : > "$LOG"
  ( timeout 420 "$ADB" -s "$S" logcat -T 1 -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|LEVEL-WARP-FAIL|LEVEL-WARP-POS|Fatal signal|GK-DIAG sig=|pbr-tess|pbr uv density|pbr height stat|pbr binding|shader.*[Ee]rror|[Ff]ailed to (compile|link)|GL_INVALID' >> "$LOG" ) 2>/dev/null &
  timeout 90 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 340 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot $TAG (see $LOG)"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 340s (boot $TAG)"
  echo "  spawned. SETTLING 90 s (past the ND logo + follow-cam drift floor)"
  sleep 90
  fg_require "post_settle_$TAG"
  grep -a 'pbr-tess' "$LOG" | tee "$OUT/tess_capability_$TAG.txt"
  grep -aiE 'failed to (compile|link)|shader.*error|GL_INVALID' "$LOG" | tee "$OUT/shader_errors_$TAG.txt"
  [ -s "$OUT/shader_errors_$TAG.txt" ] && die "shader compile/link errors during boot $TAG"
  kill_loggers
  POSREF=$(pos_now); export POSREF
  local d dxz
  d=$(pos_dist "$VPOS" "$POSREF")
  dxz=$(awk -v A="$VPOS" -v B="$POSREF" 'BEGIN{split(A,a," ");split(B,b," ");x=a[1]-b[1];z=a[3]-b[3];printf "%.3f", sqrt(x*x+z*z)}')
  echo "  arrival[$TAG]: POSREF=$POSREF  3d=${d} m  xz=${dxz} m (limit $ARRIVE_XZ)" | tee -a "$OUT/pos_track.txt"
  awk -v d="$dxz" -v L="$ARRIVE_XZ" 'BEGIN{exit !(d+0 <= L+0)}' || die "WARP DID NOT LAND: xz ${dxz} m from target (POSREF=$POSREF)"
  echo "$TAG POSREF=$POSREF target='$VPOS' xz=${dxz}" >> "$OUT/vantages.txt"
}

: > "$OUT/focus_all.txt"; : >> "$OUT/props_per_cell.txt"
require_binary
seed_settings "$TIER"
boot_with
# OFF cells BRACKET the ON cell in time so the drift floor covers the same interval the effect is
# measured over. mask/prog/diag last: they are classification, not measurement.
# ROUND 24 measurement design, four cells in this order:
#   off1  sham  on  off2
# floor  = |off1 - off2|              (the OUTER pair, spanning the whole measurement interval)
# sham   = min(|sham-off1|, |sham-off2|)   an OFF cell measured EXACTLY like the effect
# effect = min(|on  -off1|, |on  -off2|)
# `sham` and `on` sit in mirror-image interior positions, so the sham is a true false-positive
# control for the decision rule rather than a percentile chosen after the fact.
cell off1 0 0
cell sham 0 0
cell on   0 "$TIER"
cell off2 0 0
cell mask 32 "$TIER"
cell prog 30 "$TIER"
cell diag 33 "$TIER"
cell diag2 34 "$TIER"
# SEAM A/B: bisect bit 131072 = "ignore the mesh-consolidation seam pin weights" (seam := 1). Same
# boot, same vantage, same frame: the delta against `on` is exactly what the pin weights cost.
[ "${SEAMAB:-0}" = "1" ] && cell onNS 0 "$TIER" 131072
DEVSHA_END=$(dev_libgk_sha)
[ "$DEVSHA_END" = "$EXPECT_SHA" ] || die "the device binary CHANGED during the run ($EXPECT_SHA -> $DEVSHA_END): a foreign install invalidated these captures"
echo "  binary still pinned at end of run: $DEVSHA_END"
say "crash/GL sweep ($TAG)"
timeout 240 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
  | grep -aE 'Fatal signal|signal [0-9]+ \(SIG|GL_INVALID|Failed to compile|Failed to link' | tail -40 > "$OUT/crash_sweep_$TAG.txt" || true
if [ -s "$OUT/crash_sweep_$TAG.txt" ]; then echo "  !! hits:"; cat "$OUT/crash_sweep_$TAG.txt"; else echo "  clean ($TAG)"; fi
if [ -f "$OUT/settings_orig.ini" ] && [ "${RESTORE:-1}" = "1" ]; then
  timeout 30 "$ADB" -s "$S" push "$OUT/settings_orig.ini" "$SETTINGS_DEV" >/dev/null 2>&1 \
    && echo "  settings.ini RESTORED" || echo "  WARN settings.ini restore failed"
fi
kill_loggers
say "R24 CELLS DONE ($TAG)"
ls -la "$OUT"/${TAG}_*.png
