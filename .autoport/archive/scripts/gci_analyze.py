#!/usr/bin/env python3
# Gcamera-interp analyzer. Parses the extended PACE-EE logcat lines (yaw/pitch +
# Jak world pos + beta) over the PAN phase and quantifies the camera "steps/jumps"
# the owner sees: the frame-to-frame irregularity of the DISPLAYED camera angular
# velocity. Lower jitter == smoother pan. Run on the A/B toggle off vs on logs.
#
#   usage: gci_analyze.py <log> [phase=pan]
#
# PACE-EE dt_ms=.. k=.. afc=.. bfc=.. cam=x,y,z yaw=.. valid=1 pitch=.. jak=x,y,z beta=..
import re, sys, math

LOG = sys.argv[1]
PHASE = sys.argv[2] if len(sys.argv) > 2 else "pan"
# optional 3rd arg = cut threshold (deg): drop |dyaw|>CUT frames (camera cuts in a
# flythrough) so only continuous motion is measured. 0 / absent = keep all.
CUT = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0

pat = re.compile(
    r"PACE-EE dt_ms=([-\d.]+) k=(\d+) afc=(\d+) bfc=(\d+) "
    r"cam=([-\d.]+),([-\d.]+),([-\d.]+) yaw=([-\d.]+) valid=([01])"
    r"(?: pitch=([-\d.]+) jak=([-\d.]+),([-\d.]+),([-\d.]+) beta=([-\d.]+))?"
)

rows = []
phase = "baseline"
with open(LOG, "rb") as f:
    for raw in f:
        line = raw.decode("utf-8", "replace")
        if "GCAM-BASELINE-BEGIN" in line: phase = "baseline"
        elif "GCAM-PAN-BEGIN" in line:    phase = "pan"
        elif "GCAM-PAN-END" in line:      phase = "post"
        m = pat.search(line)
        if not m or phase != PHASE: continue
        dt, k, afc, bfc = float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        yaw, valid = float(m.group(8)), int(m.group(9))
        pitch = float(m.group(10)) if m.group(10) else float("nan")
        jak = (float(m.group(11)), float(m.group(12)), float(m.group(13))) if m.group(11) else None
        beta = float(m.group(14)) if m.group(14) else float("nan")
        if valid != 1: continue
        rows.append(dict(dt=dt, k=k, afc=afc, bfc=bfc, yaw=yaw, pitch=pitch, jak=jak, beta=beta))

def stats(xs):
    xs = [x for x in xs if x == x]
    if not xs: return (0,0,0,0)
    n=len(xs); mean=sum(xs)/n
    sd=math.sqrt(sum((x-mean)**2 for x in xs)/n) if n>1 else 0.0
    return (n, mean, sd, sd/abs(mean) if mean else 0.0)

# angular deltas over 1-frame steps (afc advances by 1 per render)
dyaw, avel, jak_d, betas, ks = [], [], [], [], []
prev = None
for r in rows:
    betas.append(r["beta"]); ks.append(r["k"])
    if prev is not None:
        dafc = r["afc"] - prev["afc"]
        if 1 <= dafc <= 3 and r["dt"] > 0:
            # unwrap yaw across +-180
            d = r["yaw"] - prev["yaw"]
            while d > 180: d -= 360
            while d < -180: d += 360
            if CUT > 0 and abs(d) > CUT:
                prev = r; continue                 # skip camera-cut frame
            dyaw.append(d)
            avel.append(d / (r["dt"] * dafc))      # deg per ms (displayed angular velocity)
            if r["jak"] and prev["jak"]:
                jd = math.dist(r["jak"], prev["jak"])
                jak_d.append(jd)
    prev = r

# jerk = std of successive changes in per-frame yaw-delta (the "step/jump" signature)
jerk = [dyaw[i]-dyaw[i-1] for i in range(1, len(dyaw))]

# GAME SPEED: base-frame-counter advance per wall-second (must be identical off/on;
# the render-time camera fix never touches the game clock). Sum bfc advance / sum dt.
bfc_adv = 0; wall_ms = 0.0
prev = None
for r in rows:
    if prev is not None:
        dafc = r["afc"] - prev["afc"]
        if 1 <= dafc <= 3:
            bfc_adv += (r["bfc"] - prev["bfc"]); wall_ms += r["dt"] * dafc
    prev = r
game_speed = (bfc_adv / (wall_ms/1000.0)) if wall_ms > 0 else 0.0  # base-frames / real-sec

print(f"=== {LOG}  phase={PHASE}  frames={len(rows)} ===")
n,mean,sd,cov = stats(ks);           print(f"  k                : mean={mean:.2f} sd={sd:.2f}  hist={{{','.join(str(x) for x in sorted(set(ks)))}}}")
n,mean,sd,cov = stats(betas);        print(f"  beta (applied)   : mean={mean:+.4f} sd={sd:.4f}  (0 => interp OFF)")
n,mean,sd,cov = stats([abs(x) for x in dyaw]); print(f"  |dyaw|/frame     : n={n} mean={mean:.4f} sd={sd:.4f} deg")
n,mean,sd,cov = stats(avel);         print(f"  ang.vel dyaw/ms  : mean={mean:+.5f} sd={sd:.5f} CoV={cov:.3f}   <-- SMOOTHNESS (lower CoV = smoother)")
n,mean,sd,cov = stats(jerk);         print(f"  jerk d(dyaw)     : sd={sd:.4f} deg   <-- STEP/JUMP size (lower = fewer jumps)")
print(f"  game speed       : {game_speed:.1f} base-frames/real-sec   <-- must MATCH off vs on (clock untouched)")
# present fps: from per-render-frame dt (dt_ms is the real wall time of the frame).
dts = [r["dt"] for r in rows if r["dt"] and r["dt"] > 0]
if dts:
    mean_dt = sum(dts)/len(dts)
    fps = 1000.0/mean_dt if mean_dt > 0 else 0.0
    n,mdt,sdd,cov = stats(dts)
    print(f"  present fps      : {fps:.1f} fps (mean dt={mean_dt:.2f}ms sd={sdd:.2f})   <-- must NOT regress off vs on")
if avel:
    a=sorted(abs(x) for x in avel); print(f"  ang.vel p50={a[len(a)//2]:.5f} p95={a[int(len(a)*0.95)]:.5f} max={a[-1]:.5f} deg/ms")
if jak_d:
    n,mean,sd,cov = stats(jak_d);    print(f"  Jak dpos/frame   : n={n} mean={mean:.1f} sd={sd:.1f} u  (world reference; smooth if steady)")
