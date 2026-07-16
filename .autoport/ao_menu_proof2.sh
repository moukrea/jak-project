#!/usr/bin/env bash
# ao_menu_proof2.sh — Grecharged-ambient-occlusion OWNER PROOF (a), corrected navigation, v3.
#
# v2 root cause (attempt-4): pressed DOWN only 7x on the ANDROID graphics page, landing on
# MSAA. Page layout per progress-pc.gc (Goptions-reorder + Grecharged-hud-jak1):
# android graphics page: 0 Aspect, 1 GameRes, 2 Dynamic, 3 RenderScale, 4 MinTargetFPS,
# 5 FPSCounter, 6 VSync, 7 MSAA, 8 RECHARGED SETTINGS, 9 Advanced, 10 Vulkan, 11 Back
# (MinTargetFPS row visible while Dynamic ON -> 8 downs). Recharged page (enhanced-models
# row collapsed, length 8): 0 RechargedHud, 1 GrassSettings, 2 LoadCustomAssets,
# 3 FoliageWind, 4 AMBIENT OCCLUSION, 5 AO QUALITY, 6 AO STRENGTH, 7 Back -> 4 downs to AO.
#
# v3 root causes (attempt-6 forensics, menu-proof2 frame md5s): INTERMITTENT INPUT LOSS —
# consecutive proof frames byte-identical in bursts (taps 03-05 dead, 06-09 alive, 10+
# dead). Menus are edge-triggered (cpad-pressed?), so a 0.4s hold inside a level-load
# hitch or a slow frame is simply never sampled. Fixes:
#   * hold every press 0.8s + >=2s gaps (edge-triggered rows/carousels never repeat on
#     hold — progress-pc.gc uses cpad-pressed? for up/down and carousell l/r — so a long
#     hold is still EXACTLY one step);
#   * seed a RESPONSIVE render config for the menu run (dynamic-render-scale #t,
#     render-scale 50, grass off): menu semantics are resolution-independent, and menu
#     commits progressively enable AO up to GTAO which tanks fps at locked full res;
#   * mark-based fresh-line greps over a persistent logcat reader (MIUI `logcat -c` is
#     unreliable: the attempt-6 "boot mode -> 1" line was impossible for the normalized
#     disk state = presumed stale survivor);
#   * whole-sequence retry (max 3): the four PUSH-OKs must land in ONE coherent attempt,
#     summarized as "[ao-menu-proof2] COMMIT-SEQUENCE PASS (attempt N)".
#
# Self-verifying: every commit MUST produce a fresh "[recharged-ao] mode -> N" push line
# (update-to-os pushes per frame, C++ logs on change). Persistence proven by the external
# settings file + relaunch boot push. Screenshots at every step, focus-bracketed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-ambient-occlusion/menu-proof2; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
# Safe-boot sentinel (C++ commit b057c73d6). This script ENABLES AO then force-stops within
# 60s of the enable (menu commits + persist-relaunch quit), so the sentinel survives the
# dirty death; without removing it the relaunch boots SAFE-BOOT-pinned (AO forced off once)
# and the persist proof false-fails. rm before every boot + right before the relaunch.
SENTINEL="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/ao-boot-guard"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
# v3: 0.8s hold (see header) + slow default gap. Menus are edge-triggered so the long
# hold is exactly one step at any frame rate that samples it at all.
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
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
disk(){ adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE "\((ambient-occlusion|ao-quality|ao-strength) [0-9]+\)" | tr '\n' ' '; echo; }

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

# --- persistent logcat reader + mark-based freshness (v3) ----------------------
GKLOG="$OUT/gk-lc.log"
start_lc(){ kill "$(cat /tmp/ao_menu_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -v brief opengoal-gk:I '*:S' > "$GKLOG" 2>/dev/null & echo $! > /tmp/ao_menu_lc.pid ); sleep 1; }
stop_lc(){ kill "$(cat /tmp/ao_menu_lc.pid 2>/dev/null)" 2>/dev/null || true; }
mark(){ wc -l < "$GKLOG" 2>/dev/null || echo 0; }
fresh(){ tail -n "+$(( $1 + 1 ))" "$GKLOG" 2>/dev/null; }

# poll up to 10s for a FRESH "[recharged-ao] ... mode -> M ..." push line after mark $2
# (quality NOT constrained: a real push is "mode -> 3 quality -> 1")
wait_push_mode(){ local want_m="$1" mk="$2" i
  for i in $(seq 1 20); do
    if fresh "$mk" | grep -a "recharged-ao" | grep -aq "mode -> $want_m "; then
      echo "PUSH-OK mode->$want_m"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted mode->$want_m)"; return 1
}
# poll up to 10s for a FRESH "[recharged-ao] ... quality -> Q" push line (eol tolerant)
wait_push_quality(){ local want_q="$1" mk="$2" i
  for i in $(seq 1 20); do
    if fresh "$mk" | grep -a "recharged-ao" | grep -aqE "quality -> $want_q(\s|\$|\r)"; then
      echo "PUSH-OK quality->$want_q"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted quality->$want_q)"; return 1
}
# poll up to 10s for a FRESH "[recharged-ao] ... strength -> S" push line (eol tolerant)
wait_push_strength(){ local want_s="$1" mk="$2" i
  for i in $(seq 1 20); do
    if fresh "$mk" | grep -a "recharged-ao" | grep -aqE "strength -> $want_s(\s|\$|\r)"; then
      echo "PUSH-OK strength->$want_s"; return 0
    fi
    sleep 0.5
  done
  echo "PUSH-MISSING (wanted strength->$want_s)"; return 1
}

# --- normalize + boot (one per attempt) ----------------------------------------
normalize_and_boot(){ local A="$1"
  adb shell am force-stop $PKG; sleep 2
  adb shell setprop debug.opengoal.ao.force_mode '""' >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.ao.force_quality '""' >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.ao.debug 0 >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.level.warp '""'; adb shell setprop debug.opengoal.level.warp.pos '""'
  # NORMALIZE the disk pre-state: carousel edits are RELATIVE (X, right, X = +1 step), so
  # Off->SSAO->HBAO->GTAO only proves pushes 1/2/3 if we START at Off; quality High(2) so
  # the X,left,X edit lands Medium(1). v3: also seed the RESPONSIVE render config
  # (dynamic RS on, scale 50, grass off) so menu inputs are sampled reliably — the
  # battery's owner-reset (step 5) restores grass/dynamic afterwards.
  adb shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_menu.gc 2>/dev/null
  grep -qa 'ambient-occlusion' /tmp/pcs_ao_menu.gc || { say "[ao-menu-proof2 FAIL] no ambient-occlusion key on device settings"; exit 1; }
  sed -i \
    -e 's/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/' \
    -e 's/(ao-quality [0-9]*)/(ao-quality 2)/' \
    -e 's/(ao-strength [0-9]*)/(ao-strength 1)/' \
    -e 's/(dynamic-render-scale? #[tf])/(dynamic-render-scale? #t)/' \
    -e 's/(render-scale [0-9.]*)/(render-scale 50.0000)/' \
    -e 's/(recharged-grass? #[tf])/(recharged-grass? #f)/' \
    /tmp/pcs_ao_menu.gc
  # OLD device settings files predate the ao-strength key: insert it after ao-quality.
  grep -qa '(ao-strength' /tmp/pcs_ao_menu.gc || sed -i '/(ao-quality [0-9]*)/a\  (ao-strength 1)' /tmp/pcs_ao_menu.gc
  adb push /tmp/pcs_ao_menu.gc "$SETTINGS_DEV" >/dev/null 2>&1
  # VERIFY the normalize LANDED (attempt-4 false-negative root cause: silently failed push)
  NORM_BACK=$(disk)
  case "$NORM_BACK" in *"(ambient-occlusion 0)"*) ;; *)
    say "[ao-menu-proof2 FAIL] normalize did not land: $NORM_BACK"; exit 1 ;; esac
  adb shell rm -f "$SENTINEL" >/dev/null 2>&1
  say "disk pre (attempt $A): $NORM_BACK"
  # Downs to RECHARGED SETTINGS depend on the MinTargetFPS row (visible while Dynamic ON,
  # apply-dynamic-rs-menu-mode!, progress-pc.gc:1057). We just seeded dynamic #t -> 8.
  if adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -qa '(dynamic-render-scale? #t)'; then
    DOWNS_RECHARGED=8
  else
    DOWNS_RECHARGED=7
  fi
  say "dynamic-render-scale row: DOWNS_RECHARGED=$DOWNS_RECHARGED"
  start_lc
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  sleep 75; stabilize_fg; shot "a$A-00-title"
  APP_PID=$(adb shell pidof $PKG 2>/dev/null | tr -d '\r')
  say "app pid: ${APP_PID:-unknown}"
  say "boot [recharged-ao] (fresh log only): $(fresh 0 | grep -a 'recharged-ao' | tail -3 | tr '\n' ' | ' )"
  BOOTPERF=$(fresh 0 | grep -a "AOPERF" | tail -1 | tr -d '\r')
  say "boot AOPERF: ${BOOTPERF:-none}"
  # normalized disk = mode 0: a non-0 boot mode means the game did NOT read the file we
  # seeded — dump read-path candidates for diagnosis instead of guessing (attempt-6 saw a
  # 'mode -> 1' boot line; presumed a stale logcat survivor, now structurally excluded).
  case "${BOOTPERF:-mode=0}" in *"mode=0"*) ;; *)
    say "  !!! boot AOPERF mode != normalized 0 — settings read-path diagnosis:"
    say "  external: $(disk)"
    say "  internal candidates: $(adb shell run-as $PKG sh -c 'ls -la files/ 2>/dev/null | head -20' | tr '\r' ' ' | tr '\n' ' ')" ;;
  esac
}

# --- one full nav + commit sequence; returns 0 iff ALL FOUR pushes landed --------
do_nav_and_commits(){ local A="$1" MK R1 R2 R3 R4 R5
  say "== attempt $A nav: start -> 2x down -> X (OPTIONS) -> down, X (GRAPHIC OPTIONS) =="
  tapb "start" 3.0; shot "a$A-01-main-menu"
  tapb "down"; tapb "down"; tapb "x" 3.0; shot "a$A-02-options"
  tapb "down"; tapb "x" 3.0; shot "a$A-03-graphics"
  say "== ${DOWNS_RECHARGED}x down = RECHARGED SETTINGS row =="
  for i in $(seq 1 "$DOWNS_RECHARGED"); do tapb "down" 1.6; done
  shot "a$A-04-recharged-row"
  tapb "x" 2.5; shot "a$A-05-recharged-page"
  # AO is STILL Off here (normalize seeded ambient-occlusion 0): capture the recharged page
  # with the AO STRENGTH row present-but-disabled (greyed, option-disabled while AO==0, same
  # as AO QUALITY). This is the earliest point the page is visible with AO still Off.
  shot "a$A-05b-strength-row-disabled"
  say "== 4x down = AMBIENT OCCLUSION row (enhanced-models row collapsed) =="
  for i in $(seq 1 4); do tapb "down" 1.6; done
  shot "a$A-06-ao-row"

  say "== AO commits: Off->SSAO->HBAO->GTAO (X, right, X each; each must push fresh) =="
  MK=$(mark)
  tapb "x" 1.5; shot "a$A-07-carousell-open"
  tapb "right" 1.5; shot "a$A-08-ssao-selected"
  tapb "x" 2.0; shot "a$A-09-ssao-committed"
  R1=$(wait_push_mode 1 "$MK"); say "SSAO: $R1 | disk: $(disk)"
  MK=$(mark)
  tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.0; shot "a$A-10-hbao-committed"
  R2=$(wait_push_mode 2 "$MK"); say "HBAO: $R2 | disk: $(disk)"
  MK=$(mark)
  tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.0; shot "a$A-11-gtao-committed"
  R3=$(wait_push_mode 3 "$MK"); say "GTAO: $R3 | disk: $(disk)"

  say "== AO QUALITY: 1x down, X, left (High->Medium), X =="
  MK=$(mark)
  tapb "down" 1.6; shot "a$A-12-quality-row"
  tapb "x" 1.5; tapb "left" 1.5; tapb "x" 2.0; shot "a$A-13-quality-committed"
  R4=$(wait_push_quality 1 "$MK"); say "QUALITY: $R4 | disk: $(disk)"

  say "== AO STRENGTH: 1x down, X, right (Default->Stronger), X =="
  MK=$(mark)
  tapb "down" 1.6; shot "a$A-14-strength-row"
  tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.0; shot "a$A-15-strength-committed"
  R5=$(wait_push_strength 2 "$MK"); say "STRENGTH: $R5 | disk: $(disk)"

  case "$R1$R2$R3$R4$R5" in *MISSING*) return 1 ;; esac
  return 0
}

# --- attempts loop ----------------------------------------------------------------
SEQ_PASS=0; ATT=1
while [ $ATT -le 3 ]; do
  say "== boot (attempt $ATT; ao force props cleared, responsive render seed, fresh reader) =="
  normalize_and_boot "$ATT"
  if do_nav_and_commits "$ATT"; then
    say "[ao-menu-proof2] COMMIT-SEQUENCE PASS (attempt $ATT)"
    SEQ_PASS=1; break
  fi
  say "== attempt $ATT INCOMPLETE (input drop / nav landed wrong) — retrying fresh =="
  ATT=$((ATT+1))
done
if [ "$SEQ_PASS" != 1 ]; then
  say "[ao-menu-proof2] COMMIT-SEQUENCE FAIL after 3 attempts"
fi

say "== back out: 1x down (Back = index 7, from strength row 6), X, then triangle x2 to title =="
tapb "down" 1.6; tapb "x" 2.0
tapb "triangle" 1.5; tapb "triangle" 2.0; shot "16-backed-out"

say "== persist: relaunch; boot push must carry GTAO/Medium/Stronger =="
adb shell am force-stop $PKG; sleep 2
DISK_QUIT=$(disk); say "disk after quit: $DISK_QUIT"
# Disk-persistence assertion: the menu edits (GTAO/Medium/Stronger) must have written to the
# external settings file. AO STRENGTH is the new key — assert (ao-strength 2) landed too.
DISK_OK=1
case "$DISK_QUIT" in *"(ambient-occlusion 3)"*) ;; *) DISK_OK=0; say "  DISK-PERSIST MISS: no (ambient-occlusion 3)";; esac
case "$DISK_QUIT" in *"(ao-quality 1)"*) ;; *) DISK_OK=0; say "  DISK-PERSIST MISS: no (ao-quality 1)";; esac
case "$DISK_QUIT" in *"(ao-strength 2)"*) ;; *) DISK_OK=0; say "  DISK-PERSIST MISS: no (ao-strength 2)";; esac
[ "$DISK_OK" = 1 ] && say "  DISK-PERSIST OK: GTAO/Medium/Stronger on external settings"
# The menu just enabled AO (GTAO) and we force-stopped within 60s -> the sentinel survived
# the dirty death. rm it here so the relaunch runs AO ACTIVE (persisted GTAO), NOT the
# one-shot SAFE-BOOT (AO off) fallback — otherwise the persist proof false-fails.
adb shell rm -f "$SENTINEL" >/dev/null 2>&1
start_lc
RELMARK=0
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 70; stabilize_fg; shot "17-relaunch"
say "disk after relaunch: $(disk)"
say "relaunch [recharged-ao]: $(fresh $RELMARK | grep -a 'recharged-ao' | tail -3 | tr '\n' ' | ')"
# The boot push logs mode/quality/strength together on the first change: the relaunch must
# re-push the persisted STRENGTH Stronger(2) too (mirrors the mode->3 / quality->1 re-push).
REL_STR=$(wait_push_strength 2 "$RELMARK"); say "relaunch strength re-push: $REL_STR"
# If SAFE-BOOT still shows, the sentinel rm was missed/failed and the relaunch ran AO off.
if fresh $RELMARK | grep -aq "SAFE-BOOT"; then
  say "  !!! WARNING: SAFE-BOOT present on relaunch — sentinel rm missed/failed, persist proof INVALID"
fi
fresh $RELMARK | grep -a "AOPERF" | tail -3 | tee -a "$LOGF"
FOCUS_END=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
say "focus at end: $FOCUS_END"
case "$FOCUS_END" in
  *org.opengoal.gk.jak1*) ;;
  *) say "  END-FOCUS NOT JAK1 — crash diagnosis (last fatal/signal lines):"
     adb logcat -d 2>/dev/null | grep -aE 'signal [0-9]+ \(SIG|FATAL EXCEPTION|Fatal signal|beginning of crash' \
       | tail -8 | sed 's/^/  /' | tee -a "$LOGF"
     adb shell "ps -A | grep org.opengoal" 2>/dev/null | tr -d '\r' | sed 's/^/  ps: /' | tee -a "$LOGF" ;;
esac
stop_lc
say "[ao-menu-proof2] SUMMARY: commit-seq=$( [ "$SEQ_PASS" = 1 ] && echo PASS || echo FAIL ) (mode/quality/strength pushes) | disk-persist=$( [ "${DISK_OK:-0}" = 1 ] && echo OK || echo MISS ) | relaunch-strength-repush=${REL_STR:-N/A}"
say "[ao-menu-proof2] DONE (device left running; caller decides reset/force-stop)"
