#!/usr/bin/env bash
# gda_deploy2.sh — Grecharged-directional-ambient ROOT-CAUSE FIX (smooth per-vertex normals) deploy +
# device proof. Installs the fresh --pbr APK (libgk with the reconstruction + smooth-normal shaders +
# the rt.flatnormal A/B toggle), deploy_verify, then captures the smooth-vs-flat A/B at a curved-hut
# shadowed vantage, the debug-2 world-normal A/B (direct proof the normal is now smooth), the tier
# climb (hemisphere/SH/IBL), rt-off (== stock baked), and a geometry-pin orbit. Objective A/B measure.
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
say(){ echo "[gda-deploy2] $*"; }

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
adbs push "$APK" "$STAGE" >/tmp/gda2-push.out 2>&1 || { cat /tmp/gda2-push.out; echo "PUSH FAIL"; exit 2; }
say "pm install"
adbs shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gda2-pm.out 2>&1
grep -q Success /tmp/gda2-pm.out || { cat /tmp/gda2-pm.out; echo "PM INSTALL FAIL"; exit 2; }
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

# ---------- 4: capture stages ----------
run(){ local stage="$1" tag="$2"; say "capture $stage $tag"
  if timeout 700 bash "$CAP" "$stage" "$tag" >>"$OUT/cap2.log" 2>&1; then
    say "  $tag OK frames=$(ls "$OUT/frames_$tag" 2>/dev/null | wc -l)"
  else say "  $tag FAILED (continuing)"; tail -4 "$OUT/cap2.log"; fi
}

# HEADLINE relief A/B: same build, same vantage — SMOOTH per-vertex normal vs the OLD flat per-face
# normal (rt.flatnormal). Curved shadowed geometry should show top-lit/underside-dark RELIEF with
# smooth ON and faceted/flat with flat ON. AO OFF throughout (the relief is the normal, not AO).
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still smooth_h8
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still flat_h8
# DIRECT normal-smoothness proof: debug-2 = world-normal viz. Smooth ON => continuous normal-colour
# gradient across curved surfaces; flat => hard-edged flat-colour facets. Camera-independent aggregate.
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=2  run still smooth_nrm
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=1 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=2  run still flat_nrm
# realtime-ON (smooth) vs stock BAKED (rt.light=0 => OFF == stock legacy baked path).
RTL_HOUR=8 RTL_LIGHT=0 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still baked_h8
# TIER climb on the smooth normals: SH (model 1) and IBL (model 2), richer directional ambient.
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=1 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still sh_h8
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=2 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run still ibl_h8
# geometry-pin orbit (form pinned to geometry under camera move), smooth normals.
RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 RTL_FLATNORMAL=0 AO_MODE=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0  run orbit smooth_orbit

# ---------- 5: promote representative PNGs to device/ root ----------
say "promote representative frames to device/ root"
for tag in smooth_h8 flat_h8 smooth_nrm flat_nrm baked_h8 sh_h8 ibl_h8 smooth_orbit; do
  d="$OUT/frames_$tag"; [ -d "$d" ] || continue
  n=$(ls "$d"/*.png 2>/dev/null | wc -l); [ "$n" -gt 0 ] || continue
  mid=$(ls "$d"/*.png | sed -n "$(( n/2 ))p"); late=$(ls "$d"/*.png | tail -1)
  cp "$mid"  "$OUT/still_${tag}_mid.png"  2>/dev/null || true
  cp "$late" "$OUT/still_${tag}_late.png" 2>/dev/null || true
done
ls -la "$OUT"/still_*.png "$OUT"/gda_*.mp4 2>/dev/null | tail -40

# ---------- 6: objective A/B measurements ----------
say "measure: normal-smoothness (debug-2) + relief gradient, smooth vs flat"
python3 - "$OUT" <<'PY' | tee "$OUT/measure2.txt"
import sys, glob, os
import numpy as np
try:
    from PIL import Image
except Exception as e:
    print("PIL unavailable:", e); sys.exit(0)
OUT=sys.argv[1]
def frames(tag):
    return sorted(glob.glob(f"{OUT}/frames_{tag}/*.png"))
def load(f):
    return np.asarray(Image.open(f).convert("RGB")).astype(np.float32)/255.0
def lum(a): return 0.299*a[...,0]+0.587*a[...,1]+0.114*a[...,2]

# (A) NORMAL SMOOTHNESS via debug-2 world-normal viz: number of DISTINCT quantized normal
# directions (8 levels/channel) averaged over frames. Smooth per-vertex normals span many
# directions continuously => far more distinct colours than flat per-face facets. Camera-
# independent-ish: same warp + same pan for both, so the delta is the reconstruction, not the view.
def distinct_normals(tag):
    fs=frames(tag)
    if not fs: return None
    counts=[]
    for f in fs:
        a=load(f)
        q=np.floor(np.clip(a,0,0.999)*8).astype(np.int32)   # 8 levels/channel
        key=q[...,0]*64+q[...,1]*8+q[...,2]
        # ignore near-black background (sky/HUD) so we measure geometry normals
        L=lum(a)
        key=key[L>0.06]
        counts.append(len(np.unique(key)))
    return float(np.mean(counts)), len(fs)
sm=distinct_normals("smooth_nrm"); fl=distinct_normals("flat_nrm")
if sm and fl:
    print(f"[normal-smoothness debug-2] distinct normal directions (mean/frame, higher=smoother):")
    print(f"   SMOOTH normals: {sm[0]:.1f}  ({sm[1]} frames)")
    print(f"   FLAT   normals: {fl[0]:.1f}  ({fl[1]} frames)")
    if fl[0]>0:
        print(f"   ratio smooth/flat = {sm[0]/fl[0]:.2f}x  (>1 => smooth normals vary far more => curved relief)")

# (B) RELIEF in shadow: within SHADOWED pixels (rt on, low luminance) measure the mean local
# luminance-gradient magnitude (Sobel). Smooth normals give a continuous shaded gradient across a
# curved surface; flat facets are near-constant inside each face. Aggregate over frames.
def shadow_gradient(tag):
    fs=frames(tag)
    if not fs: return None
    vals=[]
    for f in fs:
        L=lum(load(f))
        gy,gx=np.gradient(L)
        g=np.hypot(gx,gy)
        shad=(L>0.02)&(L<0.40)     # shadowed geometry, exclude pure black + bright/sunlit
        if shad.sum()>2000:
            vals.append(float(g[shad].mean()))
    return (float(np.mean(vals)), len(vals)) if vals else None
sm=shadow_gradient("smooth_h8"); fl=shadow_gradient("flat_h8")
if sm and fl:
    print(f"[relief in shadow] mean local luminance gradient in shadowed regions (higher=more form):")
    print(f"   SMOOTH normals: {sm[0]:.4f}  ({sm[1]} frames)")
    print(f"   FLAT   normals: {fl[0]:.4f}  ({fl[1]} frames)")

# (C) rt-ON vs stock-baked, and tiers: mean luminance for a quick sanity read (owner eye gates look).
for tag,lbl in [("smooth_h8","rt smooth hemi"),("baked_h8","stock baked (rt off)"),
                ("sh_h8","rt smooth SH"),("ibl_h8","rt smooth IBL")]:
    fs=frames(tag)
    if fs:
        a=load(fs[len(fs)//2]); L=lum(a)
        print(f"[look] {lbl:22s} meanL={L.mean():.3f} bright(>0.5)frac={(L>0.5).mean():.3f} ({os.path.basename(fs[len(fs)//2])})")
PY
say "DONE — eyeball still_smooth_h8 vs still_flat_h8 (relief) and still_smooth_nrm vs still_flat_nrm (normals)"
