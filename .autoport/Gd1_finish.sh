#!/usr/bin/env bash
# Gd1_finish.sh — unattended: wait for device CE-unlock, deploy the Gcine-camfov
# fix, capture the cutscene camera, and write Gd1/projection-match.txt. Launch in
# background; it drives the whole remaining pipeline once the owner unlocks.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SERIAL=eae4df44; PKG=org.opengoal.gk.jak1
echo "== Gd1_finish START $(date -Is) =="

# 1. Wait for CE-unlock (cap 8h).
deadline=$(( $(date +%s) + 28800 ))
echo "[finish] waiting for $SERIAL CE-unlock (owner PIN; no reboot)..."
until { st=$($ADB -s $SERIAL shell dumpsys user 2>/dev/null | grep -oE 'RUNNING_(UN)?LOCKED' | head -1 | tr -d '\r'); [ "$st" = RUNNING_UNLOCKED ]; } \
      && $ADB -s $SERIAL shell run-as $PKG ls files >/dev/null 2>&1; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "[finish] TIMEOUT waiting for unlock"; exit 3; }
  sleep 20
done
echo "[finish] UNLOCKED $(date -Is)"

# 2. Deploy (install-if-needed + consistent boot-CGO push + deploy_verify).
bash .autoport/Gd1_deploy.sh || { echo "[finish] deploy FAILED"; exit 4; }

# 3. Capture the cutscene camera + long routed-logcat (Gd1_run.sh).
bash .autoport/Gd1_run.sh 1 || echo "[finish] Gd1_run returned nonzero (continuing to diff)"

# 4. Objective projection re-measure -> Gd1/projection-match.txt.
python3 .autoport/lib/gd1_projection_match.py \
  --oracle .autoport/reports/Gcine-audit/x86-cam-shots.log \
  --before .autoport/reports/Gcine-audit/arm64-cam.log \
  --after  .autoport/reports/Gd1/arm64-cam.log \
  --out    .autoport/reports/Gd1/projection-match.txt
PM_RC=$?
echo "== Gd1_finish DONE $(date -Is) projection_match_rc=$PM_RC =="
exit 0
