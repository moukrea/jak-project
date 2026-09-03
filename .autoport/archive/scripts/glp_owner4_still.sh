#!/usr/bin/env bash
# glp_owner4_still.sh — mechanical boot proof still for the owner-#4 phantom-shadow fix build.
# Assumes glp_build_deploy.sh just PASSED (app foreground, live render). Grabs a short
# screenrecord (screencap is black on the GL surface), extracts the last frame, verifies focus.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-lightprobes/device
die(){ echo "[glp-still FAIL] $*" >&2; exit 1; }

TEMP=$($ADB -s $S shell dumpsys battery | grep -m1 temperature | grep -oE '[0-9]+')
[ "${TEMP:-0}" -lt 450 ] || die "device temp $TEMP >= 45.0C — cooldown required"

FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r')
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
echo "$FOCUS" > "$OUT/glpOWNER4_focus.txt"

$ADB -s $S shell screenrecord --time-limit 4 /data/local/tmp/glp_o4.mp4 || die "screenrecord failed"
$ADB -s $S pull /data/local/tmp/glp_o4.mp4 /tmp/glp_o4.mp4 >/dev/null || die "pull failed"
$ADB -s $S shell rm -f /data/local/tmp/glp_o4.mp4 || true
ffmpeg -y -sseof -0.5 -i /tmp/glp_o4.mp4 -frames:v 1 "$OUT/glpOWNER4_boot.png" 2>/dev/null || die "ffmpeg extract failed"
rm -f /tmp/glp_o4.mp4
python3 - "$OUT/glpOWNER4_boot.png" <<'EOF'
import sys
from PIL import Image
import numpy as np
im = np.asarray(Image.open(sys.argv[1]).convert('L'), dtype=np.float32)
print(f"  still {im.shape[1]}x{im.shape[0]} mean_luma={im.mean():.1f} std={im.std():.1f}")
assert im.mean() > 8 and im.std() > 5, "frame looks black/blank — not render evidence"
EOF
echo "[glp-still] DONE — $OUT/glpOWNER4_boot.png + focus"
