#!/usr/bin/env bash
# gpbrf_reopen_metrics.sh — run the REOPEN metric set over the fresh captures.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Grecharged-pbr-realtime-fusion/device
M=.autoport/gpbrf_reopen_measure.py
OUT=$D/metrics-reopen.txt
: > "$OUT"
say(){ echo "$@" | tee -a "$OUT"; }
run(){ python3 "$M" "$@" | tee -a "$OUT"; }

say "== noise floor: two frames of the SAME fused_h8.mp4 (same-config temporal floor) =="
ffmpeg -loglevel error -y -i "$D/fused_h8.mp4" -vf "select=eq(n\,0)" -vsync vfr /tmp/gpbrf_f0.png
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$D/fused_h8.mp4")
T=$(python3 -c "print(min(5.0, max(0.5, float('$DUR')-0.5)))")
ffmpeg -loglevel error -y -ss "$T" -i "$D/fused_h8.mp4" -frames:v 1 /tmp/gpbrf_f1.png
run floor /tmp/gpbrf_f0.png /tmp/gpbrf_f1.png

say "== wall signature stats (pure-wall crop, dot-masked) =="
for f in fused_h8 fused_n0_h8 fused_glossy_h8 fused_matte_h8 rtonly_h8 bidon_h8 stock_h8 fused_night fused_night_noemis; do
  [ -f "$D/$f.png" ] && run wall "$D/$f.png"
done

say "== normal-map drive: default(nstr3) vs n0 (dot-masked 8x8 block-mean) =="
run bdiff "$D/fused_h8.png" "$D/fused_n0_h8.png"
say "== roughness GGX response: glossy(40) vs matte(230) =="
run bdiff "$D/fused_glossy_h8.png" "$D/fused_matte_h8.png"
say "== three distinct paths: fused vs rtonly, fused vs bidon =="
run bdiff "$D/fused_h8.png" "$D/rtonly_h8.png"
run bdiff "$D/fused_h8.png" "$D/bidon_h8.png"
say "== emissive night glow: teal-dot count night vs no-emissive control (masked_dots in wall stats above) =="
python3 - "$D" <<'EOF' | tee -a "$OUT"
import sys, numpy as np
from PIL import Image
d = sys.argv[1]
for name in ("fused_night", "fused_night_noemis"):
    im = np.asarray(Image.open(f"{d}/{name}.png").convert('RGB'), dtype=np.float32)
    h, w, _ = im.shape
    c = im[int(h*.15):int(h*.85), :int(w*.55)]  # left-55% wall region (attempt-3 convention)
    lum = c @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    dots = (c[:,:,1] > c[:,:,0]+40) & (c[:,:,2] > c[:,:,0]) & (lum > 120)
    gl = lum[dots]
    print(f"TEALGLOW {name}: glow_px={int(dots.sum())} glow_mean_lum={gl.mean() if gl.size else 0:.1f} wall_region_mean_lum={lum.mean():.1f}")
EOF
echo "[gpbrf-reopen-metrics] DONE -> $OUT"
