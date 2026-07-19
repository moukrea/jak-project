#!/usr/bin/env bash
# rtl_night_r7.sh — Grecharged-realtime-lighting ROUND-7 device proof:
#   (1) NIGHT LEAK fixed: at night the whole world is the dark ~0.2 sky-fill floor — NO lit
#       zones anywhere across a camera SWEEP (tfrag + tie + etie + shrub all fade together).
#   (2) Form-AO dropped: no Form-AO menu row / shader term (round-5 flat floor is the baseline).
#   (3) DAY unregressed: at a day hour the sun still lights the sun-side (round-1..5 preserved).
#
# Assumes the round-7 APK is ALREADY installed + deploy_verified (build tester did that).
# Captures four things and measures night-vs-day brightness objectively:
#   A night_h0   orbit  tod.hour=0  rt.light=1 baked=0 shadow=1  -> NIGHT camera SWEEP (mp4)
#   B day_h8     still  tod.hour=8  rt.light=1 baked=0 shadow=1  -> DAY sun still works (png)
#   C sunelev0_h8/sunelev1_h8  still  tod.hour=8, rt.sunelev forced 0 vs 1 — SAME vantage A/B
#       that isolates the night-fade uniform: =0 drops EVERY world shader to the floor (proves
#       the fade reaches all four shader paths), =1 restores the sun.
#   D todsweep   fast TOD cycle clip (day->dusk->night->dawn), no phantom night "spotlights".
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
CAP=.autoport/rtl_device_capture.sh
POS="${RTL_POS:--112.0 42.0 205.0}"   # owner sage-wall vantage
adbs(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
say(){ echo "[r7] $*"; }

# clear any leftover sunelev override so the TOD-driven stages use the REAL sky-sun fade
adbs shell setprop debug.opengoal.rt.sunelev '' </dev/null || true

# ---------- A: NIGHT camera SWEEP (real pinned midnight) ----------
say "A: NIGHT sweep tod.hour=0 (whole world must stay dark floor, nothing lights up)"
RTL_POS="$POS" RTL_HOUR=0 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 bash "$CAP" orbit night_h0 || say "A FAILED (continuing)"

# ---------- B: DAY still (no round-1..5 regression) ----------
say "B: DAY still tod.hour=8 (sun-side lit / away-side floor)"
RTL_POS="$POS" RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 bash "$CAP" still day_h8 || say "B FAILED (continuing)"

# ---------- C: deterministic rt.sunelev A/B at the SAME day vantage ----------
# rtl_device_capture does not set rt.sunelev, so a prop we set here persists through its boot.
say "C1: force night-fade=0 at day hour (every world shader -> floor)"
adbs shell setprop debug.opengoal.rt.sunelev 0 </dev/null
RTL_POS="$POS" RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 bash "$CAP" still sunelev0_h8 || say "C1 FAILED"
say "C2: force night-fade=1 at day hour (sun restored)"
adbs shell setprop debug.opengoal.rt.sunelev 1 </dev/null
RTL_POS="$POS" RTL_HOUR=8 RTL_LIGHT=1 RTL_BAKED=0 RTL_SHADOW=1 bash "$CAP" still sunelev1_h8 || say "C2 FAILED"
adbs shell setprop debug.opengoal.rt.sunelev '' </dev/null   # reset

# ---------- D: fast TOD sweep (title-cycle-style day/night) ----------
say "D: fast TOD sweep (day->dusk->night->dawn); no phantom night lights"
adbs shell am force-stop $PKG </dev/null; sleep 2
adbs shell "setprop debug.opengoal.cpad_inject neutral" </dev/null
adbs shell "setprop debug.opengoal.rt.light 1" </dev/null
adbs shell "setprop debug.opengoal.rt.baked 0" </dev/null
adbs shell "setprop debug.opengoal.pbr.shadowmap 1" </dev/null
adbs shell "setprop debug.opengoal.pbr.debug ''" </dev/null
adbs shell "setprop debug.opengoal.tod.hour ''" </dev/null     # unpin
adbs shell "setprop debug.opengoal.tod.fast 1" </dev/null      # 18000 preset: full day->night->day ~24s
adbs shell setprop debug.opengoal.level.warp village1-hut </dev/null
adbs shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
SLOG="$OUT/logcat_todsweep.log"
adbs logcat -b all -c </dev/null || true
( adbs logcat -b all -v threadtime </dev/null > "$SLOG" 2>/dev/null & echo $! > /tmp/r7_lc.pid )
adbs shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
t0=$(date +%s); ok=0
while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$SLOG" && { ok=1; break; }
  grep -qaE 'signal (4|6|11) \(SIG' "$SLOG" && break
  sleep 3
done
FOCUS_SWEEP="$(adbs shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r')"
say "  todsweep warp_ok=$ok focus=$FOCUS_SWEEP"
if [ "$ok" = 1 ]; then
  sleep 8
  ( sleep 2; for _ in $(seq 1 10); do adbs shell "setprop debug.opengoal.cpad_inject rx=180" </dev/null; sleep 5; done ) &
  KICK=$!
  adbs shell rm -f /sdcard/rtl_todsweep.mp4 </dev/null
  adbs shell screenrecord --time-limit 60 --bit-rate 12000000 /sdcard/rtl_todsweep.mp4 </dev/null
  wait $KICK 2>/dev/null || true
  adbs pull /sdcard/rtl_todsweep.mp4 "$OUT/rtl_todsweep.mp4" >/dev/null 2>&1
  adbs shell rm -f /sdcard/rtl_todsweep.mp4 </dev/null
  mkdir -p "$OUT/frames_todsweep"; rm -f "$OUT/frames_todsweep"/*.png
  ffmpeg -y -loglevel error -i "$OUT/rtl_todsweep.mp4" -vf fps=1 "$OUT/frames_todsweep/f_%03d.png" 2>/dev/null || true
  say "  todsweep frames=$(ls "$OUT/frames_todsweep" 2>/dev/null | wc -l)"
fi
kill "$(cat /tmp/r7_lc.pid 2>/dev/null)" 2>/dev/null || true
adbs shell "setprop debug.opengoal.tod.fast ''" </dev/null
adbs shell am force-stop $PKG </dev/null

# ---------- MEASURE: night-vs-day brightness (objective) ----------
say "MEASURE brightness (bright-pixel fraction: night ~0, day > 0; sunelev0 collapses to ~night)"
python3 - "$OUT" <<'PY' | tee "$OUT/night_measure_r7.txt"
import sys, glob, os
OUT=sys.argv[1]
try:
    from PIL import Image
except Exception as e:
    print("PIL unavailable:", e); sys.exit(0)
def stats(tag):
    fs=sorted(glob.glob(os.path.join(OUT,f"frames_{tag}","*.png")))
    if not fs: return None
    # sample up to 12 frames spread across the clip
    step=max(1,len(fs)//12); fs=fs[::step][:12]
    tot=0; bright=0; mids=0; s=0.0; mx=0.0
    for f in fs:
        im=Image.open(f).convert("L"); px=im.getdata(); n=len(px)
        tot+=n
        for v in px:
            b=v/255.0; s+=b
            if b>mx: mx=b
            if b>0.5: bright+=1
            if b>0.35: mids+=1
    return dict(frames=len(fs), mean=s/tot, bright_frac=bright/tot, mid_frac=mids/tot, max=mx)
rows=[]
for tag in ["night_h0","day_h8","sunelev0_h8","sunelev1_h8","todsweep"]:
    st=stats(tag)
    if st: rows.append((tag,st))
print(f"{'stage':14s} {'frames':>6s} {'mean':>7s} {'>0.5frac':>9s} {'>0.35frac':>9s} {'max':>6s}")
for tag,st in rows:
    print(f"{tag:14s} {st['frames']:6d} {st['mean']:7.3f} {st['bright_frac']:9.4f} {st['mid_frac']:9.4f} {st['max']:6.3f}")
# verdicts
d=dict(rows)
def bf(t): return d[t]['bright_frac'] if t in d else None
print()
if 'night_h0' in d and 'day_h8' in d:
    print(f"NIGHT vs DAY bright(>0.5) frac: night={bf('night_h0'):.4f}  day={bf('day_h8'):.4f}  "
          f"=> {'DARK-NIGHT OK' if bf('night_h0')<0.02 and bf('day_h8')>bf('night_h0')*3+0.01 else 'CHECK'}")
if 'sunelev0_h8' in d and 'sunelev1_h8' in d:
    print(f"sunelev0 vs sunelev1 bright(>0.5) frac: fade0={bf('sunelev0_h8'):.4f}  fade1={bf('sunelev1_h8'):.4f}  "
          f"=> {'FADE-REACHES-ALL-SHADERS OK' if bf('sunelev0_h8')<0.02 and bf('sunelev1_h8')>bf('sunelev0_h8')*3+0.01 else 'CHECK'}")
PY
say "done. frames + measure under $OUT"
