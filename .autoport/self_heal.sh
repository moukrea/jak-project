#!/usr/bin/env bash
# Self-heal with quota/outage backoff. Relaunch the orchestrator on death, but if a relaunch dies
# FAST (<8min, = weekly-quota/outage crash-loop) back off 30min instead of thrashing every ~4min.
cd /home/emeric/code/jak-project || exit 1
ADB=/home/emeric/Android/platform-tools/adb
LOG=.autoport/self_heal.log
dead=0; last_relaunch=0
while true; do
  if pgrep -f 'python -u .autoport/orchestrator' >/dev/null 2>&1; then
    dead=0
  else
    dead=$((dead+1))
    if [ "$dead" -ge 2 ]; then
      now=$(date +%s)
      if [ "$last_relaunch" -ne 0 ] && [ $((now - last_relaunch)) -lt 480 ]; then
        echo "$(date '+%m-%d %H:%M:%S') fast-death $((now-last_relaunch))s after relaunch (likely weekly-quota/outage) — backing off 30m" >> "$LOG"
        sleep 1800; dead=0; continue
      fi
      if $ADB devices 2>/dev/null | grep -qE 'eae4df44[[:space:]]+device'; then
        $ADB -s eae4df44 shell svc power stayon true >/dev/null 2>&1 || true
        W=$(git status --porcelain -- 'goal_src/**' 'game/**' 'android/**' 'goalc/**' 2>/dev/null | awk '{print $2}')
        [ -n "$W" ] && git restore $W 2>/dev/null
        setsid bash ./launch.sh --quiet </dev/null >/dev/null 2>&1 &
        last_relaunch=$(date +%s)
        echo "$(date '+%m-%d %H:%M:%S') SELF-HEAL relaunched orchestrator (WIP cleaned: ${W:-none})" >> "$LOG"
        dead=0; sleep 60
      else
        echo "$(date '+%m-%d %H:%M:%S') down but DEVICE GONE — waiting" >> "$LOG"
        dead=1; sleep 60
      fi
    fi
  fi
  sleep 90
done
