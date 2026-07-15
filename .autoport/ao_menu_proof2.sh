#!/usr/bin/env bash
# ao_menu_proof2.sh — Grecharged-ambient-occlusion OWNER PROOF (a), corrected navigation.
#
# Root cause of the previous "mode stays 0" false-negative: the old scripts pressed DOWN
# only 7x on the ANDROID graphics page, landing on MSAA (index 7) and editing the MSAA
# carousell — never the AO row. Per progress-pc.gc (Goptions-reorder + Grecharged-hud-jak1),
# the android graphics page is: 0 Aspect, 1 GameRes, 2 Dynamic, 3 RenderScale,
# 4 MinTargetFPS, 5 FPSCounter, 6 VSync, 7 MSAA, 8 RECHARGED SETTINGS, 9 Advanced,
# 10 Vulkan, 11 Back  (MinTargetFPS row visible while Dynamic ON -> 8 downs).
# Recharged page (enhanced-models row collapsed, length 7): 0 RechargedHud, 1 GrassSettings,
# 2 LoadCustomAssets, 3 FoliageWind, 4 AMBIENT OCCLUSION, 5 AO QUALITY, 6 Back -> 4 downs.
#
# Self-verifying: every commit MUST produce a "[recharged-ao] mode -> N" logcat push line
# within a few seconds (update-to-os pushes per frame, logs on change) — the script polls
# for it and reports PASS/FAIL per commit. Persistence proven by external settings file +
# relaunch boot push. Screenshots at every step for post-hoc verification.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-ambient-occlusion/menu-proof2; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
# focus-bracketed screenshot (supervisor hard rule 2026-07-15 16:20): mCurrentFocus is
# checked immediately BEFORE and AFTER, saved next to the frame; a non-jak1 frame is
# flagged loudly in the proof log.
shot(){ local FB FA
  FB=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null
  FA=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$OUT/$1.focus.txt"
  case "$FB$FA" in *org.opengoal.gk.jak1*) ;; *)
    say "  SHOT $1: NOT-JAK1-FOREGROUND ($FB / $FA) — frame is NOT evidence";; esac; }
disk(){ adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE "\((ambient-occlusion|ao-quality) [0-9]+\)" | tr '\n' ' '; echo; }
aolines(){ adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "recharged-ao" | tail -4; }

LOGF="$OUT/proof-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }

fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
# MIUI early-boot launch bounces steal the foreground (the attempt-4 proof2 series was
# 100% launcher frames). Hold jak1 foregrounded 30s continuous before ANY input/shot.
stabilize_fg(){ local t0=$(date +%s) held=0
  while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
    if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && { say "  foreground STABLE (30s)"; return 0; }
    else held=0; say "  (stabilize) FG-LOST — refront"
      adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
      adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 10
    fi
    sleep 8
  done
  say "  WARNING: foreground never stabilized (6 min) — proof frames will be non-evidence"; return 1; }

# poll up to 8s for a "[recharged-ao] ... mode -> M ..." push line (quality NOT constrained:
# a real push is "mode -> 3 quality -> 1", so pinning quality to an assumed value false-negatives)
wait_push_mode(){
  local want_m="$1" i
  for i in $(seq 1 16); do
    if adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null \
       | grep -a "recharged-ao" | grep -aq "mode -> $want_m "; then
      echo "PUSH-OK mode->$want_m"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted mode->$want_m)"; return 1
}

# poll up to 8s for a "[recharged-ao] ... quality -> Q" push line (end-of-line tolerant)
wait_push_quality(){
  local want_q="$1" i
  for i in $(seq 1 16); do
    if adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null \
       | grep -a "recharged-ao" | grep -aqE "quality -> $want_q(\s|\$)"; then
      echo "PUSH-OK quality->$want_q"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted quality->$want_q)"; return 1
}

say "== boot (ao force props cleared, fresh logcat) =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.ao.force_mode '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.ao.force_quality '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp '""'; adb shell setprop debug.opengoal.level.warp.pos '""'
# NORMALIZE the disk pre-state: carousel edits are RELATIVE (X, right, X = +1 step), so
# the Off->SSAO->HBAO->GTAO sequence only proves pushes 1/2/3 if we START at Off; quality
# High(2) so the X,left,X edit lands Medium(1). (Leftover state from a killed battery
# made every commit a no-op in the attempt-4 run.)
if adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -qa 'ambient-occlusion'; then
  adb shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_menu.gc 2>/dev/null
  sed -i 's/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/; s/(ao-quality [0-9]*)/(ao-quality 2)/' /tmp/pcs_ao_menu.gc
  adb push /tmp/pcs_ao_menu.gc "$SETTINGS_DEV" >/dev/null 2>&1
fi
say "disk pre: $(disk)"
# Downs to RECHARGED SETTINGS depend on the Min Target FPS row, which is visible ONLY
# while Dynamic Render Scale is ON (apply-dynamic-rs-menu-mode!, progress-pc.gc:1057).
if adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -qa '(dynamic-render-scale? #t)'; then
  DOWNS_RECHARGED=8
else
  DOWNS_RECHARGED=7
fi
say "dynamic-render-scale row: DOWNS_RECHARGED=$DOWNS_RECHARGED"
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 75; stabilize_fg; shot 00-title
say "boot [recharged-ao]: $(aolines)"

say "== nav: start -> 2x down -> X (OPTIONS) -> down, X (GRAPHIC OPTIONS) =="
tapb "start" 2.5; shot 01-main-menu
tapb "down" 0.7; tapb "down" 0.7; tapb "x" 2.0; shot 02-options
tapb "down" 0.8; tapb "x" 2.0; shot 03-graphics
say "== ${DOWNS_RECHARGED}x down = RECHARGED SETTINGS (android layout; MinTargetFPS row only when Dynamic ON) =="
for i in $(seq 1 "$DOWNS_RECHARGED"); do tapb "down" 0.7; done
shot 04-recharged-row
tapb "x" 1.8; shot 05-recharged-page
say "== 4x down = AMBIENT OCCLUSION row (enhanced-models row collapsed) =="
for i in $(seq 1 4); do tapb "down" 0.7; done
shot 06-ao-row

say "== AO commits: Off->SSAO->HBAO->GTAO (X, right, X each; each must push) =="
# logcat cleared before EACH commit: wait_push_* must match the FRESH change-push, not the
# boot push or an earlier commit's line (the attempt-4 GTAO 'PUSH-OK' was the boot line).
adb logcat -c 2>/dev/null || true
tapb "x" 0.9; shot 07-carousell-open
tapb "right" 0.9; shot 08-ssao-selected
tapb "x" 1.6; shot 09-ssao-committed
say "SSAO: $(wait_push_mode 1) | disk: $(disk)"
adb logcat -c 2>/dev/null || true
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 10-hbao-committed
say "HBAO: $(wait_push_mode 2) | disk: $(disk)"
adb logcat -c 2>/dev/null || true
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 11-gtao-committed
say "GTAO: $(wait_push_mode 3) | disk: $(disk)"

say "== AO QUALITY: 1x down, X, left (High->Medium), X =="
adb logcat -c 2>/dev/null || true
tapb "down" 0.8; shot 12-quality-row
tapb "x" 0.9; tapb "left" 0.9; tapb "x" 1.6; shot 13-quality-committed
say "QUALITY: $(wait_push_quality 1) | disk: $(disk)"

say "== back out: 1x down (Back = index 6, from quality row 5), X, then triangle x2 to title =="
tapb "down" 0.7; tapb "x" 1.6
tapb "triangle" 1.2; tapb "triangle" 1.5; shot 14-backed-out

say "== persist: relaunch; boot push must carry GTAO/Medium =="
adb shell am force-stop $PKG; sleep 2
say "disk after quit: $(disk)"
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 70; stabilize_fg; shot 15-relaunch
say "disk after relaunch: $(disk)"
say "relaunch [recharged-ao]: $(aolines)"
adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "AOPERF" | tail -3 | tee -a "$LOGF"
FOCUS_END=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
say "focus at end: $FOCUS_END"
case "$FOCUS_END" in
  *org.opengoal.gk.jak1*) ;;
  *) say "  END-FOCUS NOT JAK1 — crash diagnosis (last fatal/signal lines):"
     adb logcat -d 2>/dev/null | grep -aE 'signal [0-9]+ \(SIG|FATAL EXCEPTION|Fatal signal|beginning of crash' \
       | tail -8 | sed 's/^/  /' | tee -a "$LOGF"
     adb shell "ps -A | grep org.opengoal" 2>/dev/null | tr -d '\r' | sed 's/^/  ps: /' | tee -a "$LOGF" ;;
esac
say "[ao-menu-proof2] DONE (device left running; caller decides reset/force-stop)"
