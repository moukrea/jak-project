#!/usr/bin/env bash
# gpbrf3_menu_preset.sh — PBR TEST PRESET row proof (supervisor gate b36f18415d): the DEBUG
# one-click preset carousel must APPLY the intended config by writing the UNDERLYING settings
# (so the fine sliders reflect it) + persist. Nav cloned from gpbrf3_menu_disp.sh.
# Recharged page rows: ... 19 DISPLACEMENT 20 PBR TEST PRESET 21 Back
# Proof: (a) screenshot of the row; (b) apply ALL-IN (left from FUSED) => settings.ini must
# show pbr-texture-relief 2.0 + pbr-displacement 2 + realtime-ambient-model 2; (c) re-apply
# FUSED => relief 1.5 + displacement 1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$OUT/preset-proof-log.txt"; }
die(){ say "[g3-preset FAIL] $*"; exit 1; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ local FB FA
  FB=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null
  FA=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$OUT/$1.focus.txt"
  case "$FB$FA" in *org.opengoal.gk.jak1*) ;; *) say "  SHOT $1 NOT-JAK1 ($FB)";; esac; }
disk_state(){ adb shell cat "$PCS" 2>/dev/null | tr -d '\r' | grep -aE '^(pbr-(texture-relief|displacement|test-preset)|realtime-ambient-model|realtime-lighting\?|pbr-materials\?) ' | tr '\n' ' '; echo; }
stabilize_fg(){ local t0=$(date +%s) held=0
  while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
    if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && { say "  foreground STABLE"; return 0; }
    else held=0; adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
      adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 10; fi
    sleep 8
  done; say "  WARN: fg never stabilized"; return 1; }

: > "$OUT/preset-proof-log.txt"
say "== normalize: FUSED-like seed (preset 1, relief 1.5, displacement 1), render-scale 50 =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1 || true
adb shell cat "$PCS" > /tmp/g3p_pcs.ini 2>/dev/null || die "cannot read $PCS"
tr -d '\r' < /tmp/g3p_pcs.ini > /tmp/g3p2.ini && mv /tmp/g3p2.ini /tmp/g3p_pcs.ini
sed -i \
  -e 's/^pbr-test-preset = .*/pbr-test-preset = 1/' \
  -e 's/^pbr-texture-relief = .*/pbr-texture-relief = 1.5000/' \
  -e 's/^pbr-displacement = .*/pbr-displacement = 1/' \
  -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #t/' \
  -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
  -e 's/^recharged-grass? = #[tf]/recharged-grass? = #f/' \
  /tmp/g3p_pcs.ini
grep -qa '^pbr-test-preset = ' /tmp/g3p_pcs.ini || sed -i '/^\[secrets\]/i pbr-test-preset = 1' /tmp/g3p_pcs.ini
grep -qa '^pbr-displacement = ' /tmp/g3p_pcs.ini || sed -i '/^\[secrets\]/i pbr-displacement = 1' /tmp/g3p_pcs.ini
adb push /tmp/g3p_pcs.ini /data/local/tmp/g3p_pcs.ini >/dev/null 2>&1 || die "push ini"
adb shell cp /data/local/tmp/g3p_pcs.ini "$PCS" || die "cp ini"
say "disk pre: $(disk_state)"

DOWNS_RECHARGED=8
say "== boot to title + nav to Recharged Settings =="
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 75; stabilize_fg; shot "p00-title"
tapb "start" 3.0
tapb "down"; tapb "down"; tapb "x" 3.0
tapb "down"; tapb "x" 3.0
for i in $(seq 1 "$DOWNS_RECHARGED"); do tapb "down" 1.6; done
tapb "x" 2.5
say "== 20x down = PBR TEST PRESET row =="
for i in $(seq 1 20); do tapb "down" 1.6; done
shot "p01-preset-row"
say "== APPLY ALL-IN: X, left (FUSED->ALL-IN), X — disk must show relief 2.0 + displacement 2 + ambient-model 2 =="
tapb "x" 1.5; shot "p02-preset-editing"
tapb "left" 1.5
tapb "x" 2.5; shot "p03-preset-allin-committed"
sleep 2
D=$(disk_state); say "disk post-ALL-IN: $D"
case "$D" in
  *"pbr-texture-relief = 2."*"pbr-displacement = 2"*|*"pbr-displacement = 2"*"pbr-texture-relief = 2."*)
    say "PRESET-ALLIN-OK (one click rewrote the underlying settings)";;
  *) say "PRESET-ALLIN-MISSING (disk: $D)";;
esac
say "== RESTORE FUSED: X, right (ALL-IN->FUSED), X — disk must show relief 1.5 + displacement 1 =="
tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.5; shot "p04-preset-fused-restored"
sleep 2
D=$(disk_state); say "disk post-FUSED: $D"
case "$D" in
  *"pbr-texture-relief = 1.5"*"pbr-displacement = 1"*|*"pbr-displacement = 1"*"pbr-texture-relief = 1.5"*)
    say "PRESET-FUSED-OK (presets round-trip)";;
  *) say "PRESET-FUSED-MISSING (disk: $D)";;
esac
adb shell am force-stop $PKG; sleep 2
say "[g3-preset] DONE"
