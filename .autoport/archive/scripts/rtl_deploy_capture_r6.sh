#!/usr/bin/env bash
# rtl_deploy_capture_r6.sh — ROUND-6 FORM-AO deploy + device proof.
# FORM-AO = a SEPARATE wide-radius ambient occlusion that darkens ONLY the ~0.2 skylight
# floor (relief in shadow), independent of the shipped standalone AO, golden rule = sunlit
# unchanged. Captures: form-AO ON vs OFF A/B (relief + golden rule), the raw wide-AO
# visibility (mode 13, must be smooth), the independence/stack tests (shipped AO x form-AO),
# and an ON orbit clip. Then measures the ON-vs-OFF regional stats (golden rule objective).
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
say(){ echo "[r6-deploy] $*"; }

# ---------- 1+2: install + launch (re-unpack custom assets) ----------
say "MIUI unblock"
adbs shell cmd appops set com.android.shell REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
adbs shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
adbs shell settings put global package_verifier_enable 0 >/dev/null 2>&1 || true
STAGE="/data/local/tmp/$(basename "$APK")"
say "push APK ($(stat -c %s "$APK") bytes)"
adbs push "$APK" "$STAGE" >/tmp/r6-push.out 2>&1 || { cat /tmp/r6-push.out; echo "PUSH FAIL"; exit 2; }
say "pm install"
adbs shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/r6-pm.out 2>&1
grep -q Success /tmp/r6-pm.out || { cat /tmp/r6-pm.out; echo "PM INSTALL FAIL"; exit 2; }
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
if bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >"$OUT/deploy_verify_r6.txt" 2>&1; then
  say "deploy_verify PASS"; tail -3 "$OUT/deploy_verify_r6.txt"
else
  say "deploy_verify FAILED — see $OUT/deploy_verify_r6.txt"; tail -20 "$OUT/deploy_verify_r6.txt"
  echo "DEPLOY_VERIFY_FAIL"; exit 3
fi

# ---------- 4: capture stages ----------
: > "$OUT/cap_r6.log"
run(){ local stage="$1" tag="$2"
  say "capture $stage $tag  (FORM_AO=${FORM_AO:-0} STR=${FORM_AO_STRENGTH:-def} AO_MODE=${AO_MODE:--1} dbg=${RTL_DEBUG_MODE:-0})"
  if timeout 600 bash "$CAP" "$stage" "$tag" >>"$OUT/cap_r6.log" 2>&1; then
    say "  $tag OK frames=$(ls "$OUT/frames_$tag" 2>/dev/null | wc -l)"
  else
    say "  $tag FAILED (continuing)"; tail -3 "$OUT/cap_r6.log"
  fi
}

# The owner sage-wall vantage (default POS in the capture) has a flat shadowed wall + ground
# — exactly where the round-5 floor reads FLAT and Form-AO must restore relief.
# A/B twin: identical everything except form_ao.on -> the golden-rule + relief measurement.
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 FORM_AO=0                       run still form_off
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 FORM_AO=1 FORM_AO_STRENGTH=0.85 run still form_on
# raw wide Form-AO visibility (debug mode 13): must read SMOOTH (heavily blurred), never blocky.
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=13 FORM_AO=1 FORM_AO_STRENGTH=0.85 run still form_viz
# INDEPENDENCE / STACK: shipped standalone AO (GTAO) ON, with Form-AO ON (both) then OFF (shipped alone).
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 AO_MODE=3 FORM_AO=1 FORM_AO_STRENGTH=0.85 run still stack_both
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 AO_MODE=3 FORM_AO=0                        run still stack_shiponly
# required mp4 + Form-AO pinned under a camera orbit
RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 RTL_DEBUG_MODE=0 FORM_AO=1 FORM_AO_STRENGTH=0.85 run orbit form_on_orbit

# ---------- 5: promote representative PNGs to device/ root ----------
say "promote representative frames to device/ root"
for tag in form_off form_on form_viz stack_both stack_shiponly form_on_orbit; do
  d="$OUT/frames_$tag"; [ -d "$d" ] || continue
  mapfile -t fs < <(ls "$d"/*.png 2>/dev/null | sort)
  n=${#fs[@]}; [ "$n" -eq 0 ] && continue
  cp "${fs[$((n/2))]}" "$OUT/r6_${tag}_mid.png"
  cp "${fs[$((n-1))]}" "$OUT/r6_${tag}_late.png"
done
ls "$OUT"/r6_*.png 2>/dev/null | head

# ---------- 6: golden-rule + relief measurement (form_on vs form_off, matched frame index) ----------
say "measure golden rule (sunlit unchanged) + relief (shadow darkened)"
python3 - "$OUT/frames_form_off" "$OUT/frames_form_on" "$OUT/frames_form_viz" "$OUT/form_ao_measure_r6.txt" <<'PY' 2>>"$OUT/cap_r6.log" || say "measure skipped (numpy/PIL?)"
import sys, glob, os
import numpy as np
try:
    from PIL import Image
except Exception as e:
    print("no PIL:", e); sys.exit(0)
d_off, d_on, d_viz, outp = sys.argv[1:5]
def load(d):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    return fs
foff, fon, fviz = load(d_off), load(d_on), load(d_viz)
lines=[]
def lum(im): return 0.299*im[...,0]+0.587*im[...,1]+0.114*im[...,2]
if foff and fon:
    # matched frame index (identical scripted look-around => same camera angle per index).
    k = min(len(foff), len(fon))
    i = k//2
    a = np.asarray(Image.open(foff[i]).convert("RGB")).astype(np.float32)/255.0
    b = np.asarray(Image.open(fon[i]).convert("RGB")).astype(np.float32)/255.0
    if a.shape == b.shape:
        la, lb = lum(a), lum(b)
        H,W = la.shape
        la_w, lb_w = la[H//3:], lb[H//3:]   # world region (drop top sky strip)
        d = lb_w - la_w                      # negative = Form-AO darkened
        # SUNLIT subset = bright in OFF (>0.5): golden rule => ~no change.
        sun = la_w > 0.5
        # SHADOW/floor subset = dim in OFF (0.08..0.42): relief => should darken.
        sh  = (la_w >= 0.08) & (la_w <= 0.42)
        lines.append(f"A/B frame index {i} (off={os.path.basename(foff[i])} on={os.path.basename(fon[i])}) {W}x{H}")
        lines.append(f"SUNLIT subset (off lum>0.5): {100*sun.mean():.1f}% of world px, mean |delta|={np.abs(d[sun]).mean() if sun.any() else float('nan'):.4f}  (GOLDEN RULE => ~0)")
        lines.append(f"SHADOW subset (off lum 0.08..0.42): {100*sh.mean():.1f}% of world px, mean delta={d[sh].mean() if sh.any() else float('nan'):+.4f}  (RELIEF => negative)")
        lines.append(f"whole-world mean delta={d.mean():+.4f}  (Form-AO only removes floor light, never adds)")
    else:
        lines.append(f"shape mismatch off{a.shape} on{b.shape} — skipping diff")
else:
    lines.append("missing form_off/form_on frames — cannot A/B")
if fviz:
    v = np.asarray(Image.open(fviz[len(fviz)//2]).convert("RGB")).astype(np.float32)/255.0
    lv = lum(v); Hv,Wv = lv.shape; vw = lv[Hv//3:]
    # smoothness: local gradient magnitude of the AO viz should be LOW (heavily blurred).
    gy = np.abs(np.diff(vw, axis=0)); gx = np.abs(np.diff(vw, axis=1))
    lines.append(f"Form-AO viz (mode13) {Wv}x{Hv}: mean visibility={vw.mean():.3f} min={vw.min():.3f}  (1=open, <1=occluded)")
    lines.append(f"Form-AO viz local-gradient mean gx={gx.mean():.4f} gy={gy.mean():.4f}  (SMOOTH => small; blocky => large)")
txt="\n".join(lines); print(txt); open(outp,"w").write(txt+"\n")
PY

say "DONE. measurement:"; cat "$OUT/form_ao_measure_r6.txt" 2>/dev/null
echo "R6_CAPTURE_DONE"
