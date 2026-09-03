#!/usr/bin/env bash
# grass_r24_capture.sh — ROUND#24 proof captures (owner R23 verdict).
# A: dummy point-blank — break scarecrow-a-1, hold for the spring-back, then WALK for 20s+:
#    the owner's moving bald circle appeared exactly here (post-break walk while the sage-hint
#    voicebox rides Jak). PROOF = frames with NO gliding bald disc + logcat R24MOVE == 0 +
#    R24CENSUS naming what the old kind-0 catch-all would have published.
# B: crates A/B regression guard (owner: crates PERFECT — look must be unchanged).
# C: warp-gate button close-up (allowlist KEEPS its static cull — base must stay clean).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/p24_occ_proof.txt"; : > "$PROOF"
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
    kill "$(cat /tmp/gr24_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gr24_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 14; return 0; }   # long settle: warp glow fully faded
  done
  return 1; }

say "A. DUMMY break + spring-back + post-break WALK — scarecrow-a-1 @ -1244.6 15.0 997.0"
boot_warp_retry "-1243.2 15.3 997.0" /tmp/gr24_dummy.log || { echo "[r24 FAIL] dummy boot"; exit 1; }
( sleep 6; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2; \
  sleep 8; \
  # post-break walk: forward/back/left/right strokes for the moving-circle beat
  pulse "ly=100" 0.9 0.8; pulse "ly=158" 0.9 0.8; \
  pulse "lx=100" 0.9 0.8; pulse "lx=158" 0.9 0.8; \
  pulse "ly=100" 0.9 0.8; pulse "ly=158" 0.9 0.8; \
  pulse "lx=100" 0.9 0.8; pulse "lx=158" 0.9 0.8; \
  pulse "ly=100" 0.9 0.8; pulse "ly=158" 0.9 0.8 ) &
KICK=$!
rec r24_dummy 60
wait $KICK 2>/dev/null || true
for f in /tmp/rec_r24_dummy/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|008|012|016|020|024|028|032|036|040|044|048|052|056|060|068|076|084|092|100|108|116) cp "$f" "$F/p24_dummy_$i.png";; esac; done
{ echo "=== A DUMMY (idle 0-6s, kicks 6-14s, spring-back 14-22s, WALK 22-45s) ==="
  echo "--- R24MOVE (moving kind-0 detector; MUST be empty):"
  grep -ac 'R24MOVE' /tmp/gr24_dummy.log || true
  grep -a 'R24MOVE' /tmp/gr24_dummy.log | head -5
  echo "--- R24CENSUS (what the old catch-all would have published):"
  grep -a 'R24CENSUS' /tmp/gr24_dummy.log | sort -u | head -30
  echo "--- R24DUMMY (broken-state flag census):"
  grep -a 'R24DUMMY' /tmp/gr24_dummy.log | tail -24
  echo "--- R21OCC last publishes:"
  grep -aE 'R21OCC goal-publish' /tmp/gr24_dummy.log | tail -6
} >> "$PROOF"

say "B. CRATES A/B regression — @ -1297.5 7.8 1035.0"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gr24_crate.log || { echo "[r24 FAIL] crate boot"; exit 1; }
rec r24_crate 14
for f in /tmp/rec_r24_crate/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|010|016|022|028) cp "$f" "$F/p24_crate_$i.png";; esac; done
{ echo "=== B CRATES (A/B vs p23_crate_flat / p22_crate_flat — look must be identical) ==="
  grep -aE 'R21OCC goal-publish' /tmp/gr24_crate.log | tail -3
  grep -ac 'R24MOVE' /tmp/gr24_crate.log || true
} >> "$PROOF"

say "C. BUTTON close-up (allowlist keeps the static cull) — @ -1309.0 7.2 1060.5"
boot_warp_retry "-1309.0 7.2 1060.5" /tmp/gr24_btn.log || { echo "[r24 FAIL] button boot"; exit 1; }
rec r24_btn 14
for f in /tmp/rec_r24_btn/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|010|016|022|028) cp "$f" "$F/p24_btn_$i.png";; esac; done
{ echo "=== C BUTTON (base must stay clean — warp-gate-switch is allowlisted) ==="
  grep -aE 'R21OCC goal-publish' /tmp/gr24_btn.log | tail -3
  grep -ac 'R24MOVE' /tmp/gr24_btn.log || true
} >> "$PROOF"

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gr24_lc.pid 2>/dev/null)" 2>/dev/null || true
ls "$F"/p24_*.png 2>/dev/null | wc -l
echo "[r24] DONE"
