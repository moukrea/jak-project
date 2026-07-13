#!/usr/bin/env bash
# evtrial_repeat.sh — Phase Gjak1-intermittent-events N-run aggregator.
# Runs evtrial_run.sh N times on one arm/continue point (with a thermal pause
# between trials) and rolls the per-run EVTRIAL-RESULT lines into a single
# EVTRIAL-RATE line — the intermittent-event trials need repetition to expose a
# flake rate, and the icache A/B needs matched-N arms to compare.
# Usage: evtrial_repeat.sh <base_tag> <arm> <cont> <N> [posm] [watch_s]
# Env:   EVFILTER, CRITERIA (passed through to each run)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
BASE="${1:-evrun}"
ARM="${2:-flush}"
CONT="${3:-village1}"
N="${4:-5}"
POSM="${5-}"
WATCH_S="${6:-50}"
OUT_DIR="${OUT_DIR:-.autoport/reports/Gjak1-intermittent-events}"
mkdir -p "$OUT_DIR"
export OUT_DIR
RUN=.autoport/lib/evtrial_run.sh

ok=0; boot_crash=0; warp_fail=0; post_crash=0; other=0
fired_x=0; fired_y=0
for i in $(seq 1 "$N"); do
  echo "=== $BASE run $i/$N (arm=$ARM cont=$CONT) ==="
  bash "$RUN" "${BASE}-$i" "$ARM" "$CONT" "$POSM" "$WATCH_S" || true
  RES="$OUT_DIR/${BASE}-$i-result.txt"
  LINE=""
  [ -f "$RES" ] && LINE=$(grep -aoE 'EVTRIAL-RESULT .*' "$RES" | tail -1)
  case "$LINE" in
    *status=OK*)               ok=$((ok+1));;
    *status=BOOT-CRASH*)       boot_crash=$((boot_crash+1));;
    *status=WARP-FAIL*)        warp_fail=$((warp_fail+1));;
    *status=POST-SPAWN-CRASH*) post_crash=$((post_crash+1));;
    *)                         other=$((other+1));;
  esac
  # accumulate fired=x/y (skip 'na')
  FV=$(printf '%s\n' "$LINE" | sed -nE 's/.*fired=([0-9]+)\/([0-9]+).*/\1 \2/p')
  if [ -n "$FV" ]; then
    fx=$(echo "$FV" | awk '{print $1}'); fy=$(echo "$FV" | awk '{print $2}')
    fired_x=$((fired_x+fx)); fired_y=$((fired_y+fy))
  fi
  if [ "$i" -lt "$N" ]; then echo "  thermal pause 20s..."; sleep 20; fi
done

RATE="EVTRIAL-RATE arm=$ARM cont=$CONT runs=$N ok=$ok boot_crash=$boot_crash warp_fail=$warp_fail post_crash=$post_crash fired_all=$fired_x/$fired_y"
echo "$RATE" | tee "$OUT_DIR/${BASE}-rate.txt"
