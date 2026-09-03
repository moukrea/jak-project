#!/usr/bin/env bash
# rtl_deploy_capture_r5.sh — round-5 CORRECTION (uniform floor) deploy + full device proof.
# 1) install fresh --pbr APK (MIUI-unblock + pm install), 2) launch to re-unpack custom assets,
# 3) deploy_verify (abort if stale), 4) run the capture stages ordered by importance,
# 5) copy representative PNGs to device/ root, 6) measure the mode-12 lighting-fraction frame.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Grecharged-realtime-lighting/device
CAP=.autoport/rtl_device_capture.sh
mkdir -p "$OUT"
adbs(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
say(){ echo "[r5-deploy] $*"; }

# ---------- 1+2: install + launch ----------
say "MIUI unblock"
adbs shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
adbs shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
adbs shell settings put global package_verifier_enable 0 >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
say "push APK ($(stat -c %s "$APK") bytes)"
adbs push "$APK" "$STAGE" >/tmp/r5-push.out 2>&1 || { cat /tmp/r5-push.out; echo "PUSH FAIL"; exit 2; }
say "pm install"
adbs shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/r5-pm.out 2>&1
grep -q Success /tmp/r5-pm.out || { cat /tmp/r5-pm.out; echo "PM INSTALL FAIL"; exit 2; }
adbs shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "install OK; launch to re-unpack custom assets"
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
adbs logcat -c >/dev/null 2>&1 || true
adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
# wait for unpack + a render marker, up to 180s
t0=$(date +%s)
while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
  adbs logcat -b all -d 2>/dev/null | grep -qaE 'LEVEL-WARP-SPAWN|A35-RENDER|frame [0-9]{3,}' && break
  sleep 4
done
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 2

# ---------- 3: deploy_verify ----------
say "deploy_verify"
if bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >"$OUT/deploy_verify_r5.txt" 2>&1; then
  say "deploy_verify PASS"; tail -3 "$OUT/deploy_verify_r5.txt"
else
  say "deploy_verify FAILED — see $OUT/deploy_verify_r5.txt"; tail -20 "$OUT/deploy_verify_r5.txt"
  echo "DEPLOY_VERIFY_FAIL"; exit 3
fi

# ---------- 4: capture stages (ordered by importance) ----------
run(){ # desc + env prefix already exported by caller
  local stage="$1" tag="$2"
  say "capture $stage $tag"
  if timeout 600 bash "$CAP" "$stage" "$tag" >>"$OUT/cap_r5.log" 2>&1; then
    say "  $tag OK frames=$(ls "$OUT/frames_$tag" 2>/dev/null | wc -l)"
  else
    say "  $tag FAILED (continuing)"; tail -3 "$OUT/cap_r5.log"
  fi
}

# money shot: normal render, sun-only + cast shadow, baked off, morning sun
RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still floor_h8
# the round-5 uniform-floor MEASUREMENT (mode 12 = lighting fraction: 1.0 sun, 0.2 away AND cast)
RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=12 run still frac_h8
# required mp4 + camera-orbit pin proof
RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run orbit orbit_h8
# h8/h16 shadow flip (sun consistency)
RTL_HOUR=16 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still flip_h16
# baked A/B (criterion 5: baked-off proven)
RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=1 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still baked_on
# relief-drape + distant-smooth vantage (round-2 relief, round-4/5 anti-pixelation)
RTL_POS="80.0 15.0 -10.0" RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 run still relief

# ---------- 5: copy representative PNGs to device/ root (validator needs *.png there) ----------
say "promote representative frames to device/ root"
for tag in floor_h8 frac_h8 flip_h16 baked_on relief orbit_h8; do
  d="$OUT/frames_$tag"
  [ -d "$d" ] || continue
  # pick a mid + late frame
  mapfile -t fs < <(ls "$d"/*.png 2>/dev/null | sort)
  n=${#fs[@]}; [ "$n" -eq 0 ] && continue
  cp "${fs[$((n/2))]}" "$OUT/still_${tag}_mid.png"
  cp "${fs[$((n-1))]}" "$OUT/still_${tag}_late.png"
done
ls "$OUT"/still_*.png 2>/dev/null | head

# ---------- 6: measure the mode-12 lighting-fraction frame (away==cast==floor) ----------
say "measure mode-12 lighting fraction"
python3 - "$OUT/frames_frac_h8" "$OUT/frac_measure_r5.txt" <<'PY' 2>>"$OUT/cap_r5.log" || say "measure skipped (numpy/PIL?)"
import sys, glob, os
import numpy as np
try:
    from PIL import Image
except Exception as e:
    print("no PIL:", e); sys.exit(0)
d, outp = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(d, "*.png")))
if not fs:
    print("no frac frames"); sys.exit(0)
# pick a middle frame
f = fs[len(fs)//2]
im = np.asarray(Image.open(f).convert("RGB")).astype(np.float32)/255.0
lum = 0.299*im[...,0]+0.587*im[...,1]+0.114*im[...,2]  # mode12 is grayscale so ~= any channel
H,Wd = lum.shape
# exclude near-black sky (top strip) heuristically: consider only lower 2/3 (world geometry)
world = lum[H//3:, :]
# histogram of the lighting-fraction over world geometry
vals = world.flatten()
# floor cluster = pixels in [0.1,0.35]; sun cluster = [0.6,1.0]
floor_pix = vals[(vals>=0.10)&(vals<=0.35)]
sun_pix   = vals[(vals>=0.60)]
lines=[]
lines.append(f"frame: {os.path.basename(f)}  ({Wd}x{H})")
lines.append(f"world-region lighting-fraction: min={vals.min():.3f} p05={np.percentile(vals,5):.3f} median={np.median(vals):.3f} max={vals.max():.3f}")
lines.append(f"floor cluster [0.10..0.35]: {100*floor_pix.size/vals.size:.1f}% of world px, mean={floor_pix.mean() if floor_pix.size else float('nan'):.3f}")
lines.append(f"sun   cluster [0.60..1.00]: {100*sun_pix.size/vals.size:.1f}% of world px, mean={sun_pix.mean() if sun_pix.size else float('nan'):.3f}")
frac_below_005 = 100*(vals<0.05).mean()
lines.append(f"pixels below 0.05 (near pure-black) in world region: {frac_below_005:.2f}%  (uniform floor => should be tiny; only true sky holes)")
txt="\n".join(lines)
print(txt)
open(outp,"w").write(txt+"\n")
PY

say "DONE. proof text:"; tail -8 "$OUT/frac_measure_r5.txt" 2>/dev/null
echo "R5_CAPTURE_DONE"
