#!/usr/bin/env bash
# gpbrf2_menu_shot.sh — REOPEN #2 menu-slider proof (owner: "tunables in SETTINGS, not adb props").
# Nav machinery cloned from ao_menu_proof2.sh v3 (edge-triggered long holds, focus-bracketed shots).
# Recharged page rows on this build (FLAG_PBR on, FLAG_HD_MODELS off):
#   0 Master 1 HUD 2 GrassSettings 3 LoadCustomAssets 4 RechargedTextures 5 PBR 6 FoliageWind
#   7 AO 8 AOQ 9 AOS 10 RealtimeLighting 11 BakedAmbient 12 AmbientModel 13 AmbStr 14 AmbContrast
#   15 ShadowDist 16 ShadowQual 17 TEXTURE RELIEF 18 SPECULAR INTENSITY 19 Back
# Proof: (a) screenshots showing the two new rows; (b) LIVE menu edit of TEXTURE RELIEF
# (X, right = +0.25 step, X) must change pbr-texture-relief on the settings.ini on disk.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$OUT/proof-log.txt"; }
die(){ say "[p2-menu FAIL] $*"; exit 1; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ local FB FA
  FB=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null
  FA=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$OUT/$1.focus.txt"
  case "$FB$FA" in *org.opengoal.gk.jak1*) ;; *) say "  SHOT $1 NOT-JAK1 ($FB)";; esac; }
disk_relief(){ adb shell cat "$PCS" 2>/dev/null | tr -d '\r' | grep -aE '^pbr-(texture-relief|specular-intensity) = ' | tr '\n' ' '; echo; }
stabilize_fg(){ local t0=$(date +%s) held=0
  while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
    if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && { say "  foreground STABLE"; return 0; }
    else held=0; adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
      adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 10; fi
    sleep 8
  done; say "  WARN: fg never stabilized"; return 1; }

: > "$OUT/proof-log.txt"
say "== normalize: fused config, sliders 1.5/1.0, responsive render, NO warp =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.pbr.kill 0 >/dev/null 2>&1 || true
adb shell cat "$PCS" > /tmp/p2_menu_pcs.ini 2>/dev/null || die "cannot read $PCS"
tr -d '\r' < /tmp/p2_menu_pcs.ini > /tmp/p2m2.ini && mv /tmp/p2m2.ini /tmp/p2_menu_pcs.ini
sed -i \
  -e 's/^pbr-texture-relief = .*/pbr-texture-relief = 1.5000/' \
  -e 's/^pbr-specular-intensity = .*/pbr-specular-intensity = 1.0000/' \
  -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #t/' \
  -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
  -e 's/^recharged-grass? = #[tf]/recharged-grass? = #f/' \
  /tmp/p2_menu_pcs.ini
grep -qa '^pbr-texture-relief = ' /tmp/p2_menu_pcs.ini || sed -i '/^\[secrets\]/i pbr-texture-relief = 1.5000' /tmp/p2_menu_pcs.ini
grep -qa '^pbr-specular-intensity = ' /tmp/p2_menu_pcs.ini || sed -i '/^\[secrets\]/i pbr-specular-intensity = 1.0000' /tmp/p2_menu_pcs.ini
adb push /tmp/p2_menu_pcs.ini /data/local/tmp/p2_menu_pcs.ini >/dev/null 2>&1 || die "push ini"
adb shell cp /data/local/tmp/p2_menu_pcs.ini "$PCS" || die "cp ini"
say "disk pre: $(disk_relief)"

DOWNS_RECHARGED=8   # dynamic-render-scale seeded #t -> MinTargetFPS row visible
say "== boot to title =="
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 75; stabilize_fg; shot "00-title"

say "== nav: start -> 2x down -> X (OPTIONS) -> down, X (GRAPHIC OPTIONS) =="
tapb "start" 3.0; shot "01-main-menu"
tapb "down"; tapb "down"; tapb "x" 3.0; shot "02-options"
tapb "down"; tapb "x" 3.0; shot "03-graphics"
say "== ${DOWNS_RECHARGED}x down -> RECHARGED SETTINGS, X =="
for i in $(seq 1 "$DOWNS_RECHARGED"); do tapb "down" 1.6; done
shot "04-recharged-row"
tapb "x" 2.5; shot "05-recharged-page"
say "== 17x down = TEXTURE RELIEF row (page scrolled to the new sliders) =="
for i in $(seq 1 17); do tapb "down" 1.6; done
shot "06-texture-relief-row"
say "== LIVE EDIT: X, right (+0.25), X — must land on disk as 1.75 =="
tapb "x" 1.5; shot "07-relief-editing"
tapb "right" 1.5
tapb "x" 2.0; shot "08-relief-committed"
sleep 2
D=$(disk_relief); say "disk post-relief-edit: $D"
case "$D" in *"pbr-texture-relief = 1.75"*) say "RELIEF-EDIT-OK (menu row live-edits + persists)";;
  *) say "RELIEF-EDIT-MISSING (disk: $D)";; esac
say "== 1x down = SPECULAR INTENSITY row =="
tapb "down" 1.6; shot "09-specular-intensity-row"
say "== LIVE EDIT: X, left (-0.1), X — must land on disk as 0.9 =="
tapb "x" 1.5; tapb "left" 1.5; tapb "x" 2.0; shot "10-specint-committed"
sleep 2
D=$(disk_relief); say "disk post-spec-edit: $D"
case "$D" in *"pbr-specular-intensity = 0.9"*) say "SPECINT-EDIT-OK (menu row live-edits + persists)";;
  *) say "SPECINT-EDIT-MISSING (disk: $D)";; esac

say "== restore defaults 1.5/1.0 via the same menu file + quit =="
adb shell am force-stop $PKG; sleep 2
adb shell cp /data/local/tmp/p2_menu_pcs.ini "$PCS" || true
say "disk restored: $(disk_relief)"
say "[p2-menu] DONE"
