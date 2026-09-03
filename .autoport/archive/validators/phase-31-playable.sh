#!/usr/bin/env bash
# Phase 31 validator: drive jak1 through title → menu → first level,
# verify the level state name comes from gstate.gc, screencap looks 3D,
# 60s longevity without crash.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh
. .autoport/lib/device-validate.sh

echo "== Phase 31 validator (first playable level reached) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_build_flavor jak1
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

DRIVE=.autoport/lib/jak1_first_level_drive.sh
test -x "$DRIVE" || { echo "FAIL: $DRIVE missing or not executable"; exit 1; }

# The drive script reads from $LOGCAT_LOG and emits taps via adb.
# It must export the reached state name on success.
bash "$DRIVE" "$LOGCAT_LOG" > /tmp/p31-drive.log 2>&1 \
    || { cat /tmp/p31-drive.log; device_fail "drive script failed to reach a level state"; }

LEVEL_STATE=$(grep -m1 -oE 'engine: state=[a-z0-9_-]+' "$LOGCAT_LOG" | tail -1 | sed 's/engine: state=//')
echo "  reached state: $LEVEL_STATE"

# Validate the state name is from gstate.gc / kernel/jak1 sources.
if ! grep -rE "state.*${LEVEL_STATE}|${LEVEL_STATE}.*state" goal_src/jak1/ 2>/dev/null | head -1 >/dev/null; then
    device_fail "level state '$LEVEL_STATE' has no origin in goal_src/jak1/ — synthetic?"
fi

# 3D-scene pixel check.
sleep 3
SCREEN_PNG=$(mktemp --suffix=.png)
adb shell screencap -p > "$SCREEN_PNG" 2>/dev/null
test -s "$SCREEN_PNG" || device_fail "screencap empty"

python3 - "$SCREEN_PNG" <<'PYEOF' || device_fail "screencap of '$LEVEL_STATE' doesn't look like a 3D scene"
import sys
from collections import Counter
try:
    from PIL import Image
except ImportError:
    print("PIL not installed", file=sys.stderr); sys.exit(2)
img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
# Look at upper-middle band of the screen (avoids UI overlays).
band = img.crop((int(w*0.1), int(h*0.2), int(w*0.9), int(h*0.6)))
cnt = Counter(band.getdata())
unique = len(cnt)
dom = cnt.most_common(1)[0][1] / (band.size[0] * band.size[1])
# Vertical gradient: average RGB of top third vs bottom third.
top = band.crop((0, 0, band.size[0], band.size[1]//3))
bot = band.crop((0, band.size[1]*2//3, band.size[0], band.size[1]))
def avg(im):
    px = list(im.getdata())
    return tuple(sum(c)/len(px) for c in zip(*px))
ta, ba = avg(top), avg(bot)
delta = sum(abs(a-b) for a, b in zip(ta, ba))
print(f"unique={unique} dominant_share={dom:.2%} top-bottom-color-delta={delta:.1f}", file=sys.stderr)
# 3D scene criteria: ≥150 unique colors, dominant <50%, top/bottom delta >20.
ok = (unique >= 150) and (dom < 0.50) and (delta > 20)
sys.exit(0 if ok else 1)
PYEOF

# 60s longevity.
echo "== 60s longevity observation =="
DEADLINE=$(( $(date +%s) + 60 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    sleep 10
    device_assert_no_crash "$PACKAGE" || device_fail "crash during longevity"
    if adb logcat -d -s SELinux:* | grep -qE "avc: denied.*$PACKAGE"; then
        device_fail "SELinux denial during longevity"
    fi
    if ! adb shell "pidof $PACKAGE" >/dev/null 2>&1; then
        device_fail "process disappeared (silent OOM kill?)"
    fi
    swaps=$(grep -cE 'eglSwapBuffers: ok' "$LOGCAT_LOG")
    echo "  alive — swaps=$swaps"
done

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 31 validator PASSED =="
echo "   jak1 reached '$LEVEL_STATE' from a real gstate source, screencap"
echo "   passes 3D-scene heuristics, 60s longevity clean. We have a"
echo "   playable Android jak1."
