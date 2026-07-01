#!/usr/bin/env bash
# gcam_pace.sh — Gcamera-smooth STATE-ANCHORED measurement (device eae4df44).
#
# Captures, per frame, BOTH:
#   PACE-EE   (EE/GOAL thread, gk_android_main.cpp): the game-clock cadence dt_ms,
#             the integer time-ratio k, the *display* base/actual frame counters,
#             and the *math-camera* pose (trans x,y,z + forward yaw). This is the
#             camera's GAME-STATE motion (should be a constant delta per frame
#             during a steady pan == the golden x86 pattern).
#   PACE-SWAP (GL thread, android_renderer.cpp): the TRUE wall-clock interval
#             between successive SwapWindow presents. This is the on-screen
#             cadence.
# If the game-state camera advances a constant delta per frame but the PRESENT
# interval jitters, that uneven present pacing is the pan judder the owner sees.
#
# Subcommands:
#   run <label> <pan_secs>   warp to Geyser, arm pace.measure, capture a no-input
#                            baseline then a sustained right-stick PAN; harvest
#                            + analyze -> evidence/<label>.log / <label>.analysis.txt
#   parse <logfile>          re-analyze a captured log
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Gcamera-smooth; EV="$OUT/evidence"; mkdir -p "$EV"
die(){ echo "[gcam FAIL] $*" >&2; exit 1; }
log(){ echo "[gcam] $*"; }
wake(){ $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; }
locked(){ $ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

# right-stick camera pan actuation (from grstick_run.sh's proven coords).
drive_pan(){
  local secs="${1:-16}"
  # display (synthetic-input) size, landscape (W>=H)
  local WM RA RB DW DH
  WM=$($ADB shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
  RA=${WM%x*}; RB=${WM#*x}
  if [ "${RA:-0}" -ge "${RB:-0}" ]; then DW=$RA; DH=$RB; else DW=$RB; DH=$RA; fi
  [ "${DW:-0}" -gt 0 ] || { DW=2400; DH=1080; }
  # anchor in the empty right-3/4 camera zone (0.58W,0.52H); clamp offset +0.12W.
  local AX AY BX BY
  AX=$(( DW * 58 / 100 )); AY=$(( DH * 52 / 100 ))
  BX=$(( AX + DW * 12 / 100 )); BY=$AY
  log "pan: anchor=($AX,$AY) clamp=($BX,$BY) display=${DW}x${DH} for ${secs}s"
  $ADB shell log -t opengoal-gk "GCAM-PAN-BEGIN" >/dev/null 2>&1 || true
  # DOWN then hold at the clamp offset -> sustained max RIGHTX (constant yaw rate).
  # Re-issue the MOVE every 2s to refresh any per-pointer throttle and keep it live.
  ( $ADB shell "input motionevent DOWN $AX $AY; input motionevent MOVE $BX $BY" >/dev/null 2>&1 || true
    local i=0
    while [ $i -lt $(( secs / 2 )) ]; do
      sleep 2
      $ADB shell "input motionevent MOVE $BX $BY" >/dev/null 2>&1 || true
      i=$((i+1))
    done
    $ADB shell "input motionevent UP $BX $BY" >/dev/null 2>&1 || true ) &
  PAN_PID=$!
}

cmd_run(){
  local label="${1:?label}" pan="${2:-16}"
  local LOG="$EV/$label.log"
  wake; locked && die "DEVICE_LOCKED — needs owner unlock"
  log "run '$label': warp Geyser, pace.measure, ${pan}s no-input baseline + ${pan}s pan"
  $ADB shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.pace.measure 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  # RSCALE=<pct> forces a fixed low 3D render scale so the device HOLDS ~60fps
  # (k=1 constant) even while panning -> isolates present-pacing from render-bound
  # fps drops. Empty => neutral (GOAL manual scale).
  if [ -n "${RSCALE:-}" ]; then
    $ADB shell setprop debug.opengoal.render.scale "$RSCALE" >/dev/null 2>&1 || true
  else
    $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true
  fi
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  $ADB logcat -G 128M >/dev/null 2>&1 || true
  $ADB logcat -c >/dev/null 2>&1 || true
  : > "$LOG"
  ( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE 'PACE-EE|PACE-SWAP|GCAM-|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
  local LCP=$!
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  # wait for gameplay (Jak spawned + rendering) up to 180s
  local t0=$(date +%s) fm=0
  while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
    sleep 5
    fm=$(maxframe "$LOG"); fm=${fm:-0}
    [ "$fm" -ge 600 ] && { log "gameplay rendering (frame $fm)"; break; }
    if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then die "crash before gameplay"; fi
  done
  [ "$fm" -ge 300 ] || die "did not reach gameplay in 180s (maxframe=$fm)"
  log "== settle ${SETTLE:-10}s (level load/settle — discarded) =="
  sleep "${SETTLE:-10}"
  log "== NO-INPUT REST baseline (${pan}s; RSCALE=${RSCALE:-neutral}, expect ~60fps k=1) =="
  for i in 1 2 3; do $ADB shell log -t opengoal-gk "GCAM-BASELINE-BEGIN" >/dev/null 2>&1 || true; sleep 0.2; done
  sleep "$pan"
  log "== sustained RIGHT-STICK PAN (${pan}s) =="
  drive_pan "$pan"
  wait "${PAN_PID:-0}" 2>/dev/null || true
  sleep 1
  $ADB shell log -t opengoal-gk "GCAM-PAN-END" >/dev/null 2>&1 || true
  sleep 1
  kill ${LCP:-0} 2>/dev/null || true
  pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
  $ADB shell setprop debug.opengoal.pace.measure 0 >/dev/null 2>&1 || true
  echo "  captured -> $LOG (maxframe=$(maxframe "$LOG"), PACE-EE=$(grep -ac PACE-EE "$LOG"), PACE-SWAP=$(grep -ac PACE-SWAP "$LOG"))"
  echo "  focus=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')"
  cmd_parse "$LOG"
}

cmd_title(){
  # Obstacle-free camera-motion probe (owner tip f78470358: measure the pan where
  # collision can't confound it). The title/village1 ATTRACT FLYTHROUGH is a smooth
  # automated camera flying over open terrain at ~60fps (light => sleep-bound => the
  # EE-loop frame cap engages), so present-pacing evenness is isolated cleanly and
  # there is zero collision. Same present path (present == EE) as the gameplay camera.
  local label="${1:?label}" secs="${2:-20}"
  local LOG="$EV/$label.log"
  wake; locked && die "DEVICE_LOCKED — needs owner unlock"
  log "run '$label': title/village attract FLYTHROUGH (no warp, obstacle-free), ${secs}s"
  $ADB shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.pace.measure 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  $ADB logcat -G 128M >/dev/null 2>&1 || true
  $ADB logcat -c >/dev/null 2>&1 || true
  : > "$LOG"
  ( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE 'PACE-EE|PACE-SWAP|GCAM-|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
  local LCP=$!
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s) fm=0
  while [ $(( $(date +%s) - t0 )) -lt 200 ]; do
    sleep 5
    fm=$(maxframe "$LOG"); fm=${fm:-0}
    grep -aq 'link finish: logo' "$LOG" 2>/dev/null && [ "$fm" -ge 600 ] && { log "title flythrough live (frame $fm)"; break; }
    if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then die "crash before title"; fi
  done
  [ "$fm" -ge 400 ] || die "title did not come up in 200s (maxframe=$fm)"
  log "== settle ${SETTLE:-6}s (discarded) =="
  sleep "${SETTLE:-6}"
  log "== FLYTHROUGH capture (${secs}s, ~60fps, camera moving, obstacle-free) =="
  for i in 1 2 3; do $ADB shell log -t opengoal-gk "GCAM-BASELINE-BEGIN" >/dev/null 2>&1 || true; sleep 0.2; done
  sleep "$secs"
  $ADB shell log -t opengoal-gk "GCAM-PAN-END" >/dev/null 2>&1 || true
  sleep 1
  kill ${LCP:-0} 2>/dev/null || true
  pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
  $ADB shell setprop debug.opengoal.pace.measure 0 >/dev/null 2>&1 || true
  echo "  captured -> $LOG (maxframe=$(maxframe "$LOG"), PACE-EE=$(grep -ac PACE-EE "$LOG"), PACE-SWAP=$(grep -ac PACE-SWAP "$LOG"))"
  echo "  focus=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')"
  cmd_parse "$LOG"
}

cmd_parse(){
  local LOG="${1:?logfile}"
  python3 - "$LOG" <<'PY'
import sys, re, statistics as st
log=sys.argv[1]
ts=re.compile(r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)')
def t2s(t):
    import datetime; return datetime.datetime.strptime(t,"%m-%d %H:%M:%S.%f").timestamp()
ee=[]; sw=[]; phase='pre'
for line in open(log, errors='replace'):
    if 'GCAM-BASELINE-BEGIN' in line: phase='baseline'; continue
    if 'GCAM-PAN-BEGIN' in line: phase='pan'; continue
    if 'GCAM-PAN-END' in line: phase='post'; continue
    m=ts.match(line); t=t2s(m.group(1)) if m else None
    e=re.search(r'PACE-EE dt_ms=([-0-9.]+) k=([0-9]+) afc=([0-9-]+) bfc=([0-9-]+) cam=([-0-9.]+),([-0-9.]+),([-0-9.]+) yaw=([-0-9.]+) valid=([01])', line)
    if e:
        ee.append(dict(t=t,phase=phase,dt=float(e.group(1)),k=int(e.group(2)),afc=int(e.group(3)),bfc=int(e.group(4)),
                       cx=float(e.group(5)),cy=float(e.group(6)),cz=float(e.group(7)),yaw=float(e.group(8)),valid=int(e.group(9))))
        continue
    s=re.search(r'PACE-SWAP n=([0-9]+) dt_ms=([-0-9.]+)', line)
    if s: sw.append(dict(t=t,phase=phase,n=int(s.group(1)),dt=float(s.group(2))))
def stats(xs):
    xs=[x for x in xs if x is not None]
    if not xs: return None
    xs2=sorted(xs)
    return dict(n=len(xs),mean=st.mean(xs),sd=(st.pstdev(xs) if len(xs)>1 else 0),
                mn=min(xs),mx=max(xs),p50=xs2[len(xs2)//2],p95=xs2[int(len(xs2)*0.95)])
def pr(name,xs,unit='ms'):
    s=stats(xs)
    if not s: print(f"  {name}: (none)"); return
    print(f"  {name}: n={s['n']} mean={s['mean']:.3f}{unit} sd={s['sd']:.3f} min={s['mn']:.3f} p50={s['p50']:.3f} p95={s['p95']:.3f} max={s['mx']:.3f}")
print(f"=== analyze {log} ===")
print(f"  PACE-EE lines={len(ee)}  PACE-SWAP lines={len(sw)}")
for ph in ('baseline','pan','post'):
    E=[e for e in ee if e['phase']==ph]; S=[s for s in sw if s['phase']==ph]
    if not E and not S: continue
    print(f"\n-- phase={ph} --")
    # present pacing (the smoking gun): swap interval jitter
    pr("PACE-SWAP present dt", [s['dt'] for s in S])
    pr("PACE-EE   game-clock dt", [e['dt'] for e in E])
    # k dither
    if E:
        from collections import Counter
        kc=Counter(e['k'] for e in E)
        print(f"  time-ratio k histogram: {dict(sorted(kc.items()))}  (k>1 frac={sum(v for kk,v in kc.items() if kk>1)/len(E):.3f})")
    # camera game-STATE motion: per-frame delta of yaw + position (only where valid & afc advances by 1)
    Ev=[e for e in E if e['valid']==1]
    dyaw_frame=[]; dpos_frame=[]; dyaw_ms=[]
    for a,b in zip(Ev,Ev[1:]):
        dafc=b['afc']-a['afc']
        if dafc<=0 or dafc>4: continue
        dy=abs(b['yaw']-a['yaw'])
        if dy>180: dy=360-dy  # wrap
        dp=((b['cx']-a['cx'])**2+(b['cy']-a['cy'])**2+(b['cz']-a['cz'])**2)**0.5
        dyaw_frame.append(dy/dafc)   # per game-frame
        dpos_frame.append(dp/dafc)
        if b['dt'] and b['dt']>0: dyaw_ms.append(dy/b['dt'])  # per wall-clock ms
    pr("camera dyaw / GAME-frame", dyaw_frame, unit='deg')
    pr("camera dpos / GAME-frame", dpos_frame, unit='u')
    pr("camera dyaw / WALL-ms",   dyaw_ms, unit='deg/ms')
    # key ratios: if game-frame delta is CONSTANT (low sd/mean) but present dt or
    # wall-ms rate jitters, that's present-pacing judder.
    sfy=stats(dyaw_frame); swp=stats([s['dt'] for s in S])
    if sfy and sfy['mean']>1e-6:
        print(f"  >> camera dyaw/GAME-frame  CoV = {sfy['sd']/sfy['mean']:.3f}  (low => game-state SMOOTH)")
    if swp and swp['mean']>1e-6:
        print(f"  >> present dt CoV          = {swp['sd']/swp['mean']:.3f}  (high => PRESENT JITTER/judder)")
    if swp:
        jit=[abs(s['dt']-swp['mean']) for s in S]
        over2=sum(1 for j in jit if j>2.0)/len(jit) if jit else 0
        print(f"  >> present frames with |dt-mean|>2ms = {over2*100:.1f}%")
PY
}

case "${1:-}" in
  run)   shift; cmd_run "$@" ;;
  title) shift; cmd_title "$@" ;;
  parse) shift; cmd_parse "$@" ;;
  *) echo "usage: $0 {run <label> <pan_secs> | title <label> <secs> | parse <log>}";;
esac
