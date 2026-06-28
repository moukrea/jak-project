#!/usr/bin/env bash
# cc_pull_dump.sh — pull the owner-play collision-glitch dump off the device.
# The instrumented capture build writes /data/data/<pkg>/files/collision_glitch.txt
# (flush+fsync per glitch hit) during the owner's REAL play. This copies it out via
# run-as (adb pull cannot read app-private paths directly).
# Usage: bash .autoport/reports/Gcollision-glitchcapture/cc_pull_dump.sh [dest]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
DEST="${1:-.autoport/reports/Gcollision-glitchcapture/collision_glitch.txt}"
$ADB -s "$S" get-state >/dev/null 2>&1 || { echo "device $S not attached"; exit 1; }
if ! $ADB -s "$S" shell "run-as $PKG test -f files/collision_glitch.txt" 2>/dev/null; then
  echo "no dump yet: files/collision_glitch.txt does not exist (owner has not triggered a glitch)"; exit 3
fi
# MIUI sandbox denies the app uid writing /data/local/tmp, so 'run-as cp' there fails. Stream the
# file straight out via exec-out (binary-safe, byte-exact) instead.
$ADB -s "$S" exec-out "run-as $PKG cat files/collision_glitch.txt" > "$DEST" 2>/dev/null
[ -s "$DEST" ] || { echo "pull produced an empty file ($DEST) — is the app debuggable + device unlocked?"; exit 1; }
n=$(grep -c '^=== GLITCH' "$DEST" 2>/dev/null || echo 0)
f=$(grep -c '^F ' "$DEST" 2>/dev/null || echo 0)
echo "pulled $DEST : $n glitch triggers, $f frame records"
echo "trigger summary:"; grep '^=== GLITCH' "$DEST" | sed -E 's/=== GLITCH #[0-9]+ //; s/ ===$//' | awk '{print $2}' | sort | uniq -c
