#!/usr/bin/env bash
# gdfix_run.sh — Gdynamic-fix device verification (eae4df44), real Adreno hardware.
# libgk is UNCHANGED (pure GOAL fix -> ENGINE.CGO/GAME.CGO); deploy_verify already PASSES.
# We push the fresh CONSISTENT arm64 28-CGO/DGO set (with the new dynamic-render-scale-update)
# into files/iso_data/jak1 (sha-verified), then run cfg-driven scenarios and capture [dyn-rs].
#
# Subcommands:
#   push                   sha-verified push of out/jak1-arm64-full/iso/*.{CGO,DGO} -> device
#   cfg <on|off> <tgt> <floor>   write device pc-settings (dynamic?/dyn-target-fps/min-render-scale)
#   run <label> <secs>     warp to Geyser Rock, launch, capture <secs> of [dyn-rs] logcat, parse
#   parse <logfile>        re-parse a captured log
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Gdynamic-fix; EV="$OUT/evidence"; mkdir -p "$EV"
SETDIR="files/.config/OpenGOAL/jak1/settings"; SETFILE="$SETDIR/pc-settings.gc"
VERHEX="1000A00040000"
SRC=out/jak1-arm64-full/iso
die(){ echo "[gdfix FAIL] $*" >&2; exit 1; }
log(){ echo "[gdfix] $*"; }
locked(){ $ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
wake(){ $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; }

cmd_push(){
  wake; locked && die "DEVICE_LOCKED — needs owner unlock"
  local n; n=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l)
  [ "$n" -eq 28 ] || die "expected 28 CGO/DGO in $SRC, got $n (run build_arm64_full_consistent.sh)"
  $ADB shell run-as "$PKG" sh -c 'ls files/iso_data/jak1/KERNEL.CGO >/dev/null 2>&1' \
    || die "iso_data not extracted on device — full-bundle install needed"
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  local fail=0 cnt=0 f bn want got
  for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
    bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
    $ADB push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
    $ADB shell run-as "$PKG" cp "/data/local/tmp/$bn" "files/iso_data/jak1/$bn" || { echo "  CP-FAIL $bn"; fail=1; }
    $ADB shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
    got=$($ADB shell run-as "$PKG" sha256sum "files/iso_data/jak1/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
    [ "$want" = "$got" ] && cnt=$((cnt+1)) || { echo "  VERIFY-FAIL $bn want=$want got=$got"; fail=1; }
  done
  [ "$fail" -eq 0 ] || die "consistent CGO push failed ($cnt/28 verified)"
  log "pushed + sha256-verified $cnt/28 consistent arm64 CGO/DGO into files/iso_data/jak1"
  bash .autoport/lib/deploy_verify.sh eae4df44 || die "deploy_verify FAILED"
  log "PUSH OK — fresh Gdynamic-fix CGOs live; libgk verified"
}

cmd_cfg(){
  local mode="${1:?on|off}" tgt="${2:?target}" floor="${3:?floor}"
  local dyn='#f'; [ "$mode" = on ] && dyn='#t'
  log "cfg dynamic=$dyn dyn-target-fps=$tgt min-render-scale=$floor -> $SETFILE"
  $ADB shell run-as "$PKG" mkdir -p "$SETDIR" || die "mkdir settings dir failed (CE-locked?)"
  local TMP; TMP=$(mktemp)
  {
    printf '(settings #x%s\n' "$VERHEX"
    printf '  (render-scale 55.0)\n'
    printf '  (min-render-scale %s.0)\n' "${floor%.*}"
    printf '  (dynamic-render-scale? %s)\n' "$dyn"
    printf '  (dyn-target-fps %s.0)\n' "${tgt%.*}"
    printf '  )\n'
  } > "$TMP"
  $ADB push "$TMP" /data/local/tmp/pc-settings.gc >/dev/null 2>&1 || die "push settings failed"
  $ADB shell run-as "$PKG" cp /data/local/tmp/pc-settings.gc "$SETFILE" || die "cp settings failed"
  $ADB shell rm -f /data/local/tmp/pc-settings.gc >/dev/null 2>&1 || true; rm -f "$TMP"
  echo "  --- device settings now ---"
  $ADB shell run-as "$PKG" cat "$SETFILE" 2>/dev/null | sed 's/^/    /'
}

maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

cmd_run(){
  local label="${1:?label}" secs="${2:-60}"
  local LOG="$EV/$label.log"
  wake; locked && die "DEVICE_LOCKED"
  log "run '$label' for ${secs}s (warp Geyser, dynamic controller trace)"
  $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  $ADB logcat -G 64M >/dev/null 2>&1 || true
  $ADB logcat -c >/dev/null 2>&1 || true
  : > "$LOG"
  ( $ADB logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE '\[dyn-rs\]|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
  local LCP=$!
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s) heavy=0 light=0
  while [ $(( $(date +%s) - t0 )) -lt "$secs" ]; do
    sleep 4
    local el=$(( $(date +%s) - t0 ))
    # MIDLOAD=<pct>: at 1/3 supersample the 3D FBO (heavy GPU) so fps drops under target ->
    # the controller DESCENDS toward the floor; at 2/3 clear it -> fps recovers -> the
    # controller CLIMBS back up (the owner's not-stuck-at-floor fix, on real hardware).
    if [ -n "${MIDLOAD:-}" ] && [ "$heavy" = 0 ] && [ "$el" -ge $(( secs/3 )) ]; then
      $ADB shell setprop debug.opengoal.render.scale "$MIDLOAD" >/dev/null 2>&1 || true
      echo "  -- MIDLOAD: render.scale=$MIDLOAD (heavy GPU phase @${el}s) --"; heavy=1
    fi
    if [ -n "${MIDLOAD:-}" ] && [ "$light" = 0 ] && [ "$el" -ge $(( 2*secs/3 )) ]; then
      $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true
      echo "  -- MIDLOAD cleared: render.scale=neutral (light phase @${el}s -> expect CLIMB) --"; light=1
    fi
    if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null; then echo "  !! crash signal seen"; break; fi
  done
  [ -n "${MIDLOAD:-}" ] && { $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true; }
  kill ${LCP:-0} 2>/dev/null || true
  pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
  echo "  captured -> $LOG  (maxframe=$(maxframe "$LOG"), [dyn-rs] lines=$(grep -ac '\[dyn-rs\]' "$LOG"))"
  echo "  focus=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')"
  cmd_parse "$LOG"
}

cmd_parse(){
  local LOG="${1:?logfile}"
  python3 - "$LOG" <<'PY'
import sys, re, datetime
log=sys.argv[1]
ts_re=re.compile(r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)')
def t2s(t):
    return datetime.datetime.strptime(t,"%m-%d %H:%M:%S.%f").timestamp()
state=[]; lower=[]; raise_=[]; reclamp=[]
for line in open(log, errors='replace'):
    if '[dyn-rs]' not in line: continue
    m=ts_re.match(line); t=t2s(m.group(1)) if m else None
    if 'state fps=' in line:
        d=dict(re.findall(r'(fps|busy|budget|scale|target|floor)=([0-9.]+)', line)); d['t']=t; state.append(d)
    elif 'LOWER to' in line: lower.append((t,line.strip()))
    elif 'RAISE' in line:
        sc=re.search(r'to ([0-9.]+)%', line); fp=re.search(r'fps ([0-9.]+)', line)
        raise_.append((t, float(sc.group(1)) if sc else None, float(fp.group(1)) if fp else None, line.strip()))
    elif 'RE-CLAMP' in line: reclamp.append((t,line.strip()))
print(f"=== parse {log} ===")
print(f"  state samples={len(state)}  LOWER={len(lower)}  RAISE={len(raise_)}  RE-CLAMP={len(reclamp)}")
if state:
    sc=[float(s['scale']) for s in state if 'scale' in s]; fp=[float(s['fps']) for s in state if 'fps' in s]
    bu=[float(s['busy']) for s in state if 'busy' in s]
    tg=state[-1].get('target'); fl=state[-1].get('floor'); bd=state[-1].get('budget')
    print(f"  target={tg} floor={fl} budget={bd}ms")
    if sc: print(f"  scale: first={sc[0]:.0f}% min={min(sc):.0f}% max={max(sc):.0f}% final={sc[-1]:.0f}%")
    if fp: print(f"  fps:   min={min(fp):.1f} max={max(fp):.1f} final={fp[-1]:.1f}")
    if bu: print(f"  busy:  min={min(bu):.1f}ms max={max(bu):.1f}ms final={bu[-1]:.1f}ms")
    if fl and sc: print(f"  FLOOR respected (min {min(sc):.0f}% >= floor {float(fl):.0f}%): {min(sc) >= float(fl)-0.5}")
    if bu and bd:
        b=float(bd); busy=bu[-1]
        print(f"  OLD busy-gate at this target: 0.8*budget={0.8*b:.1f}ms vs busy={busy:.1f}ms -> old raise {'OPEN' if busy<=0.8*b else 'CLOSED (old code STUCK here)'}")
for e in reclamp: print("  "+e[1])
for r in raise_[:8]: print(f"  RAISE -> {r[3]}")
adj=sorted([x[0] for x in lower]+[x[0] for x in raise_]); adj=[a for a in adj if a]
if len(adj)>=2:
    g=[adj[i+1]-adj[i] for i in range(len(adj)-1)]
    print(f"  cadence: {len(adj)} changes, min gap={min(g):.2f}s mean={sum(g)/len(g):.2f}s (>=~0.5s = no per-frame thrash)")
PY
  echo "  crash sigs: $(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null)"
}

case "${1:-}" in
  push)  cmd_push ;;
  cfg)   shift; cmd_cfg "$@" ;;
  run)   shift; cmd_run "$@" ;;
  parse) shift; cmd_parse "$@" ;;
  *) echo "usage: $0 {push | cfg <on|off> <tgt> <floor> | run <label> <secs> | parse <log>}";;
esac
