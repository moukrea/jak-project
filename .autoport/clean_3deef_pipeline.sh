#!/usr/bin/env bash
# Wait for the clean goalc rebuild, build a consistent 3deef6bf3 arm64 CGO set,
# wait for the clean libgk build, then signal ALL-DONE. Run in background.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOG=.autoport/logs/clean-pipeline.log
: > "$LOG"
echo "[pipe] waiting for goalc rebuild (clean-goalc.done)..." | tee -a "$LOG"
until [ -f .autoport/logs/clean-goalc.done ]; do sleep 15; done
echo "[pipe] goalc ready. arm64 goalc: $(build-arm64/goalc/goalc --version 2>&1 | head -1)" | tee -a "$LOG"

echo "[pipe] building consistent 3deef6bf3 arm64 CGO set..." | tee -a "$LOG"
if bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
  echo "[pipe] CGO build OK: $(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l) files" | tee -a "$LOG"
else
  echo "[pipe] CGO build FAILED (see log)" | tee -a "$LOG"
fi

echo "[pipe] waiting for clean libgk build to finish..." | tee -a "$LOG"
until ! pgrep -f 'cmake --build build-android' >/dev/null 2>&1; do sleep 15; done
LIBGK=build-android/lib/arm64-v8a/libgk.so
echo "[pipe] libgk done: $(stat -c%y "$LIBGK" 2>/dev/null | cut -d. -f1) sha $(sha1sum "$LIBGK" 2>/dev/null | cut -c1-12)" | tee -a "$LOG"
echo "[pipe] ALL-DONE" | tee -a "$LOG"
