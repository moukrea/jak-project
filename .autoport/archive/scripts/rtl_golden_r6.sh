#!/usr/bin/env bash
# rtl_golden_r6.sh — AIRTIGHT round-6 golden-rule proof: SAME BOOT, STATIC CAMERA.
# One continuous screenrecord while toggling props, so the four frames are pixel-aligned
# (only the feature changes, not the camera):
#   seg A t~3s : form-AO OFF   (debug.opengoal.form_ao.on 0, pbr.debug 0)
#   seg B t~7s : form-AO ON    (form_ao.on 1)                -> the A/B twin, aligned
#   seg C t~11s: mode 12       (pbr.debug 12 = lighting fraction = sun mask; form still on)
#   seg D t~15s: mode 13       (pbr.debug 13 = raw wide Form-AO visibility)
# Golden rule = over the SUN mask (mode12 high => sun_scalar~1), |B-A| ~ 0 (sunlit unchanged).
# Relief      = over the FLOOR mask (mode12 low => shadow), B-A < 0 (shadow darkened).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
POS="-112.0 42.0 205.0"; HOUR=8
adbs(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
sp(){ adbs shell "setprop $1 '$2'" </dev/null; }
say(){ echo "[r6-golden] $*"; }

LOG="$OUT/logcat_golden_r6.log"
say "boot at sage-wall vantage, form-AO OFF, rt-light ON baked OFF shadow ON, static camera"
for TRY in 1 2 3; do
  adbs shell am force-stop $PKG </dev/null; sleep 2
  sp debug.opengoal.cpad_inject neutral
  sp debug.opengoal.rt.light 1; sp debug.opengoal.rt.baked 0; sp debug.opengoal.pbr.shadowmap 1
  sp debug.opengoal.form_ao.on 0; sp debug.opengoal.form_ao.strength 0.85
  sp debug.opengoal.ao.force_mode -1; sp debug.opengoal.pbr.debug 0
  sp debug.opengoal.tod.hour $HOUR; sp debug.opengoal.tod.fast ''
  sp debug.opengoal.level.warp village1-hut; sp debug.opengoal.level.warp.pos "$POS"
  adbs logcat -b all -c </dev/null || true
  ( adbs logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/rtl_golden_lc.pid )
  adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
  ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
    sleep 3
  done
  say "try#$TRY warp_ok=$ok"
  [ "$ok" = 1 ] && break
done
[ "$ok" = 1 ] || { say "warp never spawned"; exit 1; }

say "settle 15s (let the follow-cam fully stop; Jak idle => static camera)"
sleep 15
FOCUS="$(adbs shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE mCurrentFocus | tr -d '\r')"
say "focus: $FOCUS"

# One continuous record; toggle the feature/debug props on a timeline in the background.
adbs shell rm -f /sdcard/rtl_golden.mp4 </dev/null
( sleep 5;  sp debug.opengoal.form_ao.on 1              # -> seg B form-AO ON
  sleep 4;  sp debug.opengoal.pbr.debug 12              # -> seg C sun mask (form still on)
  sleep 4;  sp debug.opengoal.pbr.debug 13              # -> seg D form-AO viz
  sleep 3 ) &
KICK=$!
say "record 18s (static) while toggling props"
adbs shell screenrecord --time-limit 18 --bit-rate 16000000 /sdcard/rtl_golden.mp4 </dev/null
wait $KICK 2>/dev/null || true
adbs pull /sdcard/rtl_golden.mp4 "$OUT/rtl_golden_r6.mp4" >/dev/null
adbs shell rm -f /sdcard/rtl_golden.mp4 </dev/null
mkdir -p "$OUT/frames_golden"; rm -f "$OUT/frames_golden"/*.png
ffmpeg -y -loglevel error -i "$OUT/rtl_golden_r6.mp4" -vf fps=4 "$OUT/frames_golden/f_%03d.png"
sleep 1; kill "$(cat /tmp/rtl_golden_lc.pid 2>/dev/null)" 2>/dev/null || true
adbs shell am force-stop $PKG </dev/null
say "frames=$(ls "$OUT/frames_golden" | wc -l)  crash-scan:"
grep -aE 'signal (4|6|11) \(SIG' "$LOG" | head -2 || echo "  (none)"

# ---- measure: pick a frame from each ~4s segment (fps=4 => segment boundaries ~ frame 20/36/52/64) ----
say "measure golden rule (sun mask) + relief (floor mask), pixel-aligned same-boot"
python3 - "$OUT/frames_golden" "$OUT/form_ao_golden_r6.txt" "$FOCUS" <<'PY' 2>>"$OUT/cap_r6.log" || say "measure skipped"
import sys, glob, os
import numpy as np
try:
    from PIL import Image
except Exception as e:
    print("no PIL:", e); sys.exit(0)
d, outp, focus = sys.argv[1], sys.argv[2], sys.argv[3]
fs = sorted(glob.glob(os.path.join(d, "*.png")))
n = len(fs)
def load(i):
    i = max(0, min(n-1, i))
    return np.asarray(Image.open(fs[i]).convert("RGB")).astype(np.float32)/255.0
def lum(im): return 0.299*im[...,0]+0.587*im[...,1]+0.114*im[...,2]
# fps=4, record 18s. Toggles at t=5 (on), t=9 (dbg12), t=13 (dbg13). Sample the LAST second of
# each segment: off@t=4.5(i18), on@t=8.5(i34), dbg12@t=12.5(i50), dbg13@t=16.5(i66).
i_off, i_on, i12, i13 = int(4.5*4), int(8.5*4), int(12.5*4), int(16.5*4)
off, on, m12, m13 = load(i_off), load(i_on), load(i12), load(i13)
lines=[f"same-boot static-camera golden proof; frames n={n}; focus={focus}",
       f"indices off={i_off} on={i_on} mode12={i12} mode13={i13} ({off.shape[1]}x{off.shape[0]})"]
lo, ln = lum(off), lum(on); l12 = lum(m12); l13 = lum(m13)
H,W = lo.shape
# restrict to world region (drop top sky strip) and to non-UI center
ys = slice(H//4, H)  # keep most of the frame below the sky band
lo_w, ln_w, l12_w = lo[ys], ln[ys], l12[ys]
d = ln_w - lo_w                      # form_on - form_off (aligned)
sun  = l12_w > 0.85                  # sun_scalar ~ >0.8  => GOLDEN RULE zone
floor= (l12_w > 0.05) & (l12_w < 0.40)  # shadow/away floor zone => RELIEF zone
lines.append(f"SUN mask (mode12>0.85, sun_scalar~1): {100*sun.mean():.1f}% of region, mean|on-off|={np.abs(d[sun]).mean() if sun.any() else float('nan'):.4f}  median|.|={np.median(np.abs(d[sun])) if sun.any() else float('nan'):.4f}  (GOLDEN RULE => ~0)")
lines.append(f"FLOOR mask (mode12 0.05..0.40, shadow): {100*floor.mean():.1f}% of region, mean(on-off)={d[floor].mean() if floor.any() else float('nan'):+.4f}  (RELIEF => negative)")
# how many sun pixels changed more than 2% (should be a tiny fraction if golden rule holds)
if sun.any():
    big = (np.abs(d[sun])>0.02).mean()
    lines.append(f"SUN pixels changing >2%: {100*big:.1f}%  (golden rule => small)")
# viz smoothness (mode13)
l13_w = l13[ys]
gx = np.abs(np.diff(l13_w,axis=1)); gy = np.abs(np.diff(l13_w,axis=0))
lines.append(f"Form-AO viz (mode13): mean vis={l13_w.mean():.3f} local-grad gx={gx.mean():.4f} gy={gy.mean():.4f}  (SMOOTH => small, no staircase)")
txt="\n".join(lines); print(txt); open(outp,"w").write(txt+"\n")
# promote the four aligned stills
for i,tag in [(i_off,"golden_off"),(i_on,"golden_on"),(i12,"golden_mode12"),(i13,"golden_mode13")]:
    try: Image.open(fs[max(0,min(n-1,i))]).save(os.path.join(os.path.dirname(d), f"r6_{tag}.png"))
    except Exception as e: print("promote fail",tag,e)
PY
say "DONE. golden measurement:"; cat "$OUT/form_ao_golden_r6.txt" 2>/dev/null
echo "R6_GOLDEN_DONE"
