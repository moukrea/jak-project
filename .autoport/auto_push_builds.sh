#!/usr/bin/env bash
# Continuously ship intermediate builds to jak-builds so the owner never waits.
# Owner 2026-08-06: "n'hésite pas à pousser les builds intermédiaires au fil de l'eau que je teste aussi"
# Uploads only when the APK's content hash actually changed, and never while a build is mid-write.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
# The HD asset pack is a SEPARATE deliverable: the reskin (skin-authority fix) is baked
# into the HD models, so it ships in this zip and NOT in the APK. Watching only the APK
# once shipped an "updated" build whose main change the owner could not possibly see.
ZIP=out/artifacts/jak1_hd_assets.zip
DIST=.autoport/dist/app-jak1-HD-recharged.apk
LOG=.autoport/logs/auto_push_builds.txt
LAST=""
[ -f "$APK" ] && LAST=$(md5sum "$APK" | cut -d' ' -f1)
echo "$(date +%H:%M:%S) watcher started (baseline ${LAST:0:8})" >> "$LOG"
while true; do
  sleep 300
  [ -f "$APK" ] || continue
  # settle: size must be stable across two reads, otherwise gradle is still writing
  s1=$(stat -c %s "$APK"); sleep 20; s2=$(stat -c %s "$APK")
  [ "$s1" = "$s2" ] || continue
  h=$(md5sum "$APK" | cut -d' ' -f1)
  [ "$h" = "$LAST" ] && continue
  # Never upload a partially-written artifact. Match an ACTIVE build only:
  # the long-lived Gradle DAEMON must not count (it runs for hours and would
  # block every upload forever - that bug held back the 20:20 APK).
  # Match a real build process only. Two traps already hit: the long-lived Gradle
  # DAEMON (runs for hours), and the worker's own `claude -p` whose PROMPT TEXT
  # contains the literal words "cmake --build" — ps sees the prompt, so the watcher
  # thought a build was running forever and never uploaded anything.
  if ps -eo comm,args | grep -vE '^claude ' \
       | grep -qE '^(cmake|ninja|cc1plus|java)[^\n]*(--build|assemble|GradleWrapperMain)'; then continue; fi
  cp "$APK" "$DIST" || continue
  UP=("$DIST")
  if [ -f "$ZIP" ]; then
    zh=$(md5sum "$ZIP" | cut -d' ' -f1)
    [ "$zh" != "${LASTZIP:-}" ] && { UP+=("$ZIP"); LASTZIP="$zh"; }
  fi
  if timeout 1800 gh release upload jak1-rtlight-wip "${UP[@]}" \
       --repo moukrea/jak-builds --clobber >>"$LOG" 2>&1; then
    LAST="$h"
    echo "$(date +%H:%M:%S) PUSHED ${h:0:8} ($(numfmt --to=iec "$s2" 2>/dev/null || echo "$s2"))" >> "$LOG"
  else
    echo "$(date +%H:%M:%S) upload FAILED ${h:0:8}" >> "$LOG"
  fi
done
