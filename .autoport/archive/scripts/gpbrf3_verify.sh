#!/usr/bin/env bash
# gpbrf3_verify.sh — REOPEN #3 step-2/3 verify: culprit-term fix + shimmer, before/after
# on device. Stages are resumable; run in order:
#   pre      captures on the CURRENT device build (pre-fix reference):
#              shimmer_before (wall vantage, nstrength 3, camera pan rx=165)
#              grazing_before.png (beach ground vantage '36.0 3.0 -12.0')
#   deploy   desktop compile check + android libgk + APK + install + deploy_verify
#   post     fixed-path captures: wall vantage fixed_m0/fixed_m4/fixed_m16/fixed_spec0,
#              shimmer_after (same pan), grazing_after.png
#   metrics  fixed matrix vs pre-fix bisect_m0 + shimmer before/after + grazing stats
# Device eae4df44, jak1, never reboot.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
BIS=.autoport/gpbrf3_bisect.sh
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gpbrf3-verify FAIL] $*" >&2; exit 1; }

snap(){ # TAG  — 3s screenrecord -> last frame png
  local TAG=$1
  adb shell screenrecord --time-limit 3 --bit-rate 8000000 /sdcard/g3v_$TAG.mp4 || die "rec $TAG"
  adb pull /sdcard/g3v_$TAG.mp4 /tmp/g3v_$TAG.mp4 >/dev/null 2>&1 || die "pull $TAG"
  adb shell rm -f /sdcard/g3v_$TAG.mp4
  rm -rf /tmp/g3v_fr; mkdir -p /tmp/g3v_fr
  ffmpeg -y -loglevel error -i /tmp/g3v_$TAG.mp4 -vf fps=2 /tmp/g3v_fr/f_%03d.png
  cp "$(ls /tmp/g3v_fr/f_*.png | tail -1)" "$OUT/$TAG.png"
  rm -rf /tmp/g3v_fr /tmp/g3v_$TAG.mp4
  echo "  -> $OUT/$TAG.png"
}

moving(){ # TAG — 8s screenrecord while right-stick pans (nstrength high for shimmer)
  local TAG=$1
  adb shell "setprop debug.opengoal.pbr.nstrength 3"
  sleep 2
  adb shell "setprop debug.opengoal.cpad_inject 'rx=165'"
  sleep 1
  adb shell screenrecord --time-limit 8 --bit-rate 8000000 /sdcard/g3v_$TAG.mp4 || die "rec $TAG"
  adb shell "setprop debug.opengoal.cpad_inject neutral"
  adb shell "setprop debug.opengoal.pbr.nstrength ''"
  adb pull /sdcard/g3v_$TAG.mp4 "$OUT/$TAG.mp4" >/dev/null 2>&1 || die "pull $TAG"
  adb shell rm -f /sdcard/g3v_$TAG.mp4
  rm -rf /tmp/g3v_${TAG}_fr; mkdir -p /tmp/g3v_${TAG}_fr
  ffmpeg -y -loglevel error -i "$OUT/$TAG.mp4" -vf fps=10 /tmp/g3v_${TAG}_fr/f_%03d.png
  echo "  -> $OUT/$TAG.mp4 + $(ls /tmp/g3v_${TAG}_fr | wc -l) frames in /tmp/g3v_${TAG}_fr"
}

case "${1:?stage (pre|deploy|post|metrics)}" in
pre)
  bash "$BIS" boot
  moving shimmer_before
  bash "$BIS" cleanup
  WARP_POS="36.0 3.0 -12.0" bash "$BIS" boot
  snap grazing_before
  bash "$BIS" cleanup
  ;;
deploy)
  cmake --build build --target gk -j"$(nproc)" 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "desktop gk build failed"
  cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "android gk build failed"
  ( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -4 ) || die "gradle failed"
  APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  [ -f "$APK" ] || die "no APK"
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
  adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  adb shell pm trim-caches 999G 2>/dev/null || true
  adb install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "install failed"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify failed"
  ;;
post)
  bash "$BIS" boot
  adb shell "setprop debug.opengoal.pbr.bisect 0";  sleep 3; snap fixed_m0
  adb shell "setprop debug.opengoal.pbr.bisect 4";  sleep 3; snap fixed_m4
  adb shell "setprop debug.opengoal.pbr.bisect 16"; sleep 3; snap fixed_m16
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.specint 0"; sleep 3; snap fixed_spec0
  adb shell "setprop debug.opengoal.pbr.specint ''"
  moving shimmer_after
  bash "$BIS" cleanup
  WARP_POS="36.0 3.0 -12.0" bash "$BIS" boot
  snap grazing_after
  bash "$BIS" cleanup
  ;;
metrics)
  {
    echo "== FIXED-PATH wall matrix (vs PRE-FIX bisect_m0 baseline) =="
    python3 - "$OUT" <<'EOF'
import importlib.util, os, sys
import numpy as np
spec = importlib.util.spec_from_file_location('bm', '.autoport/gpbrf3_bisect_metrics.py')
bm = importlib.util.module_from_spec(spec); spec.loader.exec_module(bm)
d = sys.argv[1]
base = bm.load(os.path.join(d, 'bisect_m0.png'))  # PRE-FIX baseline
ref = {}
for name, box, dm in (('wall', bm.WALL, True), ('ground', bm.GROUND, False)):
    lum, m = bm.crop(base, box, dm)
    ref[name] = bm.blockmean(lum, m)
for tag in ('fixed_m0', 'fixed_m4', 'fixed_m16', 'fixed_spec0'):
    p = os.path.join(d, tag + '.png')
    if not os.path.exists(p):
        print(tag, 'MISSING'); continue
    img = bm.load(p)
    line = [f"{tag:12}"]
    for name, box, dm in (('wall', bm.WALL, True), ('ground', bm.GROUND, False)):
        lum, m = bm.crop(img, box, dm)
        mn, p95, p99 = bm.stats(lum, m)
        bmn, bv = bm.blockmean(lum, m)
        b0, v0 = ref[name]
        both = bv & v0
        bd = float(np.abs(bmn - b0)[both].mean()) if both.any() else 0.0
        thr = np.percentile(b0[v0], 90)
        bb = both & (b0 >= thr)
        bright = float((bmn - b0)[bb].mean()) if bb.any() else 0.0
        line.append(f"{name}: mean={mn:.2f} p95={p95:.2f} p99={p99:.2f} bd={bd:.2f} bright_bd={bright:.2f}")
    print('  '.join(line))
EOF
    echo "== SHIMMER before/after (nstrength 3, rx pan) =="
    python3 .autoport/gpbrf3_shimmer_metric.py /tmp/g3v_shimmer_before_fr before
    python3 .autoport/gpbrf3_shimmer_metric.py /tmp/g3v_shimmer_after_fr after
    echo "== GRAZING ground before/after (beach vantage lower-frame crop) =="
    python3 - "$OUT" <<'EOF'
import sys, os
import numpy as np
from PIL import Image
d = sys.argv[1]
for t in ('grazing_before', 'grazing_after'):
    p = os.path.join(d, t + '.png')
    if not os.path.exists(p):
        print(t, 'MISSING'); continue
    im = np.asarray(Image.open(p).convert('RGB'), dtype=np.float32)
    h, w, _ = im.shape
    c = im[int(h*.55):int(h*.95), int(w*.20):int(w*.80)]
    lum = c @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    sat = (c.max(axis=2) - c.min(axis=2))
    print(f"GRAZING {t}: mean={lum.mean():.2f} p95={np.percentile(lum,95):.2f} "
          f"p99={np.percentile(lum,99):.2f} sat={sat.mean():.2f}")
EOF
  } | tee "$OUT/fix_verify_metrics.txt"
  ;;
*) die "unknown stage $1";;
esac
