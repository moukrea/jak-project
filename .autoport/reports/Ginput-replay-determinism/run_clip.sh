#!/usr/bin/env bash
# Ginput-replay-determinism proof driver. Records a real-gameplay clip (OG_F1_WARP
# to Geyser Rock + scripted in-engine drive) with a per-logic-frame state dump,
# then replays it on the SAME backend with the same dump, and reports whether the
# record-trace and replay-trace are bit-identical over the clip.
#   run_clip.sh <tag> <seconds>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-clip}"; SECS="${2:-70}"
D="$PWD/.autoport/reports/Ginput-replay-determinism"
GK=(build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem)
echo "== RECORD ($TAG, ${SECS}s) =="
OG_F1_WARP=1 OG_F1_WARP_DELAY=150 OG_PAD_REPLAY_RECORD="$D/$TAG.inputs" OG_PAD_REPLAY_DRIVE=1 OG_PAD_REPLAY_TRACE="$D/${TAG}_rec.trace" \
  timeout "$SECS" "${GK[@]}" > "/tmp/${TAG}_rec.log" 2>&1; echo "rec exit=$?"
echo "== REPLAY ($TAG) =="
OG_F1_WARP=1 OG_F1_WARP_DELAY=150 OG_PAD_REPLAY_REPLAY="$D/$TAG.inputs" OG_PAD_REPLAY_TRACE="$D/${TAG}_rep.trace" \
  timeout "$SECS" "${GK[@]}" > "/tmp/${TAG}_rep.log" 2>&1; echo "rep exit=$?"
RC=$(wc -l < "$D/${TAG}_rec.trace"); RP=$(wc -l < "$D/${TAG}_rep.trace")
N=$(( RC < RP ? RC : RP ))
head -n "$N" "$D/${TAG}_rec.trace" > /tmp/${TAG}.rec.head
head -n "$N" "$D/${TAG}_rep.trace" > /tmp/${TAG}.rep.head
echo "rec_frames=$RC rep_frames=$RP common=$N"
echo "anchor: $(grep -ah 'ANCHOR reached' /tmp/${TAG}_rec.log | head -1)"
if cmp -s /tmp/${TAG}.rec.head /tmp/${TAG}.rep.head; then
  echo "RESULT: RECORD==REPLAY bit-identical over $N logic frames"
  echo "sha256(common prefix): $(sha256sum /tmp/${TAG}.rec.head | awk '{print $1}')"
else
  echo "RESULT: DIVERGED"
  diff /tmp/${TAG}.rec.head /tmp/${TAG}.rep.head | grep -m1 '^<' | cut -c1-30
fi
