#!/usr/bin/env bash
# Gcollision-replay-diff: replay the OWNER demo (collision-glitch.inputs) on x86
# with the per-logic-frame collision trace, via the deterministic Geyser warp.
#   arg1 = output trace tag (written to this dir)
#   arg2 = timeout seconds (default 200)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Gcollision-replay-diff
TAG="${1:-x86_chk}"; SECS="${2:-200}"; DEMO="${3:-.autoport/demos/collision-glitch-gameplay.inputs}"
OUT="$D/${TAG}.trace"
rm -f "$OUT"
OG_F1_WARP=1 \
OG_PAD_REPLAY_REPLAY="$DEMO" \
OG_PAD_REPLAY_TRACE="$OUT" \
timeout "$SECS" build-x86/game/gk --game jak1 --portable -fakeiso --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$D/${TAG}.stdout.log" 2>&1 || true
echo "[$TAG] frames=$(grep -c '^ci frame=' "$OUT" 2>/dev/null) trace=$OUT"
grep -aE 'ANCHOR reached|REPLAY <-|link finish: logo' "$D/${TAG}.stdout.log" | head -5
