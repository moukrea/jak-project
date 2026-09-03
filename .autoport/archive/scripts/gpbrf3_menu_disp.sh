#!/usr/bin/env bash
# gpbrf3_menu_disp.sh — REOPEN #3 DISPLACEMENT carousel menu proof (nav machinery cloned
# from gpbrf2_menu_shot.sh, which proved rows 17/18). Recharged page rows on this build
# (FLAG_PBR on, FLAG_HD_MODELS off):
#   ... 16 ShadowQual 17 TEXTURE RELIEF 18 SPECULAR INTENSITY 19 DISPLACEMENT 20 Back
# Proof: (a) screenshot of the DISPLACEMENT row; (b) LIVE carousel edit (X, right =
# Parallax->Tessellation, X) must change pbr-displacement on settings.ini to 2; then
# restore to 1 (left) and verify.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$OUT/disp-proof-log.txt"; }
die(){ say "[g3-menu FAIL] $*"; exit 1; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ local FB FA
  FB=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null
  FA=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$OUT/$1.focus.txt"
  case "$FB$FA" in *org.opengoal.gk.jak1*) ;; *) say "  SHOT $1 NOT-JAK1 ($FB)";; esac; }
disk_disp(){ adb shell cat "$PCS" 2>/dev/null | tr -d '\r' | grep -aE '^pbr-displacement = '; }
stabilize_fg(){ local t0=$(date +%s) held=0
  while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
    if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && { say "  foreground STABLE"; return 0; }
    else held=0; adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
      adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 10; fi
    sleep 8
  done; say "  WARN: fg never stabilized"; return 1; }

: > "$OUT/disp-proof-log.txt"
say "== normalize: no warp props, displacement seeded 1, render-scale 50 for responsiveness =="
adb shell am force-stop $PKG; sleep 2
adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.pbr.kill 0 >/dev/null 2>&1 || true
adb shell cat "$PCS" > /tmp/g3m_pcs.ini 2>/dev/null || die "cannot read $PCS"
tr -d '\r' < /tmp/g3m_pcs.ini > /tmp/g3m2.ini && mv /tmp/g3m2.ini /tmp/g3m_pcs.ini
sed -i \
  -e 's/^pbr-displacement = .*/pbr-displacement = 1/' \
  -e 's/^dynamic-render-scale? = #[tf]/dynamic-render-scale? = #t/' \
  -e 's/^render-scale = [0-9.]*/render-scale = 50.0000/' \
  -e 's/^recharged-grass? = #[tf]/recharged-grass? = #f/' \
  /tmp/g3m_pcs.ini
grep -qa '^pbr-displacement = ' /tmp/g3m_pcs.ini || sed -i '/^\[secrets\]/i pbr-displacement = 1' /tmp/g3m_pcs.ini
adb push /tmp/g3m_pcs.ini /data/local/tmp/g3m_pcs.ini >/dev/null 2>&1 || die "push ini"
adb shell cp /data/local/tmp/g3m_pcs.ini "$PCS" || die "cp ini"
say "disk pre: $(disk_disp)"

DOWNS_RECHARGED=8   # dynamic-render-scale seeded #t -> MinTargetFPS row visible
say "== boot to title =="
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 75; stabilize_fg; shot "d00-title"
say "== nav: start -> 2x down -> X (OPTIONS) -> down, X (GRAPHIC OPTIONS) =="
tapb "start" 3.0
tapb "down"; tapb "down"; tapb "x" 3.0
say "== ${DOWNS_RECHARGED}x down -> RECHARGED SETTINGS, X =="
tapb "down"; tapb "x" 3.0
for i in $(seq 1 "$DOWNS_RECHARGED"); do tapb "down" 1.6; done
tapb "x" 2.5; shot "d01-recharged-page"
say "== 19x down = DISPLACEMENT row =="
for i in $(seq 1 19); do tapb "down" 1.6; done
shot "d02-displacement-row"
say "== LIVE EDIT: X, right (Parallax->Tessellation), X — disk must show 2 =="
tapb "x" 1.5; shot "d03-displacement-editing"
tapb "right" 1.5
tapb "x" 2.0; shot "d04-displacement-committed"
sleep 2
D=$(disk_disp); say "disk post-edit: $D"
case "$D" in *"pbr-displacement = 2"*) say "DISP-EDIT-OK (carousel live-edits + persists Tessellation)";;
  *) say "DISP-EDIT-MISSING (disk: $D)";; esac
say "== restore: X, left (Tessellation->Parallax), X — disk must show 1 =="
tapb "x" 1.5; tapb "left" 1.5; tapb "x" 2.0; shot "d05-displacement-restored"
sleep 2
D=$(disk_disp); say "disk post-restore: $D"
case "$D" in *"pbr-displacement = 1"*) say "DISP-RESTORE-OK";;
  *) say "DISP-RESTORE-MISSING (disk: $D)";; esac
adb shell am force-stop $PKG; sleep 2
say "[g3-menu] DONE"
