#!/usr/bin/env bash
# gdynrs_run.sh — Gdynamic-renderscale device verification (eae4df44).
#
# Proves the ATTEMPT-2 fix: the adaptive render-scale controller RAISES the scale
# back up on FRAME-TIME headroom (pc-get-frame-busy-us vs the 1000/target vblank
# budget) even at a VSYNC-CAPPED target (target=60, fps pinned ~60, never exceeds
# it) — the case the owner reported stuck at the floor in attempt 1.
#
# Subcommands:
#   deploy                 full CONSISTENT arm64 build (libgk + 28 CGO/DGO) + install + push + deploy_verify
#   cfg <on|off> <tgt> <floor>   write the device pc-settings (dynamic?/dyn-target-fps/min-render-scale)
#   run <label> <secs>     warp to Geyser, launch, capture <secs> of [dyn-rs] logcat -> evidence/<label>.log, parse
#   parse <logfile>        re-parse a captured log
#
# Device serial eae4df44 ONLY. Real measurements only. UI native (Grender-split unchanged).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Gdynamic-renderscale; EV="$OUT/evidence"; mkdir -p "$EV"
SETDIR="/storage/emulated/0/OpenGOAL/jak1"
SETFILE="$SETDIR/settings.ini"
VERHEX="1000A00040000"   # (static-pckernel-version 1 10 4 0): major<<48|minor<<32|rev<<16|build
die(){ echo "[gdynrs FAIL] $*" >&2; exit 1; }
log(){ echo "[gdynrs] $*"; }

locked(){ $ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
wake(){ $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; }

cmd_deploy(){
  wake; locked && die "DEVICE_LOCKED — needs owner unlock"
  if [ "${SKIP_BUILD:-0}" != 1 ]; then
    log "1/6 build libgk (arm64, includes kmachine + android_gfx + gk_android_main changes)"
    bash .autoport/lib/d3_build.sh || die "libgk build failed"
    log "2/6 build SLIM jak1 debug APK (consistent DGOs pushed separately below)"
    ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 6 ) || die "gradle failed"
    APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
    [ -f "$APK" ] || die "no APK at $APK"
    log "3/6 install libgk APK"
    $ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
    $ADB shell pm trim-caches 999G 2>/dev/null || true
    $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
    STAGE=/data/local/tmp/$(basename "$APK")
    $ADB push "$APK" "$STAGE" >/dev/null 2>&1 || die "apk push failed"
    $ADB shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gdynrs-pm.out 2>&1 \
      || { cat /tmp/gdynrs-pm.out; die "pm install failed"; }
    grep -q Success /tmp/gdynrs-pm.out || { cat /tmp/gdynrs-pm.out; die "pm install no Success"; }
    $ADB shell rm -f "$STAGE" >/dev/null 2>&1 || true
    log "4/6 build CONSISTENT arm64 28 CGO/DGO from current source (several minutes)"
    bash .autoport/build_arm64_full_consistent.sh || die "consistent arm64 build failed"
  else
    log "SKIP_BUILD=1 — reusing existing libgk/APK + staged out/jak1-arm64-full/iso"
  fi
  log "5/6 push 28 consistent CGO/DGO into files/cgo/jak1 (sha256-verified, inline)"
  local SRC=out/jak1-arm64-full/iso
  local n; n=$(ls "$SRC"/*.CGO "$SRC"/*.DGO 2>/dev/null | wc -l)
  [ "$n" -eq 28 ] || die "expected 28 CGO/DGO in $SRC, got $n"
  # accept EITHER extraction marker (the app's marker name changed across versions) or
  # an already-populated iso_data dir — the data must persist (no re-extract overwrite).
  $ADB shell run-as "$PKG" sh -c \
    'ls files/cgo/jak1/.extracted_v1 >/dev/null 2>&1 || ls files/.asset_bundle_stamp >/dev/null 2>&1 || ls files/cgo/jak1/KERNEL.CGO >/dev/null 2>&1' \
    || die "iso_data not extracted on device — a full-bundle install is needed"
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  local fail=0 cnt=0 f bn want got
  for f in "$SRC"/*.CGO "$SRC"/*.DGO; do
    bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
    $ADB push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1 || { echo "  PUSH-FAIL $bn"; fail=1; continue; }
    $ADB shell run-as "$PKG" cp "/data/local/tmp/$bn" "files/cgo/jak1/$bn" || { echo "  CP-FAIL $bn"; fail=1; }
    $ADB shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1 || true
    got=$($ADB shell run-as "$PKG" sha256sum "files/cgo/jak1/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
    [ "$want" = "$got" ] && cnt=$((cnt+1)) || { echo "  VERIFY-FAIL $bn want=$want got=$got"; fail=1; }
  done
  [ "$fail" -eq 0 ] || die "consistent CGO push failed ($cnt/28 verified)"
  echo "  pushed + sha256-verified $cnt/28 consistent CGO/DGO into files/cgo/jak1"
  log "6/6 deploy_verify (build==APK==device libgk)"
  bash .autoport/lib/deploy_verify.sh eae4df44 || die "deploy_verify FAILED"
  log "DEPLOY OK — consistent HEAD build live on device"
}

cmd_recover(){
  # FULL-APK recovery+deploy: the slim APK's stale v2 manifest tripped the loader's
  # version-mismatch WIPE of iso_data+fr3 (it has no zip to re-extract). Rebuild the
  # FULL bundle (build_asset_bundle.sh: 293 data + my arm64 CGOs + 26 fr3, version 3),
  # build+install the FULL APK, and let the loader cleanly extract my consistent build.
  wake; locked && die "DEVICE_LOCKED — needs owner unlock"
  [ "$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)" -eq 28 ] || die "no 28 arm64 CGO/DGO staged"
  log "R1 ensure libgk current (no-op if built)"
  bash .autoport/lib/d3_build.sh || die "libgk build failed"
  log "R2 build FULL jak1 debug APK (bundleJak1Assets packs 293 data + arm64 CGOs + 26 fr3 -> zip; several min)"
  # force a fresh bundle so it ships MY arm64 CGOs (the stale attempt-1 zip is deleted)
  rm -f android/app/src/jak1/assets-bundled/bundle/jak1_assets.zip \
        android/app/src/jak1/assets-bundled/bundle/manifest.properties
  ( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -n 12 ) || die "gradle full assemble failed"
  grep -qE '^version=' android/app/src/jak1/assets-bundled/bundle/manifest.properties 2>/dev/null \
    || die "bundle manifest not regenerated"
  APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  [ -f "$APK" ] || die "no APK at $APK"
  echo "  APK size: $(du -h "$APK" | cut -f1) (full bundle should be ~1.1G)"
  log "R3 install FULL APK (-r over slim)"
  $ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  $ADB shell pm trim-caches 999G 2>/dev/null || true
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  STAGE=/data/local/tmp/$(basename "$APK")
  $ADB push "$APK" "$STAGE" >/dev/null 2>&1 || die "apk push failed"
  $ADB shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gdynrs-pm.out 2>&1 \
    || { cat /tmp/gdynrs-pm.out; die "pm install failed (MIUI dialog? check device)"; }
  grep -q Success /tmp/gdynrs-pm.out || { cat /tmp/gdynrs-pm.out; die "pm install no Success"; }
  $ADB shell rm -f "$STAGE" >/dev/null 2>&1 || true
  log "R4 launch loader -> clean extract of the full bundle (watch for 'decompressed' / boot)"
  $ADB logcat -c >/dev/null 2>&1 || true
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
    sleep 5
    if $ADB logcat -d 2>/dev/null | grep -aqE 'asset bundle decompressed|asset bundle already unpacked'; then ok=1; fi
    local fm; fm=$($ADB logcat -d 2>/dev/null | grep -aoE 'A35-RENDER frame=[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -1); fm=${fm:-0}
    [ "$fm" -ge 300 ] && { ok=2; echo "  loader extracted + game rendering (frame $fm)"; break; }
    if $ADB logcat -d 2>/dev/null | grep -aqE 'FileNotFoundException|asset setup failed'; then die "loader still failing (asset setup failed) — check logcat"; fi
  done
  [ "$ok" -ge 1 ] || die "loader did not extract/boot in 240s"
  log "R5 verify device iso_data/jak1 = my arm64 build (KERNEL.CGO sha)"
  local want got
  want=$(sha256sum out/jak1-arm64-full/iso/KERNEL.CGO | awk '{print $1}')
  got=$($ADB shell run-as "$PKG" sha256sum files/cgo/jak1/KERNEL.CGO 2>/dev/null | awk '{print $1}' | tr -d '\r')
  [ "$want" = "$got" ] && echo "  KERNEL.CGO matches arm64 build ($got)" || die "KERNEL.CGO mismatch (want $want got $got) — bundle shipped wrong backend"
  log "R6 deploy_verify (build==APK==device libgk)"
  bash .autoport/lib/deploy_verify.sh eae4df44 || die "deploy_verify FAILED"
  log "RECOVER OK — full consistent HEAD bundle extracted + libgk verified"
}

cmd_cfg(){
  local mode="${1:?on|off}" tgt="${2:?target}" floor="${3:?floor}"
  local dyn='#f'; [ "$mode" = on ] && dyn='#t'
  log "cfg dynamic=$dyn dyn-target-fps=$tgt min-render-scale=$floor -> device $SETFILE"
  $ADB shell mkdir -p "$SETDIR" || die "mkdir settings dir failed"
  # craft a minimal but version-correct settings.ini (reader checks the version line,
  # then reads only the keys present; everything else keeps android surface defaults).
  local TMP; TMP=$(mktemp)
  {
    printf '[settings]\n'
    printf 'version = #x%s\n' "$VERHEX"
    printf 'render-scale = 100.0\n'
    printf 'min-render-scale = %s.0\n' "${floor%.*}"
    printf 'dynamic-render-scale? = %s\n' "$dyn"
    printf 'dyn-target-fps = %s.0\n' "${tgt%.*}"
  } > "$TMP"
  $ADB push "$TMP" "$SETFILE" >/dev/null 2>&1 || die "push settings failed"
  rm -f "$TMP"
  echo "  --- device settings now ---"
  $ADB shell cat "$SETFILE" 2>/dev/null | sed 's/^/    /'
}

maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

cmd_run(){
  local label="${1:?label}" secs="${2:-50}"
  local LOG="$EV/$label.log"
  wake; locked && die "DEVICE_LOCKED"
  log "run '$label' for ${secs}s (warp Geyser, dynamic controller trace)"
  # neutral C++ render_scale_pct (GOAL controller is the sole scale driver); warp to Geyser.
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
  local t0=$(date +%s) dropped=0
  while [ $(( $(date +%s) - t0 )) -lt "$secs" ]; do
    sleep 4
    # MIDDROP=<pct>: at half-time, shrink the neutral C++ render_scale_pct to create a
    # deterministic LIGHT phase (FBO smaller -> render-work drops -> the GOAL controller
    # sees frame-time headroom and should CLIMB its scale back toward 100% at the cap).
    if [ -n "${MIDDROP:-}" ] && [ "$dropped" = 0 ] && [ $(( $(date +%s) - t0 )) -ge $(( secs / 2 )) ]; then
      $ADB shell setprop debug.opengoal.render.scale "$MIDDROP" >/dev/null 2>&1 || true
      echo "  -- MIDDROP: set debug.opengoal.render.scale=$MIDDROP (light phase begins) --"
      dropped=1
    fi
    if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null; then
      echo "  !! crash signal seen"; break
    fi
  done
  [ -n "${MIDDROP:-}" ] && { $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true; }
  kill ${LCP:-0} 2>/dev/null || true
  pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true
  echo "  captured -> $LOG  (maxframe=$(maxframe "$LOG"), [dyn-rs] lines=$(grep -ac '\[dyn-rs\]' "$LOG"))"
  echo "  focus=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')"
  cmd_parse "$LOG"
}

cmd_parse(){
  local LOG="${1:?logfile}"
  python3 - "$LOG" <<'PY'
import sys, re
log=sys.argv[1]
ts_re=re.compile(r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)')
def t2s(t):
    import datetime
    return datetime.datetime.strptime(t,"%m-%d %H:%M:%S.%f").timestamp()
state=[]; lower=[]; raise_=[]; firstt=None
for line in open(log, errors='replace'):
    if '[dyn-rs]' not in line: continue
    m=ts_re.match(line); t=t2s(m.group(1)) if m else None
    if 'state fps=' in line:
        d=dict(re.findall(r'(fps|busy|budget|scale|target|floor)=([0-9.]+)', line))
        if d: d['t']=t; state.append(d)
    elif 'LOWER to' in line:
        lower.append((t,line.strip()))
    elif 'RAISE' in line:
        sc=re.search(r'RAISE\(probe\) to ([0-9.]+)', line)
        fp=re.search(r'fps ([0-9.]+)', line)
        raise_.append((t, float(sc.group(1)) if sc else None, float(fp.group(1)) if fp else None, line.strip()))
print(f"=== parse {log} ===")
print(f"  [dyn-rs] state samples: {len(state)}   LOWER events: {len(lower)}   RAISE(probe) events: {len(raise_)}")
if state:
    sc=[float(s['scale']) for s in state if 'scale' in s]
    fp=[float(s['fps']) for s in state if 'fps' in s]
    bu=[float(s['busy']) for s in state if 'busy' in s]
    tg=state[-1].get('target'); fl=state[-1].get('floor'); bd=state[-1].get('budget')
    print(f"  target={tg} floor={fl} budget={bd}ms")
    if sc: print(f"  scale: first={sc[0]:.0f}% min={min(sc):.0f}% max={max(sc):.0f}% final={sc[-1]:.0f}%")
    if fp: print(f"  fps:   min={min(fp):.1f} max={max(fp):.1f} final={fp[-1]:.1f}")
    if bu: print(f"  busy:  min={min(bu):.1f}ms max={max(bu):.1f}ms final={bu[-1]:.1f}ms")
    if fl and sc: print(f"  FLOOR respected (min scale {min(sc):.0f}% >= floor {float(fl):.0f}%): {min(sc) >= float(fl)-0.5}")
# raise-at-cap proof: any RAISE that fired while fps <= target (refutes 'only raise when fps>target')
if raise_ and state:
    tgt=float(state[-1].get('target',60))
    capraise=[r for r in raise_ if r[2] is not None and r[2] <= tgt+0.6]
    print(f"  RAISE-on-headroom-at/under-target events (fps<=target, the FIX): {len(capraise)} / {len(raise_)}")
    for r in raise_[:6]:
        print(f"     RAISE -> {r[1]}% at fps={r[2]}")
# anti-thrash cadence: min gap between consecutive adjustments
adj=sorted([t for t,_ in lower]+[t for t,_,_,_ in raise_])
adj=[a for a in adj if a is not None]
if len(adj)>=2:
    gaps=[adj[i+1]-adj[i] for i in range(len(adj)-1)]
    print(f"  adjustment cadence: {len(adj)} changes, min gap={min(gaps):.2f}s mean gap={sum(gaps)/len(gaps):.2f}s (>=~0.5s = no per-frame thrash)")
# crash scan
import subprocess
PY
  echo "  crash sigs in log: $(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null)"
}

case "${1:-}" in
  deploy)  cmd_deploy ;;
  recover) cmd_recover ;;
  cfg)    shift; cmd_cfg "$@" ;;
  run)    shift; cmd_run "$@" ;;
  parse)  shift; cmd_parse "$@" ;;
  *) echo "usage: $0 {deploy | cfg <on|off> <tgt> <floor> | run <label> <secs> | parse <log>}";;
esac
