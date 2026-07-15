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
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
disk(){ adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE "\((ambient-occlusion|ao-quality) [0-9]+\)" | tr '\n' ' '; echo; }
aolines(){ adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "recharged-ao" | tail -4; }

LOGF="$OUT/proof-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }

# poll up to 8s for a "[recharged-ao] mode -> M quality -> Q" line matching $1/$2
wait_push(){
  local want_m="$1" want_q="$2" i
  for i in $(seq 1 16); do
    if adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null \
       | grep -a "recharged-ao" | grep -aq "mode -> $want_m quality -> $want_q"; then
      echo "PUSH-OK mode->$want_m quality->$want_q"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted mode->$want_m quality->$want_q)"; return 1
}

say "== boot (ao force props cleared, fresh logcat) =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.ao.force_mode '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.ao.force_quality '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp '""'; adb shell setprop debug.opengoal.level.warp.pos '""'
say "disk pre: $(disk)"
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 75; shot 00-title
say "boot [recharged-ao]: $(aolines)"

say "== nav: start -> 2x down -> X (OPTIONS) -> down, X (GRAPHIC OPTIONS) =="
tapb "start" 2.5; shot 01-main-menu
tapb "down" 0.7; tapb "down" 0.7; tapb "x" 2.0; shot 02-options
tapb "down" 0.8; tapb "x" 2.0; shot 03-graphics
say "== 8x down = RECHARGED SETTINGS (android layout, Dynamic ON) =="
for i in $(seq 1 8); do tapb "down" 0.7; done
shot 04-recharged-row
tapb "x" 1.8; shot 05-recharged-page
say "== 4x down = AMBIENT OCCLUSION row (enhanced-models row collapsed) =="
for i in $(seq 1 4); do tapb "down" 0.7; done
shot 06-ao-row

say "== AO commits: Off->SSAO->HBAO->GTAO (X, right, X each; each must push) =="
tapb "x" 0.9; shot 07-carousell-open
tapb "right" 0.9; shot 08-ssao-selected
tapb "x" 1.6; shot 09-ssao-committed
say "SSAO: $(wait_push 1 2) | disk: $(disk)"
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 10-hbao-committed
say "HBAO: $(wait_push 2 2) | disk: $(disk)"
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 11-gtao-committed
say "GTAO: $(wait_push 3 2) | disk: $(disk)"

say "== AO QUALITY: 1x down, X, left (High->Medium), X =="
tapb "down" 0.8; shot 12-quality-row
tapb "x" 0.9; tapb "left" 0.9; tapb "x" 1.6; shot 13-quality-committed
say "QUALITY: $(wait_push 3 1) | disk: $(disk)"

say "== back out: 1x down (Back = index 6, from quality row 5), X, then triangle x2 to title =="
tapb "down" 0.7; tapb "x" 1.6
tapb "triangle" 1.2; tapb "triangle" 1.5; shot 14-backed-out

say "== persist: relaunch; boot push must carry GTAO/Medium =="
adb shell am force-stop $PKG; sleep 2
say "disk after quit: $(disk)"
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 70; shot 15-relaunch
say "disk after relaunch: $(disk)"
say "relaunch [recharged-ao]: $(aolines)"
adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "AOPERF" | tail -3 | tee -a "$LOGF"
adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' | tee -a "$LOGF"
say "[ao-menu-proof2] DONE (device left running; caller decides reset/force-stop)"
