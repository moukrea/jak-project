#!/usr/bin/env bash
# Robust self-heal: relaunch the orchestrator only after 2 consecutive 'dead' checks (avoids transient race).
cd /home/emeric/code/jak-project || exit 1
ADB=/home/emeric/Android/platform-tools/adb
LOG=.autoport/self_heal.log
dead=0
while true; do
  if pgrep -f 'python -u .autoport/orchestrator' >/dev/null 2>&1; then
    dead=0
  else
    dead=$((dead+1))
    if [ "$dead" -ge 2 ]; then
      if $ADB devices 2>/dev/null | grep -qE 'eae4df44[[:space:]]+device'; then
        $ADB -s eae4df44 shell svc power stayon true >/dev/null 2>&1 || true
        W=$(git status --porcelain -- 'goal_src/**' 'game/**' 'android/**' 'goalc/**' 2>/dev/null | awk '{print $2}')
        [ -n "$W" ] && git restore $W 2>/dev/null
        setsid bash ./launch.sh --quiet </dev/null >/dev/null 2>&1 &
        echo "$(date '+%m-%d %H:%M:%S') SELF-HEAL relaunched orchestrator (WIP cleaned: ${W:-none})" >> "$LOG"
        dead=0; sleep 60
      else
        echo "$(date '+%m-%d %H:%M:%S') orchestrator down but DEVICE GONE — waiting" >> "$LOG"
        dead=1
      fi
    fi
  fi
  sleep 90
done
