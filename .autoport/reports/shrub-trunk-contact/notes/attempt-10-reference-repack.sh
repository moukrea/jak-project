#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-shrub-reference-602cd
LOCK="$PWD/.autoport/.deploy-in-progress"
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
trap 'rm -f "$LOCK"' EXIT
cd android
./gradlew assembleJak1Debug -PslimIso=true -x :app:buildNativeLibs -x :app:configureNativeLibs -x :app:bundleJak1CustomPack </dev/null
