#!/usr/bin/env bash
# grv_repeat.sh — repeat the crate-stand scenario until the POST-SPAWN crash
# reproduces (boot-link flakes crash BEFORE LEVEL-WARP-SPAWN and are retried,
# counted separately). Stops on the first post-spawn crash with evidence.
# Usage: grv_repeat.sh <base_tag> [max_attempts] [watch_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
BASE="${1:-crate}"
MAXA="${2:-6}"
WATCH="${3:-180}"
OUT=.autoport/reports/Gcrash-rockvillage
FLAKES=0
for a in $(seq 1 "$MAXA"); do
  TAG="$BASE$a"
  echo "=== attempt $a/$MAXA tag=$TAG (flakes so far: $FLAKES) ==="
  # owner-like load: buzzer collect (~+5s), wander at the crate (state churn) +
  # eco births (sparticle traffic) while the hooks replay the boundary sequence
  # (load swamp -> display -> vis), then walk the SOUTH leg past the display/vis
  # band to swamp-start — the exact "walking further" the owner did.
  TASK_CLOSE=33 WANT_LEVELS='village2,swamp' WANT_LEVELS_DELAY=1800 \
  WANT_DISPLAY='swamp,display' WANT_DISPLAY_DELAY=2700 \
  WANT_VIS='swa' WANT_VIS_DELAY=3300 \
  MOUCHE_BUZZ=1 ECO_SPAWN='3 300' MAX_STEPS=70 REACH_Z=-7310000 \
  WAYPOINTS='1778073,-7147000;1819000,-7187660;1778073,-7227000;1740000,-7187660;1778073,-7187660;1822720,-7258112;1842537,-7333297' \
    bash .autoport/lib/grv_run.sh "$TAG" "$WATCH" "434.1 3 -1754.8"
  L="$OUT/$TAG-logcat.log"
  if ! grep -qaE 'Fatal signal|GK-DIAG sig=' "$L"; then
    if grep -qa 'GRV-CANARY ANOMALY' "$L"; then
      echo "=== attempt $a: NO CRASH but CANARY ANOMALY (stomp bracketed!) ==="
      grep -a 'GRV-CANARY' "$L" | head -20
    else
      echo "=== attempt $a: NO CRASH (full scenario survived) ==="
    fi
    continue
  fi
  if grep -qa 'LEVEL-WARP-SPAWN' "$L"; then
    echo "=== attempt $a: POST-SPAWN CRASH captured (tag=$TAG) ==="
    grep -aE 'GK-DIAG sig=|GRV-SP|GRV-NAME|grv-.*-bare|GRV-CANARY|A38.*nearest' "$L" | head -40
    echo "REPEAT-RESULT: POST-SPAWN-CRASH tag=$TAG flakes=$FLAKES attempt=$a"
    exit 0
  fi
  FLAKES=$((FLAKES+1))
  echo "=== attempt $a: boot-link flake (crash before spawn) — retrying ==="
done
echo "REPEAT-RESULT: NO-POST-SPAWN-CRASH after $MAXA attempts (flakes=$FLAKES)"
exit 1
