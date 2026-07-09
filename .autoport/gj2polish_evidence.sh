#!/usr/bin/env bash
# gj2polish_evidence.sh — post-deploy objective evidence for Gjak2-polish round-3.
# Captures: (1) fresh boot-to-gameplay screencap with mCurrentFocus=jak2 bracket,
# (2) A/B frame-pacing via SurfaceFlinger present timestamps for method-17+nav ON vs OFF
#     (collision/speed regression is objectively the per-frame nav-mesh DMA cost — this
#      MEASURES it; feel stays owner-judged), (3) an intro-cutscene grab for the aspect item.
# Subjective calls (glow level, cutscene fill, speed/collision feel) are NOT certified here.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak2; ACT=org.opengoal.gk.LoaderActivity
OUT=.autoport/reports/Gjak2-polish/evidence; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }

$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true

# --- A/B frame pacing --------------------------------------------------------
# layer name of the game surface
pace_measure(){ # $1=label  $2=noop_names value
  local label="$1" nn="$2"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  $ADB -s $S shell setprop debug.opengoal.jak2.noop_names "$nn" >/dev/null 2>&1 || true
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  sleep 45   # let it boot to gameplay
  local LAYER
  LAYER=$($ADB -s $S shell dumpsys SurfaceFlinger --list 2>/dev/null | tr -d '\r' | grep -iE "$PKG|SurfaceView.*gk|org.opengoal" | tail -1)
  [ -z "$LAYER" ] && LAYER=$($ADB -s $S shell dumpsys SurfaceFlinger --list 2>/dev/null | tr -d '\r' | grep -iE 'blast|surfaceview' | tail -1)
  echo "  [$label] noop_names='$nn' layer='$LAYER'"
  # sample present timestamps twice over ~6s; SurfaceFlinger --latency emits vsync/present ns
  $ADB -s $S shell dumpsys SurfaceFlinger --latency "$LAYER" 2>/dev/null | tr -d '\r' > "$OUT/pace-$label-1.txt"
  sleep 6
  $ADB -s $S shell dumpsys SurfaceFlinger --latency "$LAYER" 2>/dev/null | tr -d '\r' > "$OUT/pace-$label-2.txt"
  # focus + a screencap
  local FOCUS; FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
  echo "  [$label] focus=$FOCUS"
  $ADB -s $S exec-out screencap -p > "$OUT/pace-$label.png" 2>/dev/null || true
  # compute median/jitter of present intervals (col3 present-ns) in python
  python3 - "$OUT/pace-$label-2.txt" "$label" <<'PY'
import sys
f,label=sys.argv[1],sys.argv[2]
ts=[]
for ln in open(f):
    p=ln.split()
    if len(p)==3:
        try:
            v=int(p[2])
        except: continue
        if v>0 and v!=9223372036854775807: ts.append(v)
ts=sorted(ts)
if len(ts)<8:
    print(f"  [{label}] pacing: insufficient present samples ({len(ts)}) — SurfaceFlinger latency empty for native surface")
else:
    d=[(ts[i+1]-ts[i])/1e6 for i in range(len(ts)-1)]
    d=[x for x in d if 0<x<100]
    d.sort()
    import statistics as st
    med=st.median(d); mean=sum(d)/len(d)
    p95=d[int(len(d)*0.95)]; jit=st.pstdev(d)
    print(f"  [{label}] frames={len(d)} median={med:.2f}ms mean={mean:.2f}ms p95={p95:.2f}ms jitter(std)={jit:.2f}ms")
PY
}

say "A. pacing: method-17+nav ENABLED (current build — the config owner tested)"
pace_measure "m17-ON" '""'
say "B. pacing: method-17 re-noop'd (pre-polish collision path — owner-confirmed-good baseline)"
pace_measure "m17-OFF" '(method 17 collide-cache)'

# restore default (all enabled) for the shipped state
$ADB -s $S shell setprop debug.opengoal.jak2.noop_names '""' >/dev/null 2>&1 || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 40

say "C. fresh gameplay screencap + focus bracket (shipped config)"
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
PID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
$ADB -s $S exec-out screencap -p > "$OUT/gj2polish-gameplay.png" 2>/dev/null || true
echo "  focus=$FOCUS pid=$PID  -> $OUT/gj2polish-gameplay.png"
$ADB -s $S shell svc power stayon false >/dev/null 2>&1 || true
echo "[gj2polish-evidence] DONE"
