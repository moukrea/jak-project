#!/usr/bin/env bash
# gpbrf_r18_ab.sh — ROUND 18 device A/B (owner playtest #18: "au SOL le parallax s'étale à plat"
# + "la tessellation manque de relief EN PARTICULIER AU SOL"), 2026-07-25.
#
# Measures, in ONE boot at the owner's grass/sand vantage with the full stack on and the TOD frozen
# at noon, the two round-18 fixes against the code they replaced, plus the FPS of each cell (the
# perf-budget evidence this phase has never produced).
#
#   THE MECHANIC (get this wrong and every cell is worthless):
#   TFragment.cpp:609  use_tess = (Gfx::g_global_settings.recharged_pbr_displacement == 2) && ...
#   gates the TESSELLATION PROGRAM on the SETTING, not on debug.opengoal.pbr.displacement (that prop
#   is applied later, to a LOCAL, in first_tfrag_draw_setup -> the u_pbr_displacement UNIFORM).
#   So settings.ini must carry pbr-displacement = 2 BEFORE launch: that selects the 4-stage
#   TFRAG3_TESS program (vert/tesc/tese from tfrag3_tess, FRAGMENT stage = tfrag3.frag, i.e. the same
#   fragment code as the plain program — Shader.cpp:452). Inside that one boot:
#     prop displacement=1 -> tesc's `tess_on = (u_pbr_displacement == 2)` is FALSE => level 1.0
#                            passthrough (no generated geometry) AND tfrag3.frag:832 runs the POM
#                            march (its gate requires u_pbr_displacement != 2)  => the POM cells.
#     prop displacement=2 -> real tessellation + the fragment POM skipped                 => tess cells.
#   Both props (displacement, bisect) are re-read EVERY FRAME, so all cells share one boot.
#
#   BITS (verified in the shipped shader source):
#     tfrag3.frag:832        (bisect & 128)    != 0  => POM march disabled entirely     (reference)
#     tfrag3.frag:863        (bisect & 262144) != 0  => LEGACY parallax: pom_graze=1, pom_cap=0.08 UV
#                                                       (~16 cm of world sliding)
#     tfrag3_tess.tesc:119   (bisect & 16777216) != 0 => LEGACY tess law: clamp(128/d, 1, cap),
#                                                       distance-only, blind to patch SIZE
#   HONEST CONFOUND, reported not hidden: bit 262144 is OVERLOADED. Besides the legacy parallax it
#   also disables round-17's ambient (indirect) relief ratio at tfrag3.frag:1162. Cell `xtra_ambrel`
#   (bisect 128|262144 = 262272, POM off + ambient relief off) is captured last, right after the
#   second pomOFF, to size that side effect on its own.
#
#   MEASUREMENT-VALIDITY ADDITION (not in the mandate, required for the numbers to mean anything):
#   the device booted with `dynamic-render-scale? = #t` and the GOAL controller was pinned at its 40%
#   floor logging avg-fps 4-19 at this vantage. A dynamic resolution controller (a) absorbs a cost
#   change as RESOLUTION instead of fps, which would erase the tessLEGACY-vs-tessNEW perf signal, and
#   (b) changes the sharpness of the captured frames between cells, which would swamp every |dL|.
#   So this harness seeds dynamic-render-scale? = #f with the owner's own render-scale = 50 and
#   asserts the readback. The original settings.ini is saved to $OUT/settings_orig.ini.
#
# Every adb logcat is `timeout`-wrapped (harness rule: an un-timeouted logcat has zombied this
# phase's captures 5 times). screencap is ALL BLACK on the GL surface, so stills come from
# screenrecord + ffmpeg, with the polish harness's empty-4KB-mp4 and black-frame retries.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/r18; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"                                  # INTEGER: pc_get_tod_hour takes 12 -> 1200
WARP_POS="${WARP_POS:--111.98 41.96 204.99}"        # owner vantage (device/attempt23_posdump.txt)
CONT="${CONT:-village1-hut}"
FPS_WIN="${FPS_WIN:-60}"                            # AOPERF fires every 120 presented frames; at
                                                    # ~5 fps that is one line per 24 s.
B_POMOFF=128
B_POMLEGACY=33554432   # CORRECTED 2026-07-25 (build 9fd3477d562669ac): the round-18 parallax A/B
                       # bit was 262144, which tfrag3.frag:1167 ALREADY used for round-17's
                       # ambient-relief A/B — cell 2 was measuring both. Now 33554432, present
                       # exactly twice in the shipped .so shader text (fused + standalone POM).
B_TESSLEGACY=16777216
B_AMBREL=262272                                     # 128|262144: POM off + round-17 ambient relief off
                                                    # (kept as the control that FOUND the overload)

say(){ echo; echo "######## $* ########"; }
die(){ echo "[r18-ab FAIL] $*" >&2; exit 1; }
kill_loggers(){ pkill -f "$ADB -s $S logcat" 2>/dev/null || true; sleep 1; }

fg_require(){ # $1 = context label; a frame is only evidence when jak1 owns the focus
  local f
  f=$(timeout 30 "$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  echo "  focus[$1]: $f"
  echo "[$1] $f" >> "$OUT/focus_all.txt"
  case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground at [$1]: $f";; esac
}

pos_now(){ local i v=""
  # RETRY: a single run-as read came back EMPTY at 16:36 on 2026-07-25 and the fail-safe gate read
  # that as "moved 235 m from the origin", aborting a pass in which the character had not moved at
  # all (three immediate re-reads all returned the reference position). Empty != moved.
  for i in 1 2 3; do
    v=$(timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pos_dump.txt" 2>/dev/null | tr -d '\r' | head -1)
    case "$v" in *[0-9]*) break;; esac
    sleep 2
  done
  echo "$v"; }
# THE 16:19 TRAP (2026-07-25): during the FIRST fresh-build interleaved pass Jak travelled 39 m
# between cell 2 and cell 3 (pos_dump -111.70 34.39 204.78 -> -143.56 33.49 182.24). Every cell
# after it framed a DIFFERENT place, which collapsed the static mask to 0.0% and made the whole
# pass unmeasurable. A capture is only trustworthy if the character is provably where it was, so
# every cell asserts it now and the pass ABORTS rather than emit numbers about two vantages.
pos_assert(){ # $1 = label, $2 = reference "x y z", $3 = tolerance in metres
  local now dist
  now=$(pos_now)
  dist=$(awk -v A="$2" -v B="$now" 'BEGIN{split(A,a," ");split(B,b," ");d=0;for(i=1;i<=3;i++){x=a[i]-b[i];d+=x*x};printf "%.3f", sqrt(d)}')
  echo "  pos[$1]: $now  (drift ${dist} m from the reference)"
  echo "[$1] $now drift=${dist}m" >> "$OUT/pos_track.txt"
  awk -v d="$dist" -v t="$3" 'BEGIN{exit !(d+0 <= t+0)}' \
    || die "CHARACTER MOVED ${dist} m at [$1] (tolerance $3 m) — capture invalid, re-warp needed"
}

cell(){ # $1 = label, $2 = displacement prop, $3 = bisect prop
  local label="$1" disp="$2" bis="$3"
  say "CELL $label  (displacement=$disp bisect=$bis)"
  timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $bis" || die "setprop bisect"
  # readback: a silently-rejected prop would make two cells identical and look like "no effect"
  local rb
  rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement; getprop debug.opengoal.pbr.bisect" | tr -d '\r' | tr '\n' '/')
  echo "  props readback: $rb"
  echo "$label disp=$disp bisect=$bis readback=$rb" >> "$OUT/props_per_cell.txt"
  case "$rb" in "$disp/$bis/"*) : ;; *) die "prop readback mismatch for $label: $rb";; esac
  sleep 6                                           # both props are re-read per frame; 6 s = live
  fg_require "$label"

  local try mp4sz L
  L=""
  for try in 1 2 3; do
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r18_$label.mp4" >/dev/null 2>&1 || true
    timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 "/sdcard/r18_$label.mp4" >/dev/null 2>&1 || true
    sleep 1
    timeout 60 "$ADB" -s "$S" pull "/sdcard/r18_$label.mp4" "$OUT/$label.mp4" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r18_$label.mp4" >/dev/null 2>&1 || true
    mp4sz=$(stat -c%s "$OUT/$label.mp4" 2>/dev/null || echo 0)
    rm -rf /tmp/r18_fr; mkdir -p /tmp/r18_fr
    [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$label.mp4" -vf fps=1 /tmp/r18_fr/f_%03d.png
    L=$(ls /tmp/r18_fr/f_*.png 2>/dev/null | tail -1)
    if [ -n "$L" ]; then
      # reject an all-black frame (a timed-out screen / non-producing surface)
      if python3 -c "import sys;from PIL import Image;import numpy as np;sys.exit(0 if np.asarray(Image.open('$L').convert('L'),dtype=float).mean()>2.0 else 1)"; then
        break
      fi
      echo "  ($label: BLACK frame, retry $try)"; L=""
    else
      echo "  ($label: empty capture ${mp4sz}B, retry $try)"
    fi
    timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    sleep 12
  done
  [ -n "$L" ] || { echo "MISSING $label (no usable frame)" >> "$OUT/missing_cells.txt"; die "no usable frames $label"; }
  cp "$L" "$OUT/$label.png"
  echo "  still -> $OUT/$label.png  ($(stat -c%s "$OUT/$label.png") B, mp4 ${mp4sz} B)"
  rm -rf /tmp/r18_fr

  # ---- FPS window: props still live, NO screenrecord running (the encoder itself costs frames).
  # Anchored with logcat -t <device time> instead of logcat -c so nothing else's buffer is wiped.
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
  echo "  AOPERF lines=$n  mean fps=$mean  mean busy_ms=$bmean"
  printf '%-12s lines=%-3s mean_fps=%-7s mean_busy_ms=%-7s (disp=%s bisect=%s)\n' \
    "$label" "$n" "$mean" "$bmean" "$disp" "$bis" >> "$OUT/fps_summary.txt"
  fg_require "${label}_post"
  # an fps number is only comparable if the camera is still looking at the same thing
  [ -n "${POSREF:-}" ] && pos_assert "$label" "$POSREF" 0.30
}

case "${1:?stage (verify|boot|cells|metrics|all|fast|fps|cleanup)}" in

verify|all)
  say "0. device present + deploy_verify (the round-18 build must already be on the device)"
  timeout 60 "$ADB" -s "$S" wait-for-device || die "device not present"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tee "$OUT/deploy_verify.log" | tail -6
  grep -q 'DEPLOY-VERIFY PASS' "$OUT/deploy_verify.log" || die "deploy_verify did NOT pass"
  [ "${1:-}" = "all" ] || exit 0
  ;&

boot|all)
  say "1. seed settings.ini — pbr-displacement = 2 SELECTS THE TESS PROGRAM (the key mechanic)"
  : > "$OUT/focus_all.txt"; : > "$OUT/props_per_cell.txt"; : > "$OUT/fps_summary.txt"
  rm -f "$OUT/missing_cells.txt"
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > "$OUT/settings_orig.ini" 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' "$OUT/settings_orig.ini" || die "settings.ini has no pbr-materials? key"
  cp "$OUT/settings_orig.ini" /tmp/r18_settings.ini
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e 's/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = 1.5000/' \
    -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 2/' \
    -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
    /tmp/r18_settings.ini
  cp /tmp/r18_settings.ini "$OUT/settings_r18.ini"
  timeout 30 "$ADB" -s "$S" push /tmp/r18_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|recharged-master\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+|dynamic-render-scale\? = #[tf]|render-scale = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded readback: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  for NEED in "pbr-displacement = 2" "pbr-materials? = #t" "realtime-lighting? = #t" \
              "recharged-master? = #t" "pbr-isolate = 0" "dynamic-render-scale? = #f"; do
    case "$BACK" in *"$NEED"*) : ;; *) die "seed readback missing '$NEED'";; esac
  done

  say "2. props (kill/hour set BEFORE launch: pbr_killswitch caches at first use, tod pin is once)"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  kill_loggers
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pos_dump.txt" >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.pbr.kill 0" \
           "debug.opengoal.pbr.bisect 0" "debug.opengoal.pbr.displacement 1" \
           "debug.opengoal.pbr.relief 1.5" "debug.opengoal.rt.light 1" \
           "debug.opengoal.mesh.weld 1" "debug.opengoal.dump.pos 1" \
           "debug.opengoal.tod.hour $HOUR"; do
    timeout 20 "$ADB" -s "$S" shell "setprop $P" || die "setprop $P"
  done
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.tod.hour; getprop debug.opengoal.pbr.kill; getprop debug.opengoal.level.warp; getprop debug.opengoal.level.warp.pos" | tr -d '\r' | tee "$OUT/props_boot.txt"

  say "3. boot to the vantage ($WARP_POS), TOD pinned at $HOUR:00"
  LOG="$OUT/boot-logcat.log"; : > "$LOG"
  # -T 1: ONLY new lines. Without it adb logcat replays the whole buffer and a PREVIOUS boot's
  # LEVEL-WARP-SPAWN line satisfies the wait loop instantly (observed 16:11 on 2026-07-25 — the
  # settle then overlaps the load instead of following the spawn).
  ( timeout 420 "$ADB" -s "$S" logcat -T 1 -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=|pbr-tess|A35-RENDER FBO|shader.*[Ee]rror|link.*[Ff]ail|dyn-rs' >> "$LOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 340 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot (see $LOG)"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 340s"
  grep -a "LEVEL-WARP-SPAWN" "$LOG" | tail -2
  echo "  spawned. SETTLING 90 s (25 s leaves follow-cam drift that swamps every shading delta)"
  sleep 90
  fg_require "post_settle"
  say "3b. tessellation capability + render FBO size on THIS device"
  grep -a 'pbr-tess' "$LOG" | tail -4 | tee "$OUT/tess_capability.txt"
  grep -a 'A35-RENDER FBO' "$LOG" | tail -3 | tee "$OUT/render_fbo.txt"
  kill_loggers   # the streamer's job is done; a live logcat must never outlive its stage
  [ "${1:-}" = "all" ] || exit 0
  ;&

cells|all)
  say "4. THE CELLS — one boot, one vantage, only props change"
  #    label        disp  bisect
  cell pomOFF       1     $B_POMOFF        # POM disabled = the reference
  cell pomLEGACY    1     $B_POMLEGACY     # legacy un-faded parallax, 0.08 UV cap (~16 cm slide)
  cell pomNEW       1     0                # round-18 grazing-faded + world-cm-capped parallax
  cell tessLEGACY   2     $B_TESSLEGACY    # legacy distance-only tess level law
  cell tessNEW      2     0                # round-18 world-space-edge-length law
  cell pomOFF2      1     $B_POMOFF        # REPEAT of cell 1, captured LAST = the DRIFT FLOOR
  cell xtra_ambrel  1     $B_AMBREL        # EXTRA: POM off + bit-262144's ambient-relief side effect
  say "5. where the camera ACTUALLY was + crash sweep"
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pos_dump.txt" 2>/dev/null | tr -d '\r' > "$OUT/pos_dump.txt" || true
  cat "$OUT/pos_dump.txt" 2>/dev/null || echo "  (no pos_dump.txt)"
  timeout 90 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null \
    | grep -aE 'Fatal signal|GK-DIAG sig=|libgk.*SIG' | tail -20 > "$OUT/crash_sweep.txt" || true
  if [ -s "$OUT/crash_sweep.txt" ]; then echo "  !! signals in buffer:"; cat "$OUT/crash_sweep.txt"; else echo "  no Fatal signal / GK-DIAG sig= in the whole logcat buffer"; fi
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 2"
  echo; cat "$OUT/fps_summary.txt"
  [ "${1:-}" = "all" ] || exit 0
  ;&

metrics|all)
  say "6. METRICS — GROUND crop is where the owner's defect lives"
  python3 .autoport/gpbrf_r18_metrics.py "$OUT" | tee "$OUT/metrics.txt"
  ;;

fast)
  # ---------------------------------------------------------------------------------------------
  # DRIFT-CANCELLING INTERLEAVED PASS. The main pass proved (metrics.txt / metrics_robust.txt) that
  # at this vantage the follow-cam's minutes-scale drift floor (0.0179 raw / 0.0117 hardened mean
  # |dL| on the GROUND crop) is LARGER than the parallax A/B signal, because cell 1 and cell 6 are
  # ~6 minutes apart. Jak never moves (pos_dump is identical before and after), so the drift is the
  # camera alone and it is SLOW. This pass therefore interleaves the cells A-B-A-C-A / T-N-T-N with
  # ~15 s between neighbours and no 60 s fps window, so each measurement can be differenced against
  # the MEAN of its two flanking reference cells: that cancels any drift that is linear over ~30 s,
  # and |A1-A2| itself measures the residual floor over exactly the same interval. Same boot, same
  # vantage, same TOD, same pinned resolution as the main pass.
  # ---------------------------------------------------------------------------------------------
  FOUT="$OUT/fast"; mkdir -p "$FOUT"
  say "F. interleaved drift-cancelling pass (A-B-A-C-A, then T-N-T-N)"
  fg_require "fast_start"
  : > "$OUT/pos_track.txt"
  POSREF=$(pos_now); echo "  position reference: $POSREF"
  echo "  stability pre-check: 30 s of doing nothing, then the position must be unchanged"
  sleep 30
  pos_assert pre_pass "$POSREF" 0.30
  fcell(){ # $1 label, $2 displacement, $3 bisect  — no fps window, tight cadence
    local label="$1" disp="$2" bis="$3" try mp4sz L
    timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $disp" || die "setprop disp"
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $bis" || die "setprop bisect"
    local rb
    rb=$(timeout 20 "$ADB" -s "$S" shell "getprop debug.opengoal.pbr.displacement; getprop debug.opengoal.pbr.bisect" | tr -d '\r' | tr '\n' '/')
    case "$rb" in "$disp/$bis/"*) : ;; *) die "prop readback mismatch $label: $rb";; esac
    sleep 6
    L=""
    for try in 1 2 3; do
      timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r18f_$label.mp4" >/dev/null 2>&1 || true
      timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 "/sdcard/r18f_$label.mp4" >/dev/null 2>&1 || true
      sleep 1
      timeout 60 "$ADB" -s "$S" pull "/sdcard/r18f_$label.mp4" "$FOUT/$label.mp4" >/dev/null 2>&1 || true
      timeout 20 "$ADB" -s "$S" shell rm -f "/sdcard/r18f_$label.mp4" >/dev/null 2>&1 || true
      mp4sz=$(stat -c%s "$FOUT/$label.mp4" 2>/dev/null || echo 0)
      rm -rf /tmp/r18f_fr; mkdir -p /tmp/r18f_fr
      [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$FOUT/$label.mp4" -vf fps=1 /tmp/r18f_fr/f_%03d.png
      L=$(ls /tmp/r18f_fr/f_*.png 2>/dev/null | tail -1)
      if [ -n "$L" ] && python3 -c "import sys;from PIL import Image;import numpy as np;sys.exit(0 if np.asarray(Image.open('$L').convert('L'),dtype=float).mean()>2.0 else 1)"; then break; fi
      echo "  ($label: bad capture ${mp4sz}B, retry $try)"; L=""
      timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
      sleep 8
    done
    [ -n "$L" ] || { echo "MISSING fast/$label" >> "$OUT/missing_cells.txt"; die "no usable frames fast/$label"; }
    cp "$L" "$FOUT/$label.png"; rm -rf /tmp/r18f_fr
    echo "  fast $label (disp=$disp bisect=$bis) -> $FOUT/$label.png"
    echo "[fast_$label] $(timeout 20 "$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')" >> "$OUT/focus_all.txt"
    pos_assert "$label" "$POSREF" 0.30
  }
  fcell a1_pomOFF     1 $B_POMOFF
  fcell b1_pomLEGACY  1 $B_POMLEGACY
  fcell a2_pomOFF     1 $B_POMOFF
  fcell c1_pomNEW     1 0
  fcell a3_pomOFF     1 $B_POMOFF
  fcell t1_tessLEGACY 2 $B_TESSLEGACY
  fcell t2_tessNEW    2 0
  fcell t3_tessLEGACY 2 $B_TESSLEGACY
  fcell t4_tessNEW    2 0
  fg_require "fast_end"
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pos_dump.txt" 2>/dev/null | tr -d '\r' > "$OUT/pos_dump_after_fast.txt" || true
  cat "$OUT/pos_dump_after_fast.txt"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 2"
  timeout 90 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null | grep -aE 'Fatal signal|GK-DIAG sig=' | tail -10 > "$OUT/crash_sweep_fast.txt" || true
  [ -s "$OUT/crash_sweep_fast.txt" ] && { echo "  !! signals:"; cat "$OUT/crash_sweep_fast.txt"; } || echo "  no Fatal signal / GK-DIAG sig="
  python3 .autoport/gpbrf_r18_metrics_fast.py "$FOUT" | tee "$OUT/metrics_fast.txt"
  ;;

fps)
  # STEP 3: AOPERF fps harvest on the fresh build for the four cells the perf question needs, plus a
  # no-displacement anchor and a REPEAT of tessLEGACY at the end as the fps repeatability floor.
  # 60 s window per cell with NO screenrecord running (the encoder costs frames), resolution PINNED
  # (dynamic-render-scale? = #f, seeded by the boot stage) so a cost change shows up as fps and not
  # as a silent resolution drop.
  say "S3. fps cells (60 s AOPERF windows, resolution pinned)"
  : > "$OUT/fps_summary.txt"
  fg_require "fps_start"
  POSREF=$(pos_now); echo "  position reference: $POSREF"
  cell pomOFF       1 $B_POMOFF
  cell pomLEGACY    1 $B_POMLEGACY
  cell pomNEW       1 0
  cell tessLEGACY   2 $B_TESSLEGACY
  cell tessNEW      2 0
  cell tessLEGACY2  2 $B_TESSLEGACY
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 2"
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pos_dump.txt" 2>/dev/null | tr -d '\r' > "$OUT/pos_dump_after_fps.txt" || true
  timeout 90 "$ADB" -s "$S" logcat -d -v threadtime 2>/dev/null | grep -aE 'Fatal signal|GK-DIAG sig=' | tail -10 > "$OUT/crash_sweep_fps.txt" || true
  [ -s "$OUT/crash_sweep_fps.txt" ] && { echo "  !! signals:"; cat "$OUT/crash_sweep_fps.txt"; } || echo "  no Fatal signal / GK-DIAG sig="
  echo; cat "$OUT/fps_summary.txt"
  ;;

fps1)
  # one fps cell: LABEL/DISP/BISECT from the environment (used to recover a single cell lost to a
  # transient read failure without re-running the whole 6-cell stage).
  fg_require "fps1_start"
  POSREF=$(pos_now); echo "  position reference: $POSREF"
  cell "${LABEL:?}" "${DISP:?}" "${BISECT:?}"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 2"
  cat "$OUT/fps_summary.txt"
  ;;

cleanup)
  kill_loggers
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 2"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp none"
  [ -f "$OUT/settings_orig.ini" ] && timeout 30 "$ADB" -s "$S" push "$OUT/settings_orig.ini" "$SETTINGS_DEV" >/dev/null 2>&1
  echo "[r18-ab] props reset, original settings.ini restored"
  ;;
*) die "unknown stage ${1:-}";;
esac
