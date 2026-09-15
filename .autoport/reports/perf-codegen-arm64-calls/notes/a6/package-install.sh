#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
exec 8>.autoport/.delivery-artifacts.lock
flock -n -x 8 || exit 3
LOCK="$PWD/.autoport/.deploy-in-progress"
if [ -e "$LOCK" ]; then
  p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then exit 3; fi
  unlink "$LOCK"
fi
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
trap 'unlink "$LOCK"' EXIT
export TMPDIR="$PWD/.autoport/reports/perf-codegen-arm64-calls/notes/a6/tmp"
cd android
./gradlew assembleJak1Debug -x buildNativeLibs -x configureNativeLibs > "$TMPDIR/../package-apk.log" 2>&1
cd ..
CODEGEN_USB=$(bash .autoport/lib/pick_device.sh)
printf 'serial=%s\n' "$CODEGEN_USB"
timeout 120 /home/emeric/Android/platform-tools/adb -s "$CODEGEN_USB" install -r -d -t android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
