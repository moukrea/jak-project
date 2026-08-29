#!/usr/bin/env bash
# gls_wait_device.sh — Gloading-screen: wait for the Redmi eae4df44 ONLY.
# The Shield (192.168.1.32) is FORBIDDEN (owner 2026-08-28): never connect to it,
# never substitute it. If eae4df44 returns, run deploy_verify and record the result.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
WAIT_S="${1:-1500}"
OUT=.autoport/reports/Gloading-screen/device-wait.txt
mkdir -p "$(dirname "$OUT")"
t0=$(date +%s)
echo "[$(date '+%F %T')] waiting up to ${WAIT_S}s for $S (Shield 192.168.1.32 excluded by owner policy)" > "$OUT"
while :; do
  if "$ADB" devices 2>/dev/null | grep -qE "^${S}[[:space:]]+device$"; then
    echo "[$(date '+%F %T')] $S IS BACK — running deploy_verify" >> "$OUT"
    bash .autoport/lib/deploy_verify.sh "$S" jak1 >> "$OUT" 2>&1
    echo "deploy_verify exit=$?" >> "$OUT"
    exit 0
  fi
  now=$(date +%s); [ $((now - t0)) -ge "$WAIT_S" ] && break
  sleep 20
done
echo "[$(date '+%F %T')] TIMEOUT after ${WAIT_S}s — $S never reappeared on the USB bus" >> "$OUT"
exit 2
