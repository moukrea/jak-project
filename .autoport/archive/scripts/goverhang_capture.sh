#!/usr/bin/env bash
# goverhang_capture.sh — Grecharged-grass-overhang proof captures (device eae4df44).
# A: rim close-up, overhang ON  — 3D droop drapes over the lip, covers the alpha fringe texture;
#    walkable-top grass still stops clean at the rim (regression guard in the same frame).
# B: crossfade walk-back        — one continuous recording walking AWAY from the rim: near-3D droop
#    fades out over the blade LOD band, the stock alpha texture remains, NO cards appear on the lip.
# C: far vantage               — static far shot: lip face = original texture only.
# D: toggle OFF A/B            — recharged-grass-overhang? #f in device pc-settings, same rim
#    close-up: no droop, stock texture, top grass unchanged. Restores #t afterwards.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-overhang; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/goverhang_proof.txt"; : > "$PROOF"
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
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1 </dev/null
    kill "$(cat /tmp/gov_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gov_lc.pid )
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
# device pc-settings toggle (gdfix_run.sh pattern): sed the overhang symbol in place.
SETFILE="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
set_overhang(){ local VAL="$1" TMP=/tmp/gov_pcset.gc
  $ADB shell cat "$SETFILE" </dev/null | tr -d '\r' > "$TMP" || return 1
  # a pre-build settings file lacks the key: INSERT it after the recharged-grass? line
  # (same pattern as grass_precompute_verify.sh::set_mode for the precomputed key)
  if grep -q 'recharged-grass-overhang?' "$TMP"; then
    sed -i "s/^recharged-grass-overhang? = [^]*)/^recharged-grass-overhang? = ${VAL}/" "$TMP"
  else
    sed -i "s/^recharged-grass? = #t/recharged-grass? = #t\nrecharged-grass-overhang? = ${VAL}/" "$TMP"
    grep -q 'recharged-grass-overhang?' "$TMP" || return 1
  fi
  $ADB push "$TMP" /data/local/tmp/gov_pcset.gc >/dev/null 2>&1 </dev/null || return 1
  $ADB shell cp /data/local/tmp/gov_pcset.gc "$SETFILE" </dev/null || return 1
  $ADB shell grep 'recharged-grass-overhang?' "$SETFILE" </dev/null | tr -d '\r'; }

RIM="-1324.5 52.2 973.9"     # RIMCAND10: raised grass platform over the ocean (owner-validated rim)
TERR="-1310.2 52.8 989.0"    # RIMCAND4: stepped terraces (lips between storeys)

say "A. RIM CLOSE-UP, overhang ON (default) — RIMCAND10 $RIM"
boot_warp_retry "$RIM" /tmp/gov_a.log || { echo "[goverhang FAIL] beat A boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec gov_rim_on 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_gov_rim_on/f_$i.png ] && cp /tmp/rec_gov_rim_on/f_$i.png "$F/gov_rim_on_$i.png"; done
grep -aE 'GOVERHANG (droop zone|expand)|PLACE-TIME mode=|PRECOMPUTED unavailable' /tmp/gov_a.log | tail -6 >> "$PROOF"

say "B. CROSSFADE WALK-BACK (one take: rim close -> walk backward ~far) — same vantage"
boot_warp_retry "$RIM" /tmp/gov_b.log || { echo "[goverhang FAIL] beat B boot"; exit 1; }
( sleep 4; \
  for k in 1 2 3 4 5 6 7 8 9 10 11 12; do pulse "ly=158" 0.9 0.5; done ) &
K=$!; rec gov_crossfade 40; wait $K 2>/dev/null || true
for i in 004 008 012 016 020 024 028 032 036 040 044 048 052 056 060 064 068 072 076; do
  [ -f /tmp/rec_gov_crossfade/f_$i.png ] && cp /tmp/rec_gov_crossfade/f_$i.png "$F/gov_xfade_$i.png"; done

say "C. TERRACE VANTAGE ON — stepped lips between storeys — RIMCAND4 $TERR"
boot_warp_retry "$TERR" /tmp/gov_c.log || { echo "[goverhang FAIL] beat C boot"; exit 1; }
( sleep 4; pulse "lx=100" 0.6 0.9; pulse "ly=100" 0.5 0.9; pulse "lx=158" 0.6 0.9 ) &
K=$!; rec gov_terrace_on 24; wait $K 2>/dev/null || true
for i in 006 012 018 024 030 036 042; do
  [ -f /tmp/rec_gov_terrace_on/f_$i.png ] && cp /tmp/rec_gov_terrace_on/f_$i.png "$F/gov_terrace_on_$i.png"; done

say "D. TOGGLE OFF A/B — same RIMCAND10 vantage, overhang OFF"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set_overhang #f:"; set_overhang '#f' || { echo "[goverhang FAIL] pc-settings edit (run-as blocked?)"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov_d.log || { echo "[goverhang FAIL] beat D boot"; exit 1; }
( sleep 4; pulse "ly=100" 0.5 0.8; pulse "ly=100" 0.4 0.8; \
  pulse "lx=100" 0.5 0.9; pulse "lx=158" 0.5 0.9; pulse "ly=100" 0.4 1.2 ) &
K=$!; rec gov_rim_off 28; wait $K 2>/dev/null || true
for i in 006 010 014 018 022 026 030 034 038 042 046 050 054; do
  [ -f /tmp/rec_gov_rim_off/f_$i.png ] && cp /tmp/rec_gov_rim_off/f_$i.png "$F/gov_rim_off_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov_d.log | tail -2 >> "$PROOF"

say "E. restore overhang #t + clear props + force-stop (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set_overhang #t:"; set_overhang '#t' || echo "[goverhang WARN] restore #t FAILED — fix manually"
$ADB shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gov_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null

{ echo; echo "=== frame luminance (mean; <15 = black/invalid) ==="
  for p in "$F"/gov_*.png; do
    m=$(ffprobe -v error -f lavfi -i "movie=$p,signalstats" -show_entries frame_tags=lavfi.signalstats.YAVG -of csv=p=0 2>/dev/null | head -1)
    echo "$(basename "$p") YAVG=${m:-?}"
  done; } >> "$PROOF"
echo "[goverhang_capture] DONE — frames in $F, proof in $PROOF"
