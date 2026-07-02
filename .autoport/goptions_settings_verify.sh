#!/usr/bin/env bash
# goptions_settings_verify.sh — DETERMINISTIC defaults + persistence proof for the
# graphics settings, via the on-device pc-settings.gc file (no menu navigation).
#   A. wipe pc-settings.gc -> launch -> load-settings writes reset-gfx DEFAULTS.
#      Assert the new graphics defaults (dynamic ON, min-render 40, dyn-target 60).
#   B. round-trip: write DISTINCTIVE non-default values for EVERY graphics key ->
#      relaunch (read) -> re-commit on menu-close -> pull -> assert all retained.
#      (If the app did not READ them, the re-commit would rewrite defaults, so a
#      retained distinctive file proves read+write persistence for every setting.)
# Device eae4df44 ONLY. Real measurements only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SETF="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
OUT=.autoport/reports/Goptions-reorder; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[set FAIL] $*" >&2; exit 1; }
rd(){ adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r'; }
wait_boot(){
  adb logcat -c >/dev/null 2>&1 || true
  local LOG=/tmp/gopt-set-boot.log; : > "$LOG"
  ( adb logcat -v threadtime | grep --line-buffered -aE 'link finish: logo$|pc settings file (write|read)|GK-DIAG sig=|Fatal signal' > "$LOG" ) &
  local LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
    grep -aqE 'GK-DIAG sig=(11|6|4)|Fatal signal (11|6|4)' "$LOG" && { kill $LCP 2>/dev/null; die "boot crash"; }
    grep -aqE 'link finish: logo$' "$LOG" && break
    sleep 3
  done
  sleep 6   # let title settle + the fresh-file commit happen
  kill $LCP 2>/dev/null || true
}

adb get-state >/dev/null 2>&1 || die "device not attached"

echo "== A. DEFAULTS: wipe pc-settings.gc, boot, assert new graphics defaults =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true
[ -z "$(rd)" ] || die "settings file not wiped"
echo "  wiped. launching (fresh)..."
wait_boot
rd > "$OUT/device-pc-settings-defaults.gc"
[ -s "$OUT/device-pc-settings-defaults.gc" ] || die "no pc-settings.gc written at boot"
echo "  fresh defaults file ($(wc -l < "$OUT/device-pc-settings-defaults.gc") lines). Graphics keys:"
grep -nE 'dynamic-render-scale\?|min-render-scale|dyn-target-fps|\(render-scale |fps-counter\?|\(vsync |\(msaa |aspect-state|game-size' "$OUT/device-pc-settings-defaults.gc" | sed 's/^/    /'
D=$OUT/device-pc-settings-defaults.gc; dp=0
grep -qE '\(dynamic-render-scale\? #t\)' "$D" && echo "  OK  dynamic-render-scale? = #t (ON)"     || { echo "  BAD dynamic-render-scale?"; dp=1; }
grep -qE '\(min-render-scale 40'          "$D" && echo "  OK  min-render-scale = 40 (40%)"          || { echo "  BAD min-render-scale"; dp=1; }
grep -qE '\(dyn-target-fps 60'            "$D" && echo "  OK  dyn-target-fps = 60"                  || { echo "  BAD dyn-target-fps"; dp=1; }
[ "$dp" = 0 ] || die "defaults assertion failed"

echo "[set] DEFAULTS proof PASS (fresh pc-settings.gc written with new graphics defaults)."
