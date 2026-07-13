#!/usr/bin/env bash
# goverhang3_capture.sh — Grecharged-grass-overhang3 ROUND-3 proof captures (device eae4df44).
# Owner round-2 verdict ("failure totale") + his 22:05 correction = the acceptance list; the
# mandated captures reproduce round-2's FAILURE MODES:
#  A (a): WIDE side/below vantage of a terrace lip + the wall under it — NO blade may sprout
#         from the wall below the floor (round-2's "sort de la paroi" was the transition-band
#         uprights; round 3 combs them along the surface).
#  B (b): rim CLOSE-UP — the droop rows hug the fringe mesh relief (rooted at the up-slope/rim
#         edge, growing along the tri plane).
#  C (c)+(f): OFF then ON at the SAME warp vantage — (c) droop visual extent == the ORIGINAL
#         painted fringe extent (OFF frame shows the stock texture at the same spot), and
#         (f) OFF == stock including the fringe texture (no droop, no comb, no twins).
#  D (d)+(e): slow side sweep along a rim — continuous upright -> lean(twins) -> comb(band)
#         -> droop gradient, and blade scale == the adjacent platform grass in the same frame.
#  E: restore settings + props, force-stop (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-overhang3; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/goverhang3_proof.txt"; : > "$PROOF"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%03d.png 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)" | tee -a "$PROOF"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1 </dev/null
    kill "$(cat /tmp/gov3_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gov3_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 14; return 0; }   # settle: warp glow fades, grass field placed
  done
  return 1; }
SETFILE="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
set_key(){ local KEY="$1" VAL="$2" TMP=/tmp/gov3_pcset.gc   # sed one (key value) pair in place
  $ADB shell run-as $PKG cat "$SETFILE" </dev/null | tr -d '\r' > "$TMP" || return 1
  if grep -q "(${KEY} " "$TMP"; then
    sed -i "s/(${KEY} [^)]*)/(${KEY} ${VAL})/" "$TMP"
  else
    sed -i "s/(recharged-grass? #t)/(recharged-grass? #t)\n  (${KEY} ${VAL})/" "$TMP"
    grep -q "(${KEY} " "$TMP" || return 1
  fi
  $ADB push "$TMP" /data/local/tmp/gov3_pcset.gc >/dev/null 2>&1 </dev/null || return 1
  $ADB shell run-as $PKG cp /data/local/tmp/gov3_pcset.gc "$SETFILE" </dev/null || return 1
  $ADB shell "run-as $PKG grep -F '(${KEY} ' '$SETFILE'" </dev/null | tr -d '\r'; }

RIM="-1324.5 52.2 973.9"     # RIMCAND10: raised grass platform over the ocean (owner-validated rim)
TERR="-1310.2 52.8 989.0"    # RIMCAND4: stepped terraces (lips between storeys + walls below lips)

$ADB shell "setprop debug.opengoal.grass.droop_len ''" >/dev/null 2>&1 </dev/null

say "A. WIDE SIDE/BELOW — terraces: upper lip + the wall under it, overhang ON (round-2 failure mode a)"
boot_warp_retry "$TERR" /tmp/gov3_a.log || { echo "[goverhang3 FAIL] beat A boot"; exit 1; }
# pull back from the upper storey, then strafe both ways: several frames frame the upper lip +
# its wall from the lower terrace (side/below). Walk, don't orbit (follow-cam hygiene).
( sleep 4; pulse "ly=158" 0.6 1.0; pulse "ly=158" 0.6 1.0; pulse "ly=158" 0.5 1.0; \
  pulse "lx=100" 0.6 1.1; pulse "lx=100" 0.5 1.1; \
  pulse "lx=158" 0.6 1.1; pulse "lx=158" 0.6 1.1; pulse "lx=158" 0.5 1.1; \
  pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g3_wall_wide 30; wait $K 2>/dev/null || true
for i in 004 008 012 016 020 024 028 032 036 040 044 048 052 056; do
  [ -f /tmp/rec_g3_wall_wide/f_$i.png ] && cp /tmp/rec_g3_wall_wide/f_$i.png "$F/g3_wall_$i.png"; done
grep -aE 'GOVERHANG (droop zone|expand)|GOVERHANG[23] |PLACE-TIME mode=|PRECOMPUTED unavailable' /tmp/gov3_a.log | tail -8 >> "$PROOF"

say "B. RIM CLOSE-UP — droop rows hug the fringe mesh relief (RIMCAND10), overhang ON"
boot_warp_retry "$RIM" /tmp/gov3_b.log || { echo "[goverhang3 FAIL] beat B boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g3_rim_close 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_g3_rim_close/f_$i.png ] && cp /tmp/rec_g3_rim_close/f_$i.png "$F/g3_close_$i.png"; done

say "C1. TOGGLE OFF at RIMCAND10 — stock byte-path: painted fringe visible, no droop/comb/twins"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set_overhang #f:"; set_key 'recharged-grass-overhang?' '#f' || { echo "[goverhang3 FAIL] pc-settings overhang edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov3_c1.log || { echo "[goverhang3 FAIL] beat C1 boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g3_rim_off 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_g3_rim_off/f_$i.png ] && cp /tmp/rec_g3_rim_off/f_$i.png "$F/g3_off_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov3_c1.log | tail -2 >> "$PROOF"

say "C2. TOGGLE ON again, SAME warp vantage + SAME pulses — the (c) length-comparison pair"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set_overhang #t:"; set_key 'recharged-grass-overhang?' '#t' || { echo "[goverhang3 FAIL] pc-settings overhang edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov3_c2.log || { echo "[goverhang3 FAIL] beat C2 boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g3_rim_on 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_g3_rim_on/f_$i.png ] && cp /tmp/rec_g3_rim_on/f_$i.png "$F/g3_on_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov3_c2.log | tail -2 >> "$PROOF"

say "D. GRADIENT SIDE SWEEP — slow strafe along the terrace rim, close (d) + same-frame scale (e)"
boot_warp_retry "$TERR" /tmp/gov3_d.log || { echo "[goverhang3 FAIL] beat D boot"; exit 1; }
( sleep 4; pulse "lx=100" 0.6 0.9; \
  for k in 1 2 3 4 5 6 7 8; do pulse "ly=100" 0.35 1.1; done ) &
K=$!; rec g3_gradient 30; wait $K 2>/dev/null || true
for i in 004 008 012 016 020 024 028 032 036 040 044 048 052 056; do
  [ -f /tmp/rec_g3_gradient/f_$i.png ] && cp /tmp/rec_g3_gradient/f_$i.png "$F/g3_grad_$i.png"; done

say "E. restore + force-stop (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
$ADB shell "run-as $PKG grep -F '(recharged-grass-overhang? ' '$SETFILE'" </dev/null | tr -d '\r' || true
$ADB shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.grass.droop_len ''" >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gov3_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null

{ echo; echo "=== frame luminance (mean; <15 = black/invalid) ==="
  for p in "$F"/g3_*.png; do
    m=$(ffprobe -v error -f lavfi -i "movie=$p,signalstats" -show_entries frame_tags=lavfi.signalstats.YAVG -of csv=p=0 2>/dev/null | head -1)
    echo "$(basename "$p") YAVG=${m:-?}"
  done; } >> "$PROOF"
echo "[goverhang3_capture] DONE — frames in $F, proof in $PROOF"
