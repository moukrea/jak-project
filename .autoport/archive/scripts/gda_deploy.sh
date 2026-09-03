#!/usr/bin/env bash
# gda_deploy.sh — Grecharged-directional-ambient deploy + full device proof.
# 1) adb server refresh (avoid the wedge false-fail), 2) MIUI-unblock + install fresh --pbr APK,
# 3) launch to re-unpack custom assets, 4) deploy_verify (abort if stale), 5) capture A/B stages,
# 6) promote representative PNGs to device/ root, 7) objective A/B measurements.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
OUT=.autoport/reports/Grecharged-directional-ambient/device
CAP=.autoport/gda_capture.sh
mkdir -p "$OUT"
adbs(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
say(){ echo "[gda-deploy] $*"; }

# ---------- 0: adb server refresh (memory: wedged daemon => false 'not installed') ----------
say "adb server refresh"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
adbs wait-for-device
say "device: $(adbs get-state 2>/dev/null)"

# ---------- 1+2: install + launch ----------
say "MIUI unblock"
adbs shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
adbs shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
adbs shell settings put global package_verifier_enable 0 >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
say "push APK ($(stat -c %s "$APK") bytes)"
adbs push "$APK" "$STAGE" >/tmp/gda-push.out 2>&1 || { cat /tmp/gda-push.out; echo "PUSH FAIL"; exit 2; }
say "pm install"
adbs shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gda-pm.out 2>&1
grep -q Success /tmp/gda-pm.out || { cat /tmp/gda-pm.out; echo "PM INSTALL FAIL"; exit 2; }
adbs shell rm -f "$STAGE" >/dev/null 2>&1 || true
say "install OK; launch to re-unpack custom assets"
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
adbs logcat -c >/dev/null 2>&1 || true
adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
  adbs logcat -b all -d 2>/dev/null | grep -qaE 'LEVEL-WARP-SPAWN|A35-RENDER|frame [0-9]{3,}' && break
  sleep 4
done
adbs shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 2

# ---------- 3: deploy_verify ----------
say "deploy_verify"
if bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >"$OUT/deploy_verify.txt" 2>&1; then
  say "deploy_verify PASS"; tail -3 "$OUT/deploy_verify.txt"
else
  say "deploy_verify FAILED — see $OUT/deploy_verify.txt"; tail -20 "$OUT/deploy_verify.txt"
  echo "DEPLOY_VERIFY_FAIL"; exit 3
fi

# ---------- 4: capture A/B stages ----------
run(){ local stage="$1" tag="$2"; say "capture $stage $tag"
  if timeout 600 bash "$CAP" "$stage" "$tag" >>"$OUT/cap.log" 2>&1; then
    say "  $tag OK frames=$(ls "$OUT/frames_$tag" 2>/dev/null | wc -l)"
  else say "  $tag FAILED (continuing)"; tail -4 "$OUT/cap.log"; fi
}

# HEADLINE: form in shadow with AO OFF — hemisphere ambient ON vs OFF, day, normal render.
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still amb_on_h8
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still amb_off_h8
# OBJECTIVE form: debug-12 lighting fraction — ambient ON = directional gradient, OFF = flat 0.2.
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=12 run still frac_on_h8
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=12 run still frac_off_h8
# PREREQ 1: realtime OFF => revert (no realtime effect at all).
RTL_HOUR=8 RTL_LIGHT=0 RTL_AMBIENT=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still rtoff_h8
# TOD tracking: night — hemisphere ambient tracks TOD, stays calm (no phantom night lights).
RTL_HOUR=0 RTL_LIGHT=1 RTL_AMBIENT=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still amb_on_h0
# required mp4 + geometry-pin orbit (form pinned to geometry under camera move).
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run orbit amb_orbit

# ---------- 5: promote representative PNGs to device/ root ----------
say "promote representative frames to device/ root"
for tag in amb_on_h8 amb_off_h8 frac_on_h8 frac_off_h8 rtoff_h8 amb_on_h0 amb_orbit; do
  d="$OUT/frames_$tag"; [ -d "$d" ] || continue
  n=$(ls "$d"/*.png 2>/dev/null | wc -l); [ "$n" -gt 0 ] || continue
  mid=$(ls "$d"/*.png | sed -n "$(( n/2 ))p"); late=$(ls "$d"/*.png | tail -1)
  cp "$mid"  "$OUT/still_${tag}_mid.png"  2>/dev/null || true
  cp "$late" "$OUT/still_${tag}_late.png" 2>/dev/null || true
done
ls -la "$OUT"/*.png "$OUT"/*.mp4 2>/dev/null | tail -30

# ---------- 6: objective A/B measurements ----------
say "measure A/B (form gradient + sunlit-identical + night calm)"
python3 - "$OUT" <<'PY' | tee "$OUT/measure.txt"
import sys, glob, os
import numpy as np
try:
    from PIL import Image
except Exception as e:
    print("PIL unavailable:", e); sys.exit(0)
OUT=sys.argv[1]
def load(tag):
    fs=sorted(glob.glob(f"{OUT}/frames_{tag}/*.png"))
    if not fs: return None
    f=fs[len(fs)//2]
    a=np.asarray(Image.open(f).convert("RGB")).astype(np.float32)/255.0
    return a,f
def lum(a): return 0.299*a[...,0]+0.587*a[...,1]+0.114*a[...,2]
on=load("amb_on_h8"); off=load("amb_off_h8")
if on and off and on[0].shape==off[0].shape:
    ao,fo=on; bo,fb=off
    d=np.abs(ao-bo).mean(axis=2)
    Lon=lum(ao)
    sun=Lon>0.6      # bright/sunlit pixels
    shad=Lon<0.35    # shadowed/ambient pixels
    print(f"[form A/B] amb_on={os.path.basename(fo)} amb_off={os.path.basename(fb)}")
    print(f"  whole-frame mean |diff| = {d.mean():.4f}")
    print(f"  SUNLIT region mean |diff| = {d[sun].mean() if sun.any() else float('nan'):.4f}  (golden rule: ~0)")
    print(f"  SHADOW region mean |diff| = {d[shad].mean() if shad.any() else float('nan'):.4f}  (ambient reshapes here)")
    print(f"  sunlit px frac={sun.mean():.3f} shadow px frac={shad.mean():.3f}")
# night calm
for tag,lbl in [("amb_on_h8","day h8"),("amb_on_h0","night h0")]:
    r=load(tag)
    if r:
        a,f=r; L=lum(a)
        print(f"[TOD] {lbl}: mean L={L.mean():.4f} bright(>0.5) frac={ (L>0.5).mean():.4f}  ({os.path.basename(f)})")
PY
say "DONE — eyeball the promoted still_*.png before declaring pass"
