#!/usr/bin/env bash
# Objective frame-pacing A/B via the game's OWN dyn-render-scale clock
# ([dyn-rs] avg-fps=...), which is the real in-engine framerate. method-17+nav
# ENABLED (shipped) vs method-17 re-noop'd (pre-polish path). Feel stays owner-judged;
# this only MEASURES whether the newly-active nav-mesh path tanks the framerate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44
PKG=org.opengoal.gk.jak2; ACT=org.opengoal.gk.LoaderActivity
OUT=.autoport/reports/Gjak2-polish/evidence; mkdir -p "$OUT"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true

ab(){ # $1=label $2=noop_names
  local label="$1" nn="$2"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  $ADB -s $S shell setprop debug.opengoal.jak2.noop_names "$nn" >/dev/null 2>&1 || true
  $ADB -s $S logcat -c >/dev/null 2>&1 || true
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  sleep 50   # reach gameplay
  local F="$OUT/dynrs-$label.log"
  timeout 32 $ADB -s $S logcat -v brief opengoal-gk:V '*:S' 2>/dev/null | grep -a "dyn-rs" > "$F" || true
  python3 - "$F" "$label" "$nn" <<'PY'
import sys,re,statistics as st
f,label,nn=sys.argv[1],sys.argv[2],sys.argv[3]
fps=[float(m) for m in re.findall(r'avg-fps=([0-9.]+)', open(f).read())]
sc =[float(m) for m in re.findall(r'scale=([0-9]+)%', open(f).read())]
if len(fps)<5:
    print(f"[{label}] noop='{nn}' — only {len(fps)} dyn-rs samples (not enough)")
else:
    print(f"[{label}] noop='{nn}' samples={len(fps)} avg-fps: min={min(fps):.1f} median={st.median(fps):.1f} mean={sum(fps)/len(fps):.1f} max={max(fps):.1f} stdev={st.pstdev(fps):.2f} | scale%: min={min(sc):.0f} median={st.median(sc):.0f}")
PY
}
echo "######## A: method-17+nav ENABLED (shipped) ########"
ab "m17-ON"  '""'
echo "######## B: method-17 re-noop'd (pre-polish collision path) ########"
ab "m17-OFF" '(method 17 collide-cache)'
# restore shipped config
$ADB -s $S shell setprop debug.opengoal.jak2.noop_names '""' >/dev/null 2>&1 || true
$ADB -s $S shell svc power stayon false >/dev/null 2>&1 || true
echo "DONE"
