#!/usr/bin/env bash
# pbr_device_capture.sh — Grecharged-pbr-materials device PoC proof captures.
# Delivery = the REAL P3 user flow: material PNGs dropped in the EXTERNAL
# custom_assets dir (<root>/jak1/custom_assets/...), never app-internal pushes.
# Stages:
#   material     push the 4 PavingStones070 maps (vil-beach-01 set) to the drop dir
#   toggle on|off  set pbr-materials? in the external settings.ini (sed-or-insert)
#   run TAG      force-stop -> warp village1-hut @ beach (villa-starfish vantage)
#                -> settle -> screenrecord 45s while walk strokes move Jak/camera
#                -> harvest logcat markers + focus into the proof file
#   reset        restore pre-run settings.ini keys, clear warp props, force-stop
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
DROP=/storage/emulated/0/OpenGOAL/jak1/custom_assets
SETTINGS_DEV=/storage/emulated/0/OpenGOAL/jak1/settings.ini
SRC=custom_assets/jak1/texture_replacements/village1-vis-tfrag
OUT=.autoport/reports/Grecharged-pbr-materials/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
# Default vantage: next to villa-starfish (village1-actors.json: 36.4 -1.6 -12.6).
# Override with PBR_POS (empty string = the stock village1-hut spawn point).
POS="${PBR_POS-36.0 3.0 -12.0}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

case "${1:?stage material|toggle on/off|run TAG|reset}" in
material)
  # ONE material on device (owner mandate): TEX names the base texture the set covers.
  TEX="${PBR_TEX:-vil1-sages-stonewall-01}"
  for suf in "" _normal _roughness _ao _height; do
    [ -f "$SRC/${TEX}${suf}.png" ] || { echo "[pbr-cap FAIL] missing $SRC/${TEX}${suf}.png"; exit 1; }
  done
  adb shell mkdir -p "$DROP/village1-vis-tfrag" </dev/null
  # Stray PNGs anywhere under custom_assets replace textures via the bare-name
  # fallback and invalidate the A/B (root cause of the owner's "beaucoup de
  # violet": a stray solid-magenta vil1-jng-leafyground.png at the DROP root).
  STRAYS="$(adb shell "ls $DROP/*.png 2>/dev/null" </dev/null | tr -d '\r')"
  [ -n "$STRAYS" ] && { echo "--- removing stray root PNGs: $STRAYS"; adb shell "rm -f $DROP/*.png" </dev/null; }
  adb shell "rm -f $DROP/village1-vis-tfrag/*.png" </dev/null
  for suf in "" _normal _roughness _ao _height; do
    adb push "$SRC/${TEX}${suf}.png" "$DROP/village1-vis-tfrag/${TEX}${suf}.png" >/dev/null
  done
  echo "--- device drop dir:"; adb shell ls -la "$DROP/village1-vis-tfrag/" </dev/null
  ;;
toggle)
  WANT="${2:?on|off|stock}"; VAL="#t"; [ "$WANT" = off ] && VAL="#f"; [ "$WANT" = stock ] && VAL="#f"
  adb shell am force-stop $PKG </dev/null; sleep 1
  adb shell cat "$SETTINGS_DEV" </dev/null > /tmp/pbr_settings.gc || { echo "[pbr-cap FAIL] no settings.ini"; exit 1; }
  [ -f "$OUT/settings-prerun.gc" ] || cp /tmp/pbr_settings.gc "$OUT/settings-prerun.gc"
  if grep -q '^pbr-materials?' /tmp/pbr_settings.gc; then
    sed -i "s/^pbr-materials? = .*/pbr-materials? = $VAL/" /tmp/pbr_settings.gc
  else
    # mirror the pckernel write order: insert before recharged-foliage-wind?
    sed -i "/^recharged-foliage-wind?/i pbr-materials? = $VAL" /tmp/pbr_settings.gc
  fi
  # the P3 delivery path needs the custom-assets scan enabled; 'stock' disables it
  # entirely (no replacements at all == pristine baseline)
  LCA="#t"; [ "$WANT" = stock ] && LCA="#f"
  sed -i "s/^load-custom-assets? = .*/load-custom-assets? = $LCA/" /tmp/pbr_settings.gc
  adb push /tmp/pbr_settings.gc "$SETTINGS_DEV" >/dev/null
  echo "--- settings now:"; adb shell grep -E '^(pbr-materials|load-custom-assets)' "$SETTINGS_DEV" </dev/null
  ;;
run)
  TAG="${2:?tag}"
  LOG="$OUT/logcat_$TAG.log"
  ok=0
  for TRY in 1 2 3; do
    adb shell am force-stop $PKG </dev/null; sleep 2
    stick neutral
    # Optional TOD control (critique 2 raking-light / realtime mandates):
    #   PBR_TOD_HOUR=<0-23> pins the clock at that hour (kmachine tod_pin) — hold a
    #   low RAKING sun so normal-map relief + the specular highlight actually read.
    #   PBR_TOD_FAST=1 sweeps a full day in ~24s (tod_fast) — the moving-highlight
    #   realtime proof. Pin wins over fast in kmachine, so set at most one.
    adb shell "setprop debug.opengoal.tod.hour '${PBR_TOD_HOUR:-}'" </dev/null
    adb shell "setprop debug.opengoal.tod.fast '${PBR_TOD_FAST:-}'" </dev/null
    adb shell "setprop debug.opengoal.pbr.debug '${PBR_DEBUG_MODE:-}'" </dev/null
    adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
    adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
    adb logcat -b all -c </dev/null || true
    kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/pbr_lc.pid )
    adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    t0=$(date +%s)
    while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && break
  done
  [ "$ok" = 1 ] || { echo "[pbr-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12   # settle: warp glow fade + PBR maps upload with the level
  FOCUS_LINE="$(focus)"
  # movement during the recording: strafe/walk strokes so the camera + view vector
  # sweep across the beach -> a REALTIME specular highlight visibly moves.
  ( [ -n "${PBR_NO_WALK:-}" ] && exit 0   # static vantage (TOD-sweep realtime clip:
                                          # ONLY the sun moves -> un-fakeable)
    if [ "${PBR_WALK_STYLE:-}" = arc ]; then
      # Owner-mandate grazing arc at the sage wall: SLOW continuous lateral walk
      # past the wall so the view angle rakes across it — brick depth must visibly
      # parallax (near bricks slide over far mortar). One slow pass each way.
      sleep 4
      pulse "lx=100" 6.0 1.5
      pulse "lx=158" 12.0 1.5
      pulse "lx=100" 6.0 1.0
      exit 0
    fi
    sleep 4
    pulse "ly=100" 1.2 0.8; pulse "ly=158" 1.2 0.8
    pulse "lx=100" 1.4 0.8; pulse "lx=158" 1.4 0.8
    pulse "ly=100" 1.2 0.8; pulse "ly=158" 1.2 0.8
    pulse "lx=100" 1.4 0.8; pulse "lx=158" 1.4 0.8
    pulse "ly=100" 1.2 0.8; pulse "ly=158" 1.2 0.8 ) &
  KICK=$!
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 45 --bit-rate 12000000 /sdcard/pbr_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true
  sleep 1
  adb pull /sdcard/pbr_$TAG.mp4 "$OUT/pbr_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/pbr_$TAG.mp4" -vf fps=2 "$OUT/frames_$TAG/f_%03d.png"
  sleep 2; kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  { echo "=== run $TAG $(date -Is) ==="
    echo "focus-at-record: $FOCUS_LINE"
    echo "warp: village1-hut pos=$POS"
    echo "tod: hour='${PBR_TOD_HOUR:-}' fast='${PBR_TOD_FAST:-}' pbr_debug='${PBR_DEBUG_MODE:-}' no_walk='${PBR_NO_WALK:-}'"
    echo "--- settings keys this run:"
    grep -aE '^(pbr-materials|load-custom-assets)' /tmp/pbr_settings.gc 2>/dev/null || true
    echo "--- custom-assets scan:"
    grep -a 'custom texture replacements' "$LOG" | head -3
    echo "--- pbr maps loaded:"
    grep -a 'custom pbr map' "$LOG" | head -8
    grep -a 'custom pbr material registered' "$LOG" | head -3
    echo "--- level resolve:"
    grep -a 'Grecharged-pbr-materials' "$LOG" | head -3
    echo "--- crash scan (narrow sig pattern, own PID only):"
    grep -aE 'signal (4|6|11) \(SIG' "$LOG" | head -3 || true
    echo "video: $OUT/pbr_$TAG.mp4 ($(stat -c %s "$OUT/pbr_$TAG.mp4" 2>/dev/null)B) frames=$(ls "$OUT/frames_$TAG" | wc -l)"
    echo
  } >> "$PROOF"
  echo "  run $TAG done: $(tail -2 "$PROOF" | head -1)"
  ;;
viz)
  # Critique 2 "prove each map does work": ONE boot at the wall vantage with the sun
  # pinned low (PBR_TOD_HOUR, default 8), one screenrecord while the per-frame-read
  # debug.opengoal.pbr.debug prop steps 0..9 every 8s. Modes (tfrag3.frag u_pbr_debug):
  # 0 full PBR | 1 albedo passthrough (POM-offset -> parallax viz) | 2 geo normal |
  # 3 final normal | 4 roughness | 5 spec-only | 6 AO | 7 full PBR normal-map OFF
  # (the N A/B pair with 0) | 8 full PBR POM OFF (the POM A/B pair with 0) | 9 height.
  # Frames are extracted mid-segment from prop-set wall-clock offsets vs record start.
  TAG=viz
  LOG="$OUT/logcat_$TAG.log"
  adb shell am force-stop $PKG </dev/null; sleep 2
  stick neutral
  adb shell "setprop debug.opengoal.tod.hour '${PBR_TOD_HOUR:-8}'" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug 0" </dev/null
  adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -b all -c </dev/null || true
  kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/pbr_lc.pid )
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
  t0=$(date +%s); ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
    sleep 3
  done
  [ "$ok" = 1 ] || { echo "[pbr-cap FAIL] warp never spawned (viz)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  rm -f /tmp/pbr_viz_times.txt   # MUST precede the writer spawn (attempt-3 race
                                 # deleted the writer's first line -> misparsed
                                 # offsets -> 7 identical stills)
  BG_START=$(date +%s.%N)
  ( sleep 2
    for m in 0 1 2 3 4 5 6 7 8 9; do
      adb shell "setprop debug.opengoal.pbr.debug $m" </dev/null
      echo "$m $(date +%s.%N)" >> /tmp/pbr_viz_times.txt
      sleep 8
    done ) &
  KICK=$!
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  REC_START=$(date +%s.%N)
  adb shell screenrecord --time-limit 90 --bit-rate 12000000 /sdcard/pbr_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true
  FOCUS_END="$(focus)"
  sleep 1
  adb pull /sdcard/pbr_$TAG.mp4 "$OUT/pbr_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  adb shell am force-stop $PKG </dev/null
  sleep 2; kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
  # extract one frame from the middle of each 8s mode segment (+0.8s screenrecord
  # start latency guess; mid-segment tolerates the jitter)
  mkdir -p "$OUT/viz"; rm -f "$OUT/viz"/mode*.png
  while read -r m tset; do
    # validate: m must be a single mode digit and tset a wall-clock float;
    # anything else (partial line) falls through to the schedule fallback below.
    case "$m" in [0-9]) ;; *) continue ;; esac
    [ -n "${tset:-}" ] || continue
    off=$(python3 -c "print(max(0.5, $tset - $REC_START - 0.8 + 4.0))")
    ffmpeg -y -loglevel error -ss "$off" -i "$OUT/pbr_$TAG.mp4" -frames:v 1 "$OUT/viz/mode$m.png"
  done < /tmp/pbr_viz_times.txt
  # schedule fallback: mode m was set at ~BG_START+2+8m; mid-segment extract.
  for m in 0 1 2 3 4 5 6 7 8 9; do
    [ -f "$OUT/viz/mode$m.png" ] && continue
    off=$(python3 -c "print(max(0.5, $BG_START + 2 + 8*$m - $REC_START - 0.8 + 4.0))")
    ffmpeg -y -loglevel error -ss "$off" -i "$OUT/pbr_$TAG.mp4" -frames:v 1 "$OUT/viz/mode$m.png"
  done
  { echo "=== run viz $(date -Is) ==="
    echo "focus-at-record: $FOCUS_LINE"
    echo "focus-at-END: $FOCUS_END"
    echo "warp: village1-hut pos=$POS  tod-hour=${PBR_TOD_HOUR:-8}"
    echo "--- crash scan (narrow sig pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$LOG" | head -3 || true
    echo "video: $OUT/pbr_$TAG.mp4 ($(stat -c %s "$OUT/pbr_$TAG.mp4" 2>/dev/null)B)"
    echo "viz stills: $(ls "$OUT/viz" 2>/dev/null | tr '\n' ' ')"
    echo
  } >> "$PROOF"
  echo "  viz done: $(ls "$OUT/viz" | wc -l) stills"
  ;;
material_partial)
  # Hardening proofs (owner "beaucoup de violet" + the half-cleaned drop dir the
  # supervisor found): partial map sets must render CLEANLY (no magenta).
  #   albedo    -> only <tex>.png     (owner's half-cleaned state; PBR must NOT engage)
  #   normalonly-> <tex>.png + _normal (registered material with ABSENT R/M/AO ->
  #                the 1x1 neutral-default binds carry those units)
  KIND="${2:?albedo|normalonly}"
  TEX="${PBR_TEX:-vil-beach-01}"
  adb shell mkdir -p "$DROP/village1-vis-tfrag" </dev/null
  STRAYS="$(adb shell "ls $DROP/*.png 2>/dev/null" </dev/null | tr -d '\r')"
  [ -n "$STRAYS" ] && { echo "--- removing stray root PNGs: $STRAYS"; adb shell "rm -f $DROP/*.png" </dev/null; }
  adb shell "rm -f $DROP/village1-vis-tfrag/*.png" </dev/null
  adb push "$SRC/${TEX}.png" "$DROP/village1-vis-tfrag/${TEX}.png" >/dev/null
  if [ "$KIND" = normalonly ]; then
    adb push "$SRC/${TEX}_normal.png" "$DROP/village1-vis-tfrag/${TEX}_normal.png" >/dev/null
  fi
  echo "--- device drop dir (partial: $KIND):"; adb shell ls -la "$DROP/village1-vis-tfrag/" </dev/null
  ;;
renderscale)
  # Mandate B (owner "rendu à plein res ça a crash instant"): RUNTIME render-scale
  # change 50 -> 100 via the REAL menu slider while PBR is active, screenrecorded,
  # with the capture window extending well past the change (crash-capture rule) and
  # an app-foreground assert at the end. Precondition: 'toggle on' + 'material' done.
  TAG=renderscale
  LOG="$OUT/logcat_$TAG.log"
  adb shell am force-stop $PKG </dev/null; sleep 1
  # seed a LOW manual render scale (dynamic auto-scaler OFF so slider row 3 = render-scale)
  adb shell cat "$SETTINGS_DEV" </dev/null > /tmp/pbr_settings.gc
  for kv in 'render-scale = 50' 'dynamic-render-scale? = #f' 'pbr-materials? = #t' 'load-custom-assets? = #t'; do
    k="${kv%% =*}"
    if grep -q "^$k" /tmp/pbr_settings.gc; then
      sed -i "s|^$k = .*|$kv|" /tmp/pbr_settings.gc
    else
      echo "$kv" >> /tmp/pbr_settings.gc
    fi
  done
  adb push /tmp/pbr_settings.gc "$SETTINGS_DEV" >/dev/null
  echo "--- seeded settings:"; adb shell grep -E '^(render-scale|dynamic-render-scale|pbr-materials|load-custom-assets)' "$SETTINGS_DEV" </dev/null
  stick neutral
  adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -b all -c </dev/null || true
  kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/pbr_lc.pid )
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
  t0=$(date +%s); ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
    sleep 3
  done
  [ "$ok" = 1 ] || { echo "[pbr-cap FAIL] warp never spawned (renderscale)"; exit 1; }
  sleep 12
  # menu drive + slider ride happens in the background while screenrecord runs.
  # Buttons go through the FILE-based cpad_inject (proven by ao_menu_toggle.sh);
  # the setprop channel is for stick axes only.
  INJECT="/data/data/$PKG/files/cpad_inject"
  btn(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true
         sleep 0.4
         printf '' | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true
         sleep "${2:-0.9}"; }
  ( sleep 3
    btn "start" 2.5                                   # pause menu root
    for i in 1 2 3 4; do adb exec-out screencap -p > "$OUT/rs_nav_pre$i.png" 2>/dev/null; sleep 0.3; done
    # proven path (goverhang7_menu_toggle3.sh): CIRCLE opens OPTIONS from pause
    # root (on-screen legend), then one DOWN + X enters GRAPHICS.
    btn "circle" 2.0                                  # into OPTIONS
    adb exec-out screencap -p > "$OUT/rs_nav_options_row.png" 2>/dev/null
    btn "down" 0.8; btn "x" 2.0                       # into GRAPHICS
    adb exec-out screencap -p > "$OUT/rs_nav_graphics.png" 2>/dev/null
    btn "down" 0.6; btn "down" 0.6; btn "down" 0.6    # row 3 = RENDER SCALE
    adb exec-out screencap -p > "$OUT/rs_nav_slider_row.png" 2>/dev/null
    btn "x" 0.9                                       # open slider edit
    for i in 1 2 3 4 5; do btn "right" 0.8; done      # 50 -> 100 (step 10)
    adb exec-out screencap -p > "$OUT/rs_nav_slider_100.png" 2>/dev/null
    btn "x" 1.2                                       # commit
    # leave the menu: triangle backs out of pages, start resumes
    btn "triangle" 1.0; btn "triangle" 1.0; btn "triangle" 1.0; btn "start" 1.5
    stick neutral ) &
  KICK=$!
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 90 --bit-rate 12000000 /sdcard/pbr_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true
  FOCUS_END="$(focus)"
  PID_LINE="$(adb shell pidof $PKG </dev/null | tr -d '\r')"
  sleep 1
  adb pull /sdcard/pbr_$TAG.mp4 "$OUT/pbr_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/pbr_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/pbr_$TAG.mp4" -vf fps=2 "$OUT/frames_$TAG/f_%03d.png"
  SET_AFTER="$(adb shell grep -E '^render-scale' "$SETTINGS_DEV" </dev/null | tr -d '\r')"
  sleep 2; kill "$(cat /tmp/pbr_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  { echo "=== run $TAG $(date -Is) ==="
    echo "focus-at-END (must be $PKG): $FOCUS_END"
    echo "pid-at-END (must be nonempty): $PID_LINE"
    echo "settings render-scale after commit: $SET_AFTER"
    echo "--- crash scan (narrow sig pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$LOG" | head -5 || true
    echo "--- game-resolution pushes (FBO realloc trigger):"
    grep -a 'set_game_resolution\|game_res' "$LOG" | tail -5 || true
    echo "video: $OUT/pbr_$TAG.mp4 ($(stat -c %s "$OUT/pbr_$TAG.mp4" 2>/dev/null)B) frames=$(ls "$OUT/frames_$TAG" | wc -l)"
    echo
  } >> "$PROOF"
  echo "  renderscale done: focus-end=$FOCUS_END"
  ;;
reset)
  adb shell am force-stop $PKG </dev/null; sleep 1
  if [ -f "$OUT/settings-prerun.gc" ]; then
    adb push "$OUT/settings-prerun.gc" "$SETTINGS_DEV" >/dev/null
    echo "--- settings restored to pre-run:"; adb shell grep -E '^(pbr-materials|load-custom-assets)' "$SETTINGS_DEV" </dev/null || true
  fi
  adb shell "setprop debug.opengoal.level.warp ''" </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour ''" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  stick neutral
  adb shell am force-stop $PKG </dev/null
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
echo "[pbr-cap $1] DONE"
