#!/usr/bin/env bash
# Gperf-particles2 image PARITY: prove the KEPT opts render identical to the v4
# renderer. The 5 kept opts are pure CPU/submission changes (research: image-
# invariant), so at a held pose the clean(kept-ON) vs v4(kept-OFF) screencap diff
# must equal the AMBIENT-ANIMATION NOISE FLOOR (clean-vs-clean diff a moment apart)
# — anything the opts changed in the image would exceed it. Clock PINNED + pad
# NEUTRAL here is legitimate: parity is a pixel-value question at a fixed state,
# NOT the pop/flicker question (which needs motion and is proven separately).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
WARP="${1:-village2-start}"
HOUR="${2:-12}"   # TOD hour to pin for this parity pass (day 12 / night 23 / sunrise 6)
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
OUT=.autoport/reports/Gperf-particles2/parity/h$HOUR; mkdir -p "$OUT"
A(){ "$ADB" -s "$S" "$@"; }
focus_ok(){ A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG"; }
die(){ echo "[parity FAIL] $*" >&2; exit 1; }
SWK=(nospritelean nostatecache noinstance noshrubidx no2dvec)
clean(){ for s in "${SWK[@]}"; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done; }
v4(){ for s in "${SWK[@]}"; do A shell setprop "debug.opengoal.perf.$s" 1 >/dev/null 2>&1; done; }

# static-ish held pose: pin clock (frozen day), pad neutral (no replay/drive)
A shell setprop debug.opengoal.pad_replay '""' >/dev/null 2>&1
A shell setprop debug.opengoal.tod.fast '""' >/dev/null 2>&1
A shell setprop debug.opengoal.tod.hour "$HOUR" >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp "$WARP" >/dev/null 2>&1
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
for s in notodpp notodskip nooverlap; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true

LOG="$OUT/logcat.txt"
for b in 1 2 3 4 5 6; do
  A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
  A logcat -c >/dev/null 2>&1; : > "$LOG"
  A logcat -v threadtime opengoal-gk:V GK_STDOUT:V '*:S' > "$LOG" 2>&1 & LP=$!
  A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
  ok=0; for i in $(seq 1 180); do grep -qa "LEVEL-WARP-SPAWN name=$WARP" "$LOG" && { ok=1; break; }; sleep 1; done
  [ "$ok" = 1 ] && break; echo "  boot flake -> retry"; kill $LP 2>/dev/null||true
done
[ "$ok" = 1 ] || die "no warp"
echo "  warp ok; settling"; sleep 25
focus_ok || die "not foreground"

clean; sleep 3
A exec-out screencap -p > "$OUT/clean_a.png"; sleep 1
A exec-out screencap -p > "$OUT/clean_b.png"; sleep 1
A exec-out screencap -p > "$OUT/clean_c.png"
v4; sleep 3
A exec-out screencap -p > "$OUT/v4_a.png"; sleep 1
A exec-out screencap -p > "$OUT/v4_b.png"
clean; sleep 3
A exec-out screencap -p > "$OUT/clean_d.png"   # revert -> back to clean
kill $LP 2>/dev/null||true
A shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1

python3 - "$OUT" <<'PY'
import sys,glob,numpy as np
from PIL import Image
d=sys.argv[1]
def L(p): return np.asarray(Image.open(p).convert("RGB"),np.float32)
def diff(a,b):
    A,B=L(f"{d}/{a}"),L(f"{d}/{b}")
    h=min(A.shape[0],B.shape[0]); w=min(A.shape[1],B.shape[1])
    return round(float(np.abs(A[:h,:w]-B[:h,:w]).mean()),3)
# ANIMATION FLOOR = diff between two captures of the SAME config. Fire/water/idle
# particles animate continuously, so ANY two captures differ; crucially the fire's
# frame-to-frame magnitude is VARIABLE (a calm-vs-active flicker), so clean-vs-clean
# alone can under-sample it and fake a "DIFFERS". Include BOTH clean-clean AND v4-v4
# same-config pairs so the floor captures the fire variance symmetrically. If the kept
# features are image-invariant, the cross-config (clean-vs-v4) distribution is drawn
# from the SAME population as the same-config floor.
floor=[diff("clean_a.png","clean_b.png"),diff("clean_b.png","clean_c.png"),
       diff("clean_a.png","clean_c.png"),diff("clean_a.png","clean_d.png"),
       diff("v4_a.png","v4_b.png")]  # v4-v4 = same-config floor w/ active-fire variance
# clean vs v4 (cross-config)
cross=[diff("clean_a.png","v4_a.png"),diff("clean_b.png","v4_a.png"),diff("clean_c.png","v4_b.png")]
print("PARITY (mean abs pixel diff, 0..255):")
print(f"  same-config FLOOR (clean-clean + v4-v4) : {floor}  (max {max(floor)})")
print(f"  cross-config     (clean-vs-v4)          : {cross}  (max {max(cross)})")
print(f"  VERDICT: cross max {max(cross)} vs floor max {max(floor)} -> "
      f"{'PARITY (within same-config animation floor)' if max(cross)<=max(floor)*1.3+0.5 else 'DIFFERS (exceeds same-config floor)'}")
PY
echo "[parity DONE] -> $OUT"
