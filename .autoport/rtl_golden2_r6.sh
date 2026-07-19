#!/usr/bin/env bash
# rtl_golden2_r6.sh — round-6 re-tuned proof (SAME BOOT, STATIC CAMERA) + intensity sweep.
# One continuous record; the prop timeline:
#   t~3  : form-AO OFF                     (seg A: off)
#   t~7  : form-AO ON  (default 8192/0.5)  (seg B: on)  -> golden+relief A/B
#   t~11 : pbr.debug 12                    (seg C: sun mask)
#   t~15 : pbr.debug 13                    (seg D: viz @ intensity 0.5 default)
#   t~19 : form_ao.intensity 0.7           (seg E: viz stronger)
#   t~23 : form_ao.intensity 0.35          (seg F: viz weaker)
# Picks the differential (open bright / nooks dark) that reads as FORM, not a uniform crush.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
POS="-112.0 42.0 205.0"; HOUR=8
adbs(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
sp(){ adbs shell "setprop $1 '$2'" </dev/null; }
say(){ echo "[r6-golden2] $*"; }
LOG="$OUT/logcat_golden2_r6.log"

say "boot at sage-wall, form-AO OFF, rt-light ON baked OFF shadow ON, static camera"
for TRY in 1 2 3; do
  adbs shell am force-stop $PKG </dev/null; sleep 2
  sp debug.opengoal.cpad_inject neutral
  sp debug.opengoal.rt.light 1; sp debug.opengoal.rt.baked 0; sp debug.opengoal.pbr.shadowmap 1
  sp debug.opengoal.form_ao.on 0; sp debug.opengoal.form_ao.strength 0.85
  sp debug.opengoal.form_ao.intensity ''; sp debug.opengoal.form_ao.radius ''
  sp debug.opengoal.ao.force_mode -1; sp debug.opengoal.pbr.debug 0
  sp debug.opengoal.tod.hour $HOUR; sp debug.opengoal.tod.fast ''
  sp debug.opengoal.level.warp village1-hut; sp debug.opengoal.level.warp.pos "$POS"
  adbs logcat -b all -c </dev/null || true
  ( adbs logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/rtl_g2_lc.pid )
  adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
  ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
    sleep 3
  done
  say "try#$TRY warp_ok=$ok"; [ "$ok" = 1 ] && break
done
[ "$ok" = 1 ] || { say "warp never spawned"; exit 1; }
say "settle 15s"; sleep 15
FOCUS="$(adbs shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE mCurrentFocus | tr -d '\r')"
say "focus: $FOCUS"

adbs shell rm -f /sdcard/rtl_g2.mp4 </dev/null
( sleep 5;  sp debug.opengoal.form_ao.on 1
  sleep 4;  sp debug.opengoal.pbr.debug 12
  sleep 4;  sp debug.opengoal.pbr.debug 13
  sleep 4;  sp debug.opengoal.form_ao.intensity 0.7
  sleep 4;  sp debug.opengoal.form_ao.intensity 0.35
  sleep 3 ) &
KICK=$!
say "record 26s static while toggling"
adbs shell screenrecord --time-limit 26 --bit-rate 16000000 /sdcard/rtl_g2.mp4 </dev/null
wait $KICK 2>/dev/null || true
adbs pull /sdcard/rtl_g2.mp4 "$OUT/rtl_golden2_r6.mp4" >/dev/null
adbs shell rm -f /sdcard/rtl_g2.mp4 </dev/null
mkdir -p "$OUT/frames_golden2"; rm -f "$OUT/frames_golden2"/*.png
ffmpeg -y -loglevel error -i "$OUT/rtl_golden2_r6.mp4" -vf fps=4 "$OUT/frames_golden2/f_%03d.png"
sleep 1; kill "$(cat /tmp/rtl_g2_lc.pid 2>/dev/null)" 2>/dev/null || true
adbs shell am force-stop $PKG </dev/null
say "frames=$(ls "$OUT/frames_golden2" | wc -l) crash:"; grep -aE 'signal (4|6|11) \(SIG' "$LOG" | head -2 || echo "  (none)"

python3 - "$OUT/frames_golden2" "$OUT/form_ao_golden2_r6.txt" "$FOCUS" <<'PY' 2>>"$OUT/cap_r6.log" || say "measure skipped"
import sys, glob, os
import numpy as np
from PIL import Image
d, outp, focus = sys.argv[1], sys.argv[2], sys.argv[3]
fs = sorted(glob.glob(os.path.join(d,"*.png"))); n=len(fs)
def load(i): i=max(0,min(n-1,i)); return np.asarray(Image.open(fs[i]).convert("RGB")).astype(np.float32)/255.0
def lum(im): return 0.299*im[...,0]+0.587*im[...,1]+0.114*im[...,2]
# toggles at t=5,9,13,17,21; sample last second of each 4s seg (fps=4):
i_off,i_on,i12,i13a,i13b,i13c = int(4.5*4),int(8.5*4),int(12.5*4),int(16.5*4),int(20.5*4),int(24.5*4)
off,on,m12 = load(i_off),load(i_on),load(i12)
lo,ln,l12 = lum(off),lum(on),lum(m12); H,W=lo.shape; ys=slice(H//4,H)
d_=ln[ys]-lo[ys]; l12w=l12[ys]
sun=l12w>0.85; floor=(l12w>0.05)&(l12w<0.40)
L=[f"re-tuned same-boot proof n={n} {W}x{H} focus={focus}",
   f"SUN mask(mode12>0.85): {100*sun.mean():.1f}% mean|on-off|={np.abs(d_[sun]).mean() if sun.any() else float('nan'):.4f} median={np.median(np.abs(d_[sun])) if sun.any() else float('nan'):.4f} (GOLDEN=>~0)",
   f"FLOOR mask(0.05..0.40): {100*floor.mean():.1f}% mean(on-off)={d_[floor].mean() if floor.any() else float('nan'):+.4f} (RELIEF=>neg)"]
def vizstat(i,tag):
    v=lum(load(i))[ys]
    L.append(f"VIZ {tag}: mean={v.mean():.3f} p10={np.percentile(v,10):.3f} p50={np.percentile(v,50):.3f} p90={np.percentile(v,90):.3f} spread(p90-p10)={np.percentile(v,90)-np.percentile(v,10):.3f}")
    return i
vizstat(i13a,"int0.5(default)"); vizstat(i13b,"int0.7"); vizstat(i13c,"int0.35")
txt="\n".join(L); print(txt); open(outp,"w").write(txt+"\n")
for i,t in [(i_off,"g2_off"),(i_on,"g2_on"),(i12,"g2_mode12"),(i13a,"g2_viz_int05"),(i13b,"g2_viz_int07"),(i13c,"g2_viz_int035")]:
    Image.open(fs[max(0,min(n-1,i))]).save(os.path.join(os.path.dirname(d),f"r6_{t}.png"))
PY
say "DONE:"; cat "$OUT/form_ao_golden2_r6.txt" 2>/dev/null
echo "R6_GOLDEN2_DONE"
