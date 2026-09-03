#!/usr/bin/env bash
# Gnewgame-crash verification run: drive NEW GAME -> intro cinematic via the
# cpad_inject bridge and save the routed logcat at the path the phase validator
# expects: .autoport/reports/Gnewgame-routed-logcat-<run>.log. Thin wrapper over
# .autoport/f1d_run.sh (FLOW=newgame) which captures to F1d-routed-logcat-<run>.log.
#
# Usage: bash .autoport/gnewgame_run.sh <run-number> [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
RUN="${1:-1}"
SKIP="${2:-}"

FLOW=newgame bash .autoport/f1d_run.sh "$RUN" "$SKIP"

SRC=".autoport/reports/F1d-routed-logcat-run${RUN}.log"
DST=".autoport/reports/Gnewgame-routed-logcat-run${RUN}.log"
if [ -f "$SRC" ]; then
  cp -f "$SRC" "$DST"
  echo "Gnewgame routed logcat -> $DST ($(wc -l < "$DST" 2>/dev/null || echo 0) lines)"
  CR=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11|signal 4 \(SIGILL\)" "$DST" 2>/dev/null || true)
  FM=$(grep -a 'A35-RENDER frame=' "$DST" | grep -oE 'frame=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
  echo "  crash-signal events: ${CR:-0}   highest A35-RENDER frame: ${FM:-0}"
else
  echo "WARN: $SRC not found; no Gnewgame routed logcat produced" >&2
  exit 1
fi
