#!/usr/bin/env bash
# Gd1_capture_retry.sh — run the cutscene capture, retrying past the known
# intermittent early boot/link flake (sig=4 fn-ptr=0 at title, ~1-in-6), until a
# run cleanly reaches the misty cutscene (frame>=10500, 0 native sigs). Then
# write Gd1/projection-match.txt from the captured device cam log vs the oracle.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL=eae4df44; PKG=org.opengoal.gk.jak1
LOG=.autoport/reports/Gcine-camfov-routed-logcat-run1.log
MAXTRIES="${MAXTRIES:-7}"
good=0
for attempt in $(seq 1 "$MAXTRIES"); do
  echo "===== capture attempt $attempt/$MAXTRIES $(date -Is) ====="
  $ADB -s $SERIAL shell am force-stop $PKG >/dev/null 2>&1 || true
  # Run in its OWN session/process-group: Gd1_run.sh's EXIT trap does `kill 0`
  # (LCP2=0), which would otherwise SIGTERM this wrapper's whole group.
  setsid --wait bash .autoport/Gd1_run.sh 1 < /dev/null || true
  FM=$(grep -a 'A35-RENDER frame=' "$LOG" 2>/dev/null | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
  MISTY=$(grep -ac 'lvl=misty' "$LOG" 2>/dev/null || echo 0)
  CAMM=$(grep -a 'GCINE-CAM' "$LOG" 2>/dev/null | grep -ac 'lvl=misty' || echo 0)
  CR=$(grep -acE "GK-DIAG sig=11|Fatal signal (11|6|4)|signal 4 \(SIGILL\)|signal 6 \(SIGABRT\)|signal 11 \(SIGSEGV\)" "$LOG" 2>/dev/null || echo 0)
  echo "  -> frame=$FM misty_cam_lines=$CAMM crash_sigs=$CR"
  if [ "$FM" -ge 10500 ] && [ "$CAMM" -ge 1 ] && [ "$CR" -eq 0 ]; then
    echo "  -> CLEAN capture reached the cutscene"; good=1; break
  fi
  echo "  -> flaked (early crash/short run); retrying"
  sleep 5
done

echo "===== writing projection-match $(date -Is) ====="
python3 .autoport/lib/gd1_projection_match.py \
  --oracle .autoport/reports/Gcine-audit/x86-cam-shots.log \
  --before .autoport/reports/Gcine-audit/arm64-cam.log \
  --after  .autoport/reports/Gd1/arm64-cam.log \
  --out    .autoport/reports/Gd1/projection-match.txt
PM_RC=$?
echo "===== Gd1_capture_retry DONE good=$good projection_match_rc=$PM_RC $(date -Is) ====="
exit 0
