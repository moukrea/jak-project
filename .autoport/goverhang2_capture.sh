#!/usr/bin/env bash
# goverhang2_capture.sh — Grecharged-grass-overhang2 ROUND-2 proof captures (device eae4df44).
# Owner round-1 verdict = the acceptance list:
#  (1) fringe alpha texture must be COVERED near (was: "ça passe au travers ... toujours visible")
#  (2) droop must be SHORT like the painted fringe (was: "descend beaucoup trop bas")
#  (3) upright->droop must be PROGRESSIVE (was: "pas progressif ... binaire")
# Beats:
#  A: rim close-up ON (default droop_len) — droop present, NO painted fringe visible under it near.
#  B: droop-length LIVE SWEEP (one take: default -> 0.3 -> 1.0 -> default) — the tunable works
#     without reboot; frames let us match the default to the original texture's visual length.
#  C: progressive-gradient close-up — slow walk toward the rim; the transition twins lean
#     gradually outward/downward as rim distance shrinks (not a binary switch).
#  D: near-dist 15 A/B — fade boundary moves in-frame: far lip reverts to the STOCK texture
#     (crossfade, far = texture only), near lip keeps droop with the texture hidden.
#  E: toggle OFF — stock byte-path: painted fringe fully visible, no droop, no twins.
#  F: restore settings + props, force-stop (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-overhang2; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/goverhang2_proof.txt"; : > "$PROOF"
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
    kill "$(cat /tmp/gov2_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gov2_lc.pid )
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
set_key(){ local KEY="$1" VAL="$2" TMP=/tmp/gov2_pcset.gc   # sed one (key value) pair in place
  $ADB shell run-as $PKG cat "$SETFILE" </dev/null | tr -d '\r' > "$TMP" || return 1
  if grep -q "(${KEY} " "$TMP"; then
    sed -i "s/(${KEY} [^)]*)/(${KEY} ${VAL})/" "$TMP"
  else
    sed -i "s/(recharged-grass? #t)/(recharged-grass? #t)\n  (${KEY} ${VAL})/" "$TMP"
    grep -q "(${KEY} " "$TMP" || return 1
  fi
  $ADB push "$TMP" /data/local/tmp/gov2_pcset.gc >/dev/null 2>&1 </dev/null || return 1
  $ADB shell run-as $PKG cp /data/local/tmp/gov2_pcset.gc "$SETFILE" </dev/null || return 1
  # whole remote command QUOTED — an unquoted '(' is re-joined by adb and hits the device sh raw
  $ADB shell "run-as $PKG grep -F '(${KEY} ' '$SETFILE'" </dev/null | tr -d '\r'; }

RIM="-1324.5 52.2 973.9"     # RIMCAND10: raised grass platform over the ocean (owner-validated rim)
TERR="-1310.2 52.8 989.0"    # RIMCAND4: stepped terraces (lips between storeys)

say "A. RIM CLOSE-UP, overhang ON, default droop_len — RIMCAND10 $RIM"
$ADB shell "setprop debug.opengoal.grass.droop_len ''" >/dev/null 2>&1 </dev/null
boot_warp_retry "$RIM" /tmp/gov2_a.log || { echo "[goverhang2 FAIL] beat A boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g2_rim_on 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_g2_rim_on/f_$i.png ] && cp /tmp/rec_g2_rim_on/f_$i.png "$F/g2_rim_on_$i.png"; done
grep -aE 'GOVERHANG (droop zone|expand)|GOVERHANG2 droop rims|PLACE-TIME mode=|PRECOMPUTED unavailable' /tmp/gov2_a.log | tail -8 >> "$PROOF"

say "B. DROOP-LEN LIVE SWEEP (default ~6s -> 0.3 ~6s -> 1.0 ~6s -> default) — same vantage, no reboot"
boot_warp_retry "$RIM" /tmp/gov2_b.log || { echo "[goverhang2 FAIL] beat B boot"; exit 1; }
( sleep 7; $ADB shell setprop debug.opengoal.grass.droop_len 0.3 </dev/null; \
  sleep 8; $ADB shell setprop debug.opengoal.grass.droop_len 1.0 </dev/null; \
  sleep 8; $ADB shell "setprop debug.opengoal.grass.droop_len ''" </dev/null ) &
K=$!; rec g2_dlen_sweep 30; wait $K 2>/dev/null || true
for i in 006 010 022 026 038 042 054 058; do
  [ -f /tmp/rec_g2_dlen_sweep/f_$i.png ] && cp /tmp/rec_g2_dlen_sweep/f_$i.png "$F/g2_dlen_$i.png"; done

say "C. PROGRESSIVE GRADIENT — slow walk toward the rim, close-up of the lean band"
boot_warp_retry "$TERR" /tmp/gov2_c.log || { echo "[goverhang2 FAIL] beat C boot"; exit 1; }
( sleep 4; pulse "lx=100" 0.6 0.9; \
  for k in 1 2 3 4 5 6 7 8; do pulse "ly=100" 0.35 1.1; done ) &
K=$!; rec g2_gradient 30; wait $K 2>/dev/null || true
for i in 004 008 012 016 020 024 028 032 036 040 044 048 052 056; do
  [ -f /tmp/rec_g2_gradient/f_$i.png ] && cp /tmp/rec_g2_gradient/f_$i.png "$F/g2_grad_$i.png"; done

say "D. NEAR-DIST 15 A/B — fade boundary moves in-frame (far lip = stock texture, near lip = droop)"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set near-dist 15:"; set_key 'recharged-grass-near-dist' '15.0' || { echo "[goverhang2 FAIL] pc-settings near-dist edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov2_d.log || { echo "[goverhang2 FAIL] beat D boot"; exit 1; }
( sleep 4; pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9 ) &
K=$!; rec g2_near15 20; wait $K 2>/dev/null || true
for i in 006 012 018 024 030 036; do
  [ -f /tmp/rec_g2_near15/f_$i.png ] && cp /tmp/rec_g2_near15/f_$i.png "$F/g2_near15_$i.png"; done
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- restore near-dist 30:"; set_key 'recharged-grass-near-dist' '30.0' || echo "[goverhang2 WARN] near-dist restore FAILED"

say "E. TOGGLE OFF — stock byte-path (fringe texture VISIBLE, no droop, no twins)"
echo "--- set_overhang #f:"; set_key 'recharged-grass-overhang?' '#f' || { echo "[goverhang2 FAIL] pc-settings overhang edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov2_e.log || { echo "[goverhang2 FAIL] beat E boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec g2_rim_off 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_g2_rim_off/f_$i.png ] && cp /tmp/rec_g2_rim_off/f_$i.png "$F/g2_rim_off_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov2_e.log | tail -2 >> "$PROOF"

say "F. restore overhang #t + clear props + force-stop (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set_overhang #t:"; set_key 'recharged-grass-overhang?' '#t' || echo "[goverhang2 WARN] restore #t FAILED — fix manually"
$ADB shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.grass.droop_len ''" >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gov2_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null

{ echo; echo "=== frame luminance (mean; <15 = black/invalid) ==="
  for p in "$F"/g2_*.png; do
    m=$(ffprobe -v error -f lavfi -i "movie=$p,signalstats" -show_entries frame_tags=lavfi.signalstats.YAVG -of csv=p=0 2>/dev/null | head -1)
    echo "$(basename "$p") YAVG=${m:-?}"
  done; } >> "$PROOF"
echo "[goverhang2_capture] DONE — frames in $F, proof in $PROOF"
