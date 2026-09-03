#!/usr/bin/env bash
# goverhang5_diag.sh — Grecharged-grass-overhang5 DIAGNOSTIC capture (device eae4df44).
# CAPTURE-ONLY. Do NOT rebuild/reinstall. Device already runs HEAD libgk (droop shader)
# + current GBK5 grassbake. Shows exactly what the drape does at the terrace/lip overhang.
#
# Two vantages (RIM=ocean lip silhouette, TERR=stepped terraces = owner's view). For each,
# four conditions: OFF (stock lips), ON_len10 (default drape), ON_len15 (max drape reach),
# ON_blades15 (blades-only cyan, grass_dbg 2). warp+settle 14s, then ~8s screenrecord while
# panning cpad (yaw sweep rx + downward pitch ry) so lip edges come into frame; fps=2 frames.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-overhang5/diag; mkdir -p "$OUT"
PROOF="$OUT/goverhang5_diag.txt"; : > "$PROOF"
EXT="/storage/emulated/0/OpenGOAL/jak1/settings.ini"  # external (direct; sole settings file)

RIM="-1324.5 52.2 973.9"     # raised grass platform over the OCEAN — lip silhouette vs sky
TERR="-1310.2 52.8 989.0"    # stepped terraces — dirt walls/lips between storeys (owner's view)

say(){ echo; echo "######## $* ########" | tee -a "$PROOF"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.6}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

# --- set one key = value line in the (sole, external) settings.ini (INI form, direct adb) ---
set_key_both(){ local KEY="$1" VAL="$2"
  local E=/tmp/gov5_ext.gc
  if $ADB shell "cat '$EXT'" </dev/null 2>/dev/null | tr -d '\r' > "$E" && [ -s "$E" ]; then
    if grep -q "^${KEY} = " "$E"; then sed -i "s/^${KEY} = .*/${KEY} = ${VAL}/" "$E"
    else sed -i "s/^recharged-grass? = #t/recharged-grass? = #t\n${KEY} = ${VAL}/" "$E"; fi
    $ADB push "$E" "$EXT" >/dev/null 2>&1 </dev/null
  fi
  echo "  set_key_both ${KEY}=${VAL}: ext=$($ADB shell "grep '^${KEY} = ' '$EXT'" </dev/null 2>/dev/null | tr -d '\r' | paste -sd' ')" | tee -a "$PROOF"; }

ensure_grass_on(){ set_key_both 'recharged-grass?' '#t'; set_key_both 'recharged-grass-precomputed?' '#t'; }

boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3 4 5 6 7 8; do
    $ADB shell am force-stop $PKG </dev/null >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral </dev/null >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start </dev/null >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null >/dev/null 2>&1
    $ADB logcat -b all -c </dev/null >/dev/null 2>&1
    kill "$(cat /tmp/gov5_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gov5_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" </dev/null >/dev/null 2>&1
    local t0=$(date +%s); ok=0; local died=0
    # 60s cap per try; break IMMEDIATELY on the ~1-in-few early-boot SIGILL flake so we relaunch fast
    while [ $(( $(date +%s)-t0 )) -lt 60 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && { died=1; break; }
      sleep 2
    done
    local FOC="$(focus)"
    echo "  try#$TRY warp_ok=$ok died=$died $FOC" | tee -a "$PROOF"
    if [ "$ok" = 1 ]; then
      case "$FOC" in *org.opengoal.gk.jak1*) sleep 14; return 0 ;;
        *) echo "  !! focus NOT jak1 — retry" | tee -a "$PROOF" ;; esac
    fi
  done
  return 1; }

rec_pan(){ local TAG="$1" DIR="$2"    # ~8s screenrecord while yaw-sweep + downward pitch
  mkdir -p "$DIR"
  $ADB shell rm -f /sdcard/${TAG}.mp4 </dev/null >/dev/null 2>&1
  ( sleep 0.5
    pulse "ry=120" 0.5 0.6          # tilt down so the lip/edge drops into frame
    pulse "rx=150" 0.5 0.6          # yaw sweep right
    pulse "rx=150" 0.5 0.6
    pulse "ry=120" 0.4 0.5          # a little more down
    pulse "rx=158" 0.5 0.6
    pulse "rx=158" 0.5 0.6
    pulse "ry=120" 0.4 0.5 ) &
  local K=$!
  $ADB shell screenrecord --time-limit 8 --bit-rate 12000000 /sdcard/${TAG}.mp4 </dev/null >/dev/null 2>&1
  wait $K 2>/dev/null || true
  stick neutral
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 </dev/null >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 </dev/null >/dev/null 2>&1
  rm -f "$DIR"/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 "$DIR/f_%03d.png" 2>/dev/null
  local FOC="$(focus)"
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls "$DIR"/*.png 2>/dev/null | wc -l) DIR=$DIR" | tee -a "$PROOF"
  echo "    focus: $FOC" | tee -a "$PROOF"; }

census(){ local LOG="$1" LABEL="$2"
  echo "  --- census [$LABEL] from $LOG ---" | tee -a "$PROOF"
  grep -aE 'GOVERHANG[0-9]? tail: droop_scatter|PLACE-TIME mode=|PRECOMPUTED unavailable|GOVERHANG[0-9]? smooth normals|FLOORBELOW' "$LOG" 2>/dev/null | tail -8 | sed 's/^/    /' | tee -a "$PROOF"
  # also grep any droop / overhang line for completeness
  grep -aiE 'recharged-grass.*(droop|overhang|mode=|LIVE fallback)' "$LOG" 2>/dev/null | grep -aviE 'R21OCC|R19OCC|R21F|R19SYNC|RIMCAND' | tail -6 | sed 's/^/    /' | tee -a "$PROOF" || true; }

# ---- MAIN LOOP: for each vantage, four conditions ----
$ADB shell setprop debug.opengoal.grass_dbg 0 </dev/null >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.grass.droop_len ''" </dev/null >/dev/null 2>&1
ensure_grass_on

for VANT in RIM TERR; do
  if [ "$VANT" = RIM ]; then POS="$RIM"; else POS="$TERR"; fi
  VDIR="$OUT/$VANT"; mkdir -p "$VDIR"

  # 1) OFF — overhang #f, droop_len 1.0, grass_dbg 0
  say "$VANT / OFF (overhang #f, droop_len 1.0, grass_dbg 0) — STOCK lips baseline"
  set_key_both 'recharged-grass-overhang?' '#f'
  $ADB shell setprop debug.opengoal.grass_dbg 0 </dev/null >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass.droop_len 1.0 </dev/null >/dev/null 2>&1
  if boot_warp_retry "$POS" /tmp/gov5_${VANT}_OFF.log; then
    rec_pan gov5_${VANT}_OFF "$VDIR/OFF"; census /tmp/gov5_${VANT}_OFF.log "$VANT/OFF"
  else echo "  [FAIL] $VANT/OFF boot" | tee -a "$PROOF"; fi

  # 2) ON_len10 — overhang #t, droop_len 1.0, grass_dbg 0
  say "$VANT / ON_len10 (overhang #t, droop_len 1.0, grass_dbg 0) — current default drape"
  set_key_both 'recharged-grass-overhang?' '#t'
  $ADB shell setprop debug.opengoal.grass_dbg 0 </dev/null >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass.droop_len 1.0 </dev/null >/dev/null 2>&1
  if boot_warp_retry "$POS" /tmp/gov5_${VANT}_ON10.log; then
    rec_pan gov5_${VANT}_ON10 "$VDIR/ON_len10"; census /tmp/gov5_${VANT}_ON10.log "$VANT/ON_len10"
  else echo "  [FAIL] $VANT/ON_len10 boot" | tee -a "$PROOF"; fi

  # 3) ON_len15 — overhang #t, droop_len 1.5, grass_dbg 0
  say "$VANT / ON_len15 (overhang #t, droop_len 1.5, grass_dbg 0) — max drape reach"
  set_key_both 'recharged-grass-overhang?' '#t'
  $ADB shell setprop debug.opengoal.grass_dbg 0 </dev/null >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass.droop_len 1.5 </dev/null >/dev/null 2>&1
  if boot_warp_retry "$POS" /tmp/gov5_${VANT}_ON15.log; then
    rec_pan gov5_${VANT}_ON15 "$VDIR/ON_len15"; census /tmp/gov5_${VANT}_ON15.log "$VANT/ON_len15"
  else echo "  [FAIL] $VANT/ON_len15 boot" | tee -a "$PROOF"; fi

  # 4) ON_blades15 — overhang #t, droop_len 1.5, grass_dbg 2 (blades-only cyan)
  say "$VANT / ON_blades15 (overhang #t, droop_len 1.5, grass_dbg 2) — blades-only cyan"
  set_key_both 'recharged-grass-overhang?' '#t'
  $ADB shell setprop debug.opengoal.grass_dbg 2 </dev/null >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass.droop_len 1.5 </dev/null >/dev/null 2>&1
  if boot_warp_retry "$POS" /tmp/gov5_${VANT}_BLADES.log; then
    rec_pan gov5_${VANT}_BLADES "$VDIR/ON_blades15"; census /tmp/gov5_${VANT}_BLADES.log "$VANT/ON_blades15"
  else echo "  [FAIL] $VANT/ON_blades15 boot" | tee -a "$PROOF"; fi
done

# ---- restore + hygiene ----
say "RESTORE + force-stop (device hygiene)"
$ADB shell setprop debug.opengoal.grass_dbg 0 </dev/null >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.grass.droop_len ''" </dev/null >/dev/null 2>&1
set_key_both 'recharged-grass-overhang?' '#t'
$ADB shell setprop debug.opengoal.level.warp '""' </dev/null >/dev/null 2>&1
$ADB shell setprop debug.opengoal.level.warp.pos '""' </dev/null >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject '""' </dev/null >/dev/null 2>&1
kill "$(cat /tmp/gov5_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG </dev/null >/dev/null 2>&1

# ---- per-frame luminance table (mean; <15 = black/invalid) ----
{ echo; echo "=== frame luminance (YAVG mean; <15 = black) ==="
  for p in $(find "$OUT" -name 'f_*.png' | sort); do
    m=$(ffprobe -v error -f lavfi -i "movie=$p,signalstats" -show_entries frame_tags=lavfi.signalstats.YAVG -of csv=p=0 2>/dev/null | head -1)
    echo "$(echo "$p" | sed "s#$OUT/##") YAVG=${m:-?}"
  done; } >> "$PROOF"
echo "[goverhang5_diag] DONE — frames under $OUT, proof=$PROOF" | tee -a "$PROOF"
