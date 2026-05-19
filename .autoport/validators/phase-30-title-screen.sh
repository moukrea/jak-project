#!/usr/bin/env bash
# Phase 30 validator: title screen rendered AND responds to a START tap.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh
. .autoport/lib/device-validate.sh

echo "== Phase 30 validator (title screen visible + reacts to input) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_build_flavor jak1
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Wait for boot through to title.
device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 240 \
    || device_fail "loader broken"
device_wait_for_marker 'engine: state=title' 240 \
    || device_fail "kernel never reached title state"

# Wait 5s for title-screen content to settle.
echo "== waiting 5s for title content to settle =="
sleep 5

# Capture START hitbox coords if the runtime logged them.
HITBOX=$(grep -m1 -oE 'touch-hitbox: start_button at \([0-9]+,[0-9]+\)-\([0-9]+,[0-9]+\)' "$LOGCAT_LOG" || true)
if [ -n "$HITBOX" ]; then
    TAP_X=$(echo "$HITBOX" | grep -oE '\([0-9]+,[0-9]+\)' | head -1 | tr -d '()' | cut -d, -f1)
    TAP_Y=$(echo "$HITBOX" | grep -oE '\([0-9]+,[0-9]+\)' | head -1 | tr -d '()' | cut -d, -f2)
    echo "  using logged START hitbox: ($TAP_X, $TAP_Y)"
else
    # Fallback: center bottom 80%.
    read SCREEN_W SCREEN_H <<<"$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1 | tr 'x' ' ')"
    SCREEN_W=${SCREEN_W:-1080}; SCREEN_H=${SCREEN_H:-2300}
    TAP_X=$((SCREEN_W / 2)); TAP_Y=$((SCREEN_H * 80 / 100))
    echo "  no logged hitbox; falling back to ($TAP_X, $TAP_Y)"
fi

# Pre-shot.
PRE=$(mktemp --suffix=.png)
adb shell screencap -p > "$PRE" 2>/dev/null
test -s "$PRE" || device_fail "pre screencap empty"
echo "  pre: $(stat -c %s "$PRE") bytes"

# Diversity sanity on the pre-shot itself — must already look like real
# rendering, not a solid clear (phase 29 should have ensured this).
if ! anti_stub_count_pixel_diversity "$PRE" 2>&1; then
    device_fail "pre-screenshot is solid color — title screen not actually rendered"
fi

# Tap START.
echo "== tapping START at ($TAP_X, $TAP_Y) =="
adb shell input tap "$TAP_X" "$TAP_Y"
sleep 3

# Post-shot.
POST=$(mktemp --suffix=.png)
adb shell screencap -p > "$POST" 2>/dev/null
test -s "$POST" || device_fail "post screencap empty"
echo "  post: $(stat -c %s "$POST") bytes"

# Perceptual-difference: count pixel changes in the central region.
python3 - "$PRE" "$POST" <<'PYEOF' || device_fail "pre and post screencaps are nearly identical — input had no effect"
import sys
try:
    from PIL import Image, ImageChops
except ImportError:
    print("PIL not installed", file=sys.stderr)
    sys.exit(2)
pre = Image.open(sys.argv[1]).convert("RGB")
post = Image.open(sys.argv[2]).convert("RGB")
if pre.size != post.size:
    print(f"size mismatch: {pre.size} vs {post.size}", file=sys.stderr)
    sys.exit(1)
w, h = pre.size
# Center 60% region (avoid status bar + touch overlay).
cx, cy = w // 2, h // 2
hw, hh = int(w * 0.30), int(h * 0.30)
box = (cx - hw, cy - hh, cx + hw, cy + hh)
diff = ImageChops.difference(pre.crop(box), post.crop(box))
# Count pixels whose RGB sum-diff exceeds 30 (modest change).
changed = 0
total = 0
for r, g, b in diff.getdata():
    total += 1
    if r + g + b > 30:
        changed += 1
share = changed / total
print(f"changed-pixel share in center: {share*100:.2f}% ({changed}/{total})", file=sys.stderr)
# Accept ≥3% of central pixels changed. A menu overlay typically changes
# 20-50%; jitter from animation alone is <0.5%. 3% is a comfortable floor.
sys.exit(0 if share >= 0.03 else 1)
PYEOF

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_no_crash "$PACKAGE" || device_fail "crash during title/menu transition"

echo
echo "== Phase 30 validator PASSED =="
echo "   Title screen rendered with diverse pixel content, and a START tap"
echo "   produced a measurable screen change (likely menu)."
