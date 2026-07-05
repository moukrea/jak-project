#!/usr/bin/env bash
# Gperf-particles2 — detector self-test driver.
# Re-extracts a window of frames from the REAL clean recording, scores them with
# detect.py (base = no defect), then injects a pop (black-hole) defect and a
# flicker (luma sawtooth) defect and scores each. Proves detect.py FIRES on the
# owner's defect shapes on THIS device's frames (the device-non-repro control gap).
# Writes JSONs to synthetic/ and prints a comparison table. Deterministic.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT=.autoport/reports/Gperf-particles2
TOOLS=$ROOT/tools
REC=$ROOT/cap/clean/rec.mp4
OUT=$ROOT/synthetic
NFRAMES="${1:-460}"     # 23 pop injections at period 20
[ -f "$REC" ] || { echo "no clean rec.mp4 at $REC" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT/base"

# 1. re-extract a window of frames with the SAME pipeline capture.sh used.
ffmpeg -nostdin -loglevel error -y -i "$REC" -vf "scale=480:-2" -vsync 0 \
  -frames:v "$NFRAMES" "$OUT/base/r%05d.png" 2>&1 | tail -1
NB=$(ls "$OUT/base"/*.png 2>/dev/null | wc -l)
echo "extracted $NB base frames from real clean recording"

score(){ # <dir> <label> <jsonname>
  python3 "$TOOLS/detect.py" "$1" --label "$2" --no-dedup --json "$OUT/$3.json" | sed 's/^/  /'
}

echo "--- BASE (no defect) ---"
score "$OUT/base" "synthetic-base" base
echo "--- POP injected (central black hole every 20 frames) ---"
python3 "$TOOLS/synthetic_inject.py" "$OUT/base" "$OUT/pop" --mode pop --period 20 --rect 0.5
score "$OUT/pop" "synthetic-pop" pop
echo "--- FLICKER injected (+/-12% luma sawtooth) ---"
python3 "$TOOLS/synthetic_inject.py" "$OUT/base" "$OUT/flicker" --mode flicker --amp 0.12
score "$OUT/flicker" "synthetic-flicker" flicker

# keep JSON only; drop the bulk PNG dirs (re-extractable).
rm -rf "$OUT/base" "$OUT/pop" "$OUT/flicker"

echo "=== SUMMARY (detector self-test) ==="
python3 - "$OUT" <<'PY'
import json, sys, os
d = sys.argv[1]
def g(n):
    with open(os.path.join(d, n + ".json")) as f: return json.load(f)
print(f"{'config':<16}{'POP events':>12}{'pop_frames':>12}{'flip_rate':>11}{'saw%':>9}")
for name in ("base", "pop", "flicker"):
    j = g(name)
    print(f"{name:<16}{j['pop']['pop_events']:>12}{j['pop']['pop_frames']:>12}"
          f"{j['flicker']['flip_rate']:>11}{j['flicker']['saw_energy_pct']:>9}")
PY
