#!/usr/bin/env bash
# grass_gclip_capture.sh — Grecharged-grass-object-clip fresh-HEAD re-verification.
# The object-clip fix landed in Grecharged-grass-poc rounds #18-#30 (owner-validated 2026-07-13).
# Two grass phases (precompute, overhang) touched grass code AFTER that close; this run proves the
# HEAD build still clips grass under ground-resting non-TIE actors on device:
#   A BUTTON  (warp-gate-switch-8, static CULL) — grass must not poke through the plate.
#   B ECOVENT (drawless vent, entity-anchored 1.8m footprint) — base clean, NO giant bald patch.
#   C CRATES / open field (breakable TRAMPLE + density regression guard).
# Harvest = R21OCC goal-publish census + R19OCC frame dumps (occ[] world coords + radii).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-object-clip; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/gclip_occ_proof.txt"; : > "$PROOF"
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
    kill "$(cat /tmp/gclip_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gclip_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 14; return 0; }   # settle: warp glow fully faded
  done
  return 1; }
harvest(){ local TITLE="$1" LOG="$2"
  { echo "=== $TITLE ==="
    echo "--- focus: $(focus)"
    echo "--- R21OCC goal-publish (census):"
    grep -aE 'R21OCC goal-publish' "$LOG" | tail -4
    echo "--- R19OCC frame dumps (occ[] world coords + radii):"
    grep -aE 'R19OCC frame=' "$LOG" | tail -4
  } >> "$PROOF"; }

say "A. BUTTON close-up (warp-gate-switch static CULL) — @ -1309.0 7.2 1060.5"
boot_warp_retry "-1309.0 7.2 1060.5" /tmp/gclip_btn.log || { echo "[gclip FAIL] button boot"; exit 1; }
sleep 4
pulse "ry=238" 0.8 0.6
rec gclip_btn 14
for f in /tmp/rec_gclip_btn/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|010|016|022|028) cp "$f" "$F/gclip_btn_$i.png";; esac; done
harvest "A-BUTTON (grass must not poke through the plate; cull ring tight)" /tmp/gclip_btn.log

say "B. ECOVENT (drawless vent, entity-anchored footprint; buried-base nuance) "
VOK=0
for POS in "-1304.5 29.8 851.5" "-1310.5 29.8 850.0" "-1305.0 30.2 858.5"; do
  if boot_warp_retry "$POS" /tmp/gclip_vent.log; then VOK=1; break; fi
done
if [ "$VOK" = 1 ]; then
  sleep 4
  pulse "rx=205" 1.0 0.5
  rec gclip_vent 14
  for f in /tmp/rec_gclip_vent/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
    case "$i" in 004|010|016|022|028) cp "$f" "$F/gclip_vent_$i.png";; esac; done
  harvest "B-ECOVENT (base clean, 1.8m footprint only — NO giant bald patch)" /tmp/gclip_vent.log
else
  echo "[gclip WARN] vent warp failed at all 3 candidates"
fi

say "C. CRATES + open field (trample + density regression guard) — @ -1297.5 7.8 1035.0"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gclip_crate.log || { echo "[gclip FAIL] crate boot"; exit 1; }
rec gclip_crate 14
for f in /tmp/rec_gclip_crate/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|010|016|022|028) cp "$f" "$F/gclip_crate_$i.png";; esac; done
harvest "C-CRATES/FIELD (trample + open-field density, no regression)" /tmp/gclip_crate.log

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gclip_lc.pid 2>/dev/null)" 2>/dev/null || true
ls "$F"/gclip_*.png 2>/dev/null | wc -l
echo "[gclip] DONE"
