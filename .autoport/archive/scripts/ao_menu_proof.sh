#!/usr/bin/env bash
# ao_menu_proof.sh — Grecharged-ambient-occlusion OWNER PROOF (a): the REAL menu chain.
# One uninterrupted run (the title menu idle-times-out, so no pauses for eyeballing):
# boot -> title menu -> graphics -> Recharged Settings -> AO row (4 downs: the ENHANCED
# MODELS row is hidden while the feature is recalled) -> commit SSAO, HBAO, GTAO in turn
# (each commit must emit a [recharged-ao] mode -> N line = GOAL->C++ push) -> AO QUALITY
# High->Medium (quality -> 1) -> back out -> relaunch -> persisted values re-pushed at boot.
# Screenshots are taken at every step for post-hoc verification.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-ambient-occlusion/menu-proof; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
disk(){ adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -oE "^(ambient-occlusion|ao-quality) = [0-9]+" | tr '\n' ' '; echo; }
aolines(){ adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "recharged-ao" | tail -6; }

LOGF="$OUT/proof-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }

say "== boot (props cleared, fresh logcat) =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.ao.force_mode '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.ao.force_quality '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp '""'; adb shell setprop debug.opengoal.level.warp.pos '""'
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
say "disk pre: $(disk)"
sleep 75; shot 00-title
say "boot [recharged-ao]: $(aolines)"

say "== nav to AO row (start, 2x down, X, down, X, 7x down, X, 4x down) =="
tapb "start" 2.5
tapb "down" 0.7; tapb "down" 0.7; tapb "x" 2.0        # OPTIONS
tapb "down" 0.8; tapb "x" 2.0                          # GRAPHIC OPTIONS
for i in $(seq 1 7); do tapb "down" 0.55; done         # RECHARGED SETTINGS row
tapb "x" 1.8                                           # enter recharged page
for i in $(seq 1 4); do tapb "down" 0.55; done         # AO row (enhanced-models row hidden)
shot 01-ao-row

say "== AO edits: Off->SSAO->HBAO->GTAO (X, right, X each) =="
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 02-ssao
say "after SSAO commit: disk $(disk) | $(aolines)"
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 03-hbao
say "after HBAO commit: disk $(disk) | $(aolines)"
tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6; shot 04-gtao
say "after GTAO commit: disk $(disk) | $(aolines)"

say "== AO QUALITY: High->Medium (down, X, left, X) =="
tapb "down" 0.8; shot 05-quality-row
tapb "x" 0.9; tapb "left" 0.9; tapb "x" 1.6; shot 06-quality-medium
say "after quality commit: disk $(disk) | $(aolines)"

say "== back out (down to Retour, X, triangle x2) =="
tapb "down" 0.8; tapb "x" 1.6
tapb "triangle" 1.2; tapb "triangle" 1.5; shot 07-backed-out

say "== persist: relaunch, boot-time push must carry the menu values =="
adb shell am force-stop $PKG; sleep 2
adb logcat -c 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 70; shot 08-relaunch
say "disk after relaunch: $(disk)"
say "relaunch [recharged-ao]: $(aolines)"
AOPERF=$(adb logcat -d -v brief opengoal-gk:I '*:S' 2>/dev/null | grep -a "AOPERF" | tail -3)
say "relaunch AOPERF: $AOPERF"
adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' | tee -a "$LOGF"
say "[ao-menu-proof] DONE"
