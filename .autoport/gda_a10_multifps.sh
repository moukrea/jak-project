#!/usr/bin/env bash
# gda_a10_multifps.sh — OWNER PLAYTEST #4, attempt-10 honest per-channel handoff proof.
#
# The tod.fast 18000x sweep advances the sun ~25 game-min PER 12fps FRAME, which is larger than the
# yellow<->green shadow/light elevation ramp band (~1.3 game-hours). So a CONTINUOUS ramp is UNDERSAMPLED
# into a big single-frame per-channel step (the measured ~14/255) even though the underlying signal is
# smooth. This tool re-extracts the SAME sweep mp4 at 12 / 30 / 60 fps and measures the per-channel step at
# each: a CONTINUOUS ramp's worst step SHRINKS ~proportionally to 1/fps as the sampling gets finer (14 -> ~5
# -> ~2); a TRUE discontinuity (a real one-frame pop) would stay ~constant across fps. This discriminates
# "smooth ramp undersampled" from "brutal step" — the honest per-channel gate for the yellow<->green handoff.
#
# usage: gda_a10_multifps.sh <mp4> <tag>       e.g. gda_a10_multifps.sh <OUT>/gda_gda_a10_smooth.mp4 a10_smooth
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-directional-ambient/device
MP4="${1:?mp4}"; TAG="${2:?tag}"
[ -f "$MP4" ] || { echo "no mp4: $MP4"; exit 1; }
ARGS=()
for F in 12 30 60; do
  d="$OUT/frames_${TAG}_${F}fps"; mkdir -p "$d"; rm -f "$d"/*.png
  ffmpeg -y -loglevel error -i "$MP4" -vf fps=$F "$d/f_%04d.png"
  echo "extracted $TAG @ ${F}fps: $(ls "$d" 2>/dev/null | wc -l) frames"
  ARGS+=("$d" "${TAG}_${F}fps")
done
python3 .autoport/gda_perchannel_smoothness.py "${ARGS[@]}"
