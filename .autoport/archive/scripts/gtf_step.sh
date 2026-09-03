#!/usr/bin/env bash
# Gtouch-fix interactive step helper: one real `adb input tap`, settle, screencap,
# and echo the Gtm-tap log lines it produced. Used by the manager one step at a
# time (screenshot-verified, no blind choreography).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44
OUT=.autoport/reports/Gtouch-fix/shots2; mkdir -p "$OUT"
X=$1; Y=$2; NAME=$3; SETTLE="${4:-2.0}"
"$ADB" -s "$S" logcat -c 2>/dev/null || true
echo ">> input tap $X $Y  ($NAME)"
"$ADB" -s "$S" shell input tap "$X" "$Y"
sleep "$SETTLE"
"$ADB" -s "$S" exec-out screencap -p > "$OUT/$NAME.png" 2>/dev/null
"$ADB" -s "$S" logcat -d 2>/dev/null | grep -aE 'Gtm-tap|onMenuTap' | tail -4
echo "fg=$("$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')"
