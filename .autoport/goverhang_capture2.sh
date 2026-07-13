#!/usr/bin/env bash
# goverhang_capture2.sh — Grecharged-grass-overhang beats D/F/E (redo after run#1).
# D: toggle OFF A/B at the SAME rim vantage as gov_rim_on (droop gone, stock alpha texture at the
#    lip, walkable-top grass unchanged) — also shows exactly the texture the ON droop covers.
# F: near-dist slider A/B (30 -> 15) at the same vantage, overhang ON: lips beyond the blade band
#    lose the 3D droop and show the ORIGINAL texture in the SAME frame as the near droop — the
#    distance-driven fade (crossfade) + "far = texture, no cards" proof without locomotion.
# E: restore (#t + near-dist 30), clear props, force-stop.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-overhang; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/goverhang_proof2.txt"; : > "$PROOF"
say(){ echo; echo "######## $* ########"; }
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
    [ "$ok" = 1 ] && { sleep 14; return 0; }
  done
  return 1; }
SETFILE="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
# set a key to a value; INSERTS the overhang key after recharged-grass? when missing
set_key(){ local KEY="$1" VAL="$2" TMP=/tmp/gov2_pcset.gc
  $ADB shell run-as $PKG cat "$SETFILE" </dev/null | tr -d '\r' > "$TMP" || return 1
  if grep -q "(${KEY} " "$TMP"; then
    sed -i "s/(${KEY} [^)]*)/(${KEY} ${VAL})/" "$TMP"
  else
    sed -i "s/(recharged-grass? #t)/(recharged-grass? #t)\n  (${KEY} ${VAL})/" "$TMP"
    grep -q "(${KEY} " "$TMP" || return 1
  fi
  $ADB push "$TMP" /data/local/tmp/gov2_pcset.gc >/dev/null 2>&1 </dev/null || return 1
  $ADB shell run-as $PKG cp /data/local/tmp/gov2_pcset.gc "$SETFILE" </dev/null || return 1
  $ADB shell "run-as $PKG grep -E 'recharged-grass-overhang\?|recharged-grass-near-dist' $SETFILE" </dev/null | tr -d '\r'; }

RIM="-1324.5 52.2 973.9"   # same RIMCAND10 vantage as gov_rim_on

say "D. TOGGLE OFF — same rim vantage, overhang OFF (droop gone, stock alpha texture at the lip)"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set overhang #f:"; set_key 'recharged-grass-overhang?' '#f' || { echo "[gov2 FAIL] pc-settings edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov2_d.log || { echo "[gov2 FAIL] beat D boot"; exit 1; }
rec gov_rim_off 20
for i in 006 010 014 018 022 026 030 034 038; do
  [ -f /tmp/rec_gov_rim_off/f_$i.png ] && cp /tmp/rec_gov_rim_off/f_$i.png "$F/gov_rim_off_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov2_d.log | tail -2 | tee -a "$PROOF"

say "F. NEAR-DIST 15 A/B — overhang ON, blade band shrunk: far lips show TEXTURE in the same frame"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- set overhang #t + near-dist 15:"
set_key 'recharged-grass-overhang?' '#t' || { echo "[gov2 FAIL] pc-settings edit"; exit 1; }
set_key 'recharged-grass-near-dist' '15.0000' || { echo "[gov2 FAIL] pc-settings edit"; exit 1; }
boot_warp_retry "$RIM" /tmp/gov2_f.log || { echo "[gov2 FAIL] beat F boot"; exit 1; }
rec gov_rim_near15 20
for i in 006 010 014 018 022 026 030 034 038; do
  [ -f /tmp/rec_gov_rim_near15/f_$i.png ] && cp /tmp/rec_gov_rim_near15/f_$i.png "$F/gov_rim_near15_$i.png"; done
grep -aE 'GOVERHANG expand' /tmp/gov2_f.log | tail -2 | tee -a "$PROOF"

say "E. restore (#t, near-dist 30) + hygiene"
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
echo "--- restore:"; set_key 'recharged-grass-near-dist' '30.0000' || echo "[gov2 WARN] near-dist restore FAILED"
set_key 'recharged-grass-overhang?' '#t' || echo "[gov2 WARN] overhang restore FAILED"
# clear the warp props with a genuinely EMPTY value (device-side quoting): a leftover name would
# warp the owner's next real boot. Empty -> level_warp_requested() sees buf[0]==0 -> no warp.
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1 </dev/null
echo "  warp prop now: [$($ADB shell getprop debug.opengoal.level.warp </dev/null | tr -d '\r')] (must be empty)"
kill "$(cat /tmp/gov2_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null

{ echo; echo "=== frame luminance (mean; <15 = black/invalid) ==="
  for p in "$F"/gov_rim_off_*.png "$F"/gov_rim_near15_*.png; do
    [ -f "$p" ] || continue
    m=$(ffprobe -v error -f lavfi -i "movie=$p,signalstats" -show_entries frame_tags=lavfi.signalstats.YAVG -of csv=p=0 2>/dev/null | head -1)
    echo "$(basename "$p") YAVG=${m:-?}"
  done; } >> "$PROOF"
echo "[goverhang_capture2] DONE — frames in $F, proof in $PROOF"
