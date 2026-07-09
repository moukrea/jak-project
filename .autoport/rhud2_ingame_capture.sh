#!/usr/bin/env bash
# rhud2_ingame_capture.sh — Grecharged-hud-jak1 in-game HUD evidence (eae4df44).
# Follow-up to rhud2_device_verify.sh run7: that run proved menu/toggle/persistence but
# its in-game sections were stranded in the Recharged submenu (circle-back is swallowed
# there — can-go-back? whitelist lacks recharged-settings; RETOUR still works).
# This script avoids menu back-out entirely by using the f1.warp hook per round:
#  0: push fresh *COMMON.TXT/*SUBTIT.TXT from out/jak1/iso (device text was stale ->
#     FR ids 1706/1707 missing -> EN fallback labels in the FR menu)
#  1: warp OFF boot -> menu shots with FR labels (+ toggle still OUI = persisted)
#  2: ON round — debug.opengoal.f1.warp=1 (Geyser Rock game-start, bypasses intro) +
#     debug.opengoal.mouche.buzz=1 (real scout-fly collect at Jak ~5s after control)
#     -> walk bursts toward the blue-eco path, shots every burst
#  3: OFF round — settings recharged-hud? #t->#f pushed, same warp+walk -> stock HUD A/B
#  4: restore recharged-hud? #t (owner keeps it ON), clear props
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/shots"; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$SHOTS/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-50}s..."; sleep "${1:-50}"; }
push_appfile(){ # $1 local, $2 device path relative to app home
  local bn want got; bn=$(basename "$1"); want=$(sha256sum "$1" | awk '{print $1}')
  adb push "$1" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; return 1; }
  adb shell run-as $PKG cp "/data/local/tmp/$bn" "$2" || { echo "  CP-FAIL $bn"; return 1; }
  adb shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
  got=$(adb shell run-as $PKG sha256sum "$2" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$got" = "$want" ] || { echo "  SHA-MISMATCH $bn"; return 1; }
}
nav_to_graphics(){ tapb start 2.2; tapb down; tapb down; tapb x 2.0; tapb down; tapb x 2.0; }
nav_to_recharged_row(){ for i in 1 2 3 4 5 6 7 8; do tapb down 0.5; done; }
walk_and_shoot(){ # $1 shot prefix, $2 bursts
  local i; for i in $(seq 1 "$2"); do
    inject "ly=0"; sleep 2.5; clr; sleep 0.8
    shot "$1-walk$i"
  done
}

adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi

echo "== 0. push fresh text files (FR 1706/1707) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
fail=0; cnt=0
for f in out/jak1/iso/*COMMON.TXT out/jak1/iso/*SUBTIT.TXT; do
  [ -f "$f" ] || continue
  push_appfile "$f" "files/iso_data/jak1/$(basename "$f")" || fail=1
  cnt=$((cnt+1))
done
[ "$fail" -eq 0 ] || { echo "TXT push failed"; exit 1; }
echo "  pushed + sha256-verified $cnt text files"
n=$(adb shell run-as $PKG cat files/iso_data/jak1/1COMMON.TXT 2>/dev/null | strings | grep -c RECHARG || true)
echo "  device 1COMMON.TXT RECHARG hits: $n (want >=2)"

echo "== 1. menu shots with FR labels (warp off; toggle should read OUI from run7) =="
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell setprop debug.opengoal.mouche.buzz 0 || true
boot 55
nav_to_graphics
nav_to_recharged_row
shot G1-menu-FR-recharged-row
tapb x 1.5
shot G2-menu-FR-submenu-persist-OUI
# leave via RETOUR (down + x) — the circle-back whitelist gap makes circle a no-op here
tapb down 0.8; tapb x 1.5
shot G3-menu-back-via-RETOUR

echo "== 2. ON round: Geyser warp + scout-fly collect + eco walk =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 1 || true
adb shell setprop debug.opengoal.mouche.buzz 1 || true
boot 90
shot E1-ingame-ON-spawn
sleep 6; shot E2-ingame-ON-flycollect
walk_and_shoot E3-ingame-ON 6
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|MOUCHE|recharged-hud|Fatal signal|GK-DIAG sig=' > "$OUT/device-ingame-ON-logcat.txt" || true
echo "  ON logcat markers:"; grep -acE 'F1-WARP' "$OUT/device-ingame-ON-logcat.txt" | xargs echo "   f1-warp lines:"; grep -acE 'MOUCHE' "$OUT/device-ingame-ON-logcat.txt" | xargs echo "   mouche lines:"

echo "== 3. OFF round: settings #t->#f, same warp+walk (stock HUD baseline) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/rhud2-settings-on.gc
grep -q '(recharged-hud? #t)' /tmp/rhud2-settings-on.gc || { echo "settings missing ON flag?"; cat /tmp/rhud2-settings-on.gc | grep recharged; }
sed 's/(recharged-hud? #t)/(recharged-hud? #f)/' /tmp/rhud2-settings-on.gc > /tmp/rhud2-settings-off.gc
push_appfile /tmp/rhud2-settings-off.gc "$SETF" || { echo "settings push failed"; exit 1; }
echo "  device flag now: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
adb logcat -c >/dev/null 2>&1 || true
boot 90
shot F1-ingame-OFF-spawn
sleep 6; shot F2-ingame-OFF-flycollect
walk_and_shoot F3-ingame-OFF 6
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|MOUCHE|recharged-hud|Fatal signal|GK-DIAG sig=' > "$OUT/device-ingame-OFF-logcat.txt" || true

echo "== 4. restore ON for the owner + clear props =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
push_appfile /tmp/rhud2-settings-on.gc "$SETF" || echo "  WARN: restore push failed"
echo "  device flag restored: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell setprop debug.opengoal.mouche.buzz 0 || true
echo "[rhud2-ingame] DONE. Shots:"
ls -la "$SHOTS"/device-{G,E,F}*.png 2>/dev/null
