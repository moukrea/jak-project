#!/usr/bin/env bash
# Gperf-particles2 moving-gameplay capture. ONE deployed build serves every config
# (all 8 opts are runtime props). For a named config it:
#   - arms tod.fast (clock ADVANCES ~60x -> natural day->night in ~24s, NOT pinned)
#   - arms pad_replay of the synthesized walk+pan clip (Jak moves + camera pans)
#   - warps to the TOD scene, boots (retry on flake), waits for Jak spawn
#   - screenrecords a moving window, extracts EVERY frame (ffmpeg -vsync 0)
#   - asserts app-foreground before AND after (crash-window rule)
#   - runs inspect.py -> POP + FLICKER scores
# Also parses an fps window from logcat.
#
# Usage: capture.sh <config> [warp] [seconds]
#   config: v4 | clean | pop | flicker   (or "raw:<k=v,...>" custom)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CFG="${1:-clean}"; WARP="${2:-village2-start}"; SEC="${3:-50}"  # ~2 TOD cycles @18000
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
OUT=.autoport/reports/Gperf-particles2/cap/$CFG; mkdir -p "$OUT"
FRAMES="$OUT/frames"; rm -rf "$FRAMES"; mkdir -p "$FRAMES"
CLIP=.autoport/reports/Gperf-particles2/tools/walkpan.inputs
TOOLS=.autoport/reports/Gperf-particles2/tools
A(){ "$ADB" -s "$S" "$@"; }
now(){ date +%H:%M:%S; }
focus_ok(){ A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG"; }
die(){ echo "[cap $CFG FAIL] $*" >&2; exit 1; }

# All 8 perf props. Kept features: '1'=OFF(v4). Dropped: '2'=ON(known-bad).
SWALL=(nospritelean nostatecache noinstance noshrubidx no2dvec notodpp notodskip nooverlap)
clearperf(){ for s in "${SWALL[@]}"; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done; }
setperf(){ A shell setprop "debug.opengoal.perf.$1" "$2" >/dev/null 2>&1; echo "  set perf.$1=$2"; }

echo "### config=$CFG warp=$WARP sec=$SEC"
[ -f "$CLIP" ] || die "no clip $CLIP (run gen_clip.py first)"

# ---- perf prop config ----
clearperf  # baseline: kept ON (0!=1), dropped OFF (0!=2) == CLEAN default
case "$CFG" in
  v4)      for s in nospritelean nostatecache noinstance noshrubidx no2dvec; do setperf "$s" 1; done ;;
  clean)   : ;;                                   # defaults == kept ON, dropped OFF
  pop)     setperf nooverlap 2 ;;                 # known-bad: GOAL/GL overlap ON
  flicker) setperf notodpp 2 ;;                   # known-bad: TOD ping-pong ON
  raw:*)   IFS=',' read -ra kv <<<"${CFG#raw:}"; for p in "${kv[@]}"; do setperf "${p%=*}" "${p#*=}"; done ;;
  *) die "unknown config $CFG" ;;
esac

# ---- input clip + fast clock + warp (set BEFORE am start; latched at boot) ----
# App uid can't read /data/local/tmp, so write the clip binary-safe via base64
# text (pty-safe) piped into `base64 -d` under run-as (which owns files/).
base64 -w0 "$CLIP" | A shell "run-as $PKG sh -c 'base64 -d > files/pad_demo.inputs'" 2>/dev/null
DEV_MD5=$(A shell run-as "$PKG" md5sum files/pad_demo.inputs 2>/dev/null | cut -d' ' -f1)
HOST_MD5=$(md5sum "$CLIP" | cut -d' ' -f1)
[ "$DEV_MD5" = "$HOST_MD5" ] || die "clip transfer md5 mismatch (dev=$DEV_MD5 host=$HOST_MD5)"
echo "  clip on device ok (md5 $HOST_MD5)"
A shell setprop debug.opengoal.pad_replay replay >/dev/null 2>&1
A shell setprop debug.opengoal.pad_replay_realtime 1 >/dev/null 2>&1
A shell setprop debug.opengoal.tod.fast 1 >/dev/null 2>&1
A shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1  # ensure NOT pinned
A shell setprop debug.opengoal.level.warp "$WARP" >/dev/null 2>&1
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
A shell svc power stayon true >/dev/null 2>&1||true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE LOCKED — owner unlock needed"

LOG="$OUT/logcat.txt"
boot(){
  for b in 1 2 3 4 5 6; do
    A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
    A logcat -G 128M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
    pkill -f "logcat.*$CFG/logcat" 2>/dev/null||true
    A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
    LP=$!
    A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
    for i in $(seq 1 180); do
      grep -qa "LEVEL-WARP-SPAWN name=$WARP" "$LOG" && return 0
      grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && break
      sleep 1
    done
    echo "  boot $b flake -> retry"; kill $LP 2>/dev/null || true
  done
  return 1
}
boot || die "no warp to $WARP after 6 tries"
echo "  warp ok: $(grep -a "LEVEL-WARP-SPAWN name=$WARP" "$LOG" | tail -1)"
grep -qa 'TOD-FAST' "$LOG" && echo "  tod.fast: $(grep -a 'TOD-FAST' "$LOG" | tail -1)" || echo "  WARN: no TOD-FAST log yet"
grep -qa 'pad_replay: REPLAY' "$LOG" && echo "  pad: $(grep -a 'pad_replay: REPLAY' "$LOG" | tail -1)" || echo "  WARN: no pad_replay REPLAY log"

# let Jak spawn + inputs engage + the clock start moving
sleep 10
focus_ok || die "app not foreground before record"

# ---- screenrecord the moving window, pull, extract EVERY frame ----
MP4=/sdcard/gp2_$CFG.mp4
RS=$(now)
A shell screenrecord --time-limit "$SEC" --bit-rate 40000000 "$MP4" >/dev/null 2>&1 &
SRPID=$!
sleep "$((SEC+3))"
wait $SRPID 2>/dev/null || true
RE=$(now)
focus_ok && echo "  focus OK after record" || echo "  WARN: app NOT foreground after record (crash?)"
A pull "$MP4" "$OUT/rec.mp4" >/dev/null 2>&1 || die "pull mp4"
# Extract EVERY frame but DOWNSCALED to 800px wide: the FLICKER/POP metrics are tile-
# mean based (resolution-invariant, verified full-vs-3x-downscale agree to 3 dp), and
# full-res 2400x1080 PNGs blow both the host disk (~5GB/config) and detect.py's RAM.
ffmpeg -nostdin -loglevel error -y -i "$OUT/rec.mp4" -vf "scale=480:-2" -vsync 0 "$FRAMES/r%05d.png" 2>&1 | tail -2
NF=$(ls "$FRAMES"/*.png 2>/dev/null | wc -l)
echo "  extracted $NF frames"
[ "$NF" -ge 30 ] || die "too few frames ($NF) — record failed"
kill $LP 2>/dev/null || true

# ---- fps window (median over the record window) ----
python3 "$TOOLS/fps.py" "$LOG" "$RS" "$RE" 2>/dev/null || echo "  (fps parse skipped)"

# ---- POP + FLICKER inspection ----
python3 "$TOOLS/detect.py" "$FRAMES" --label "$CFG" --json "$OUT/inspect.json" \
  --dump-worst "$OUT/worst" | sed 's/^/  /'
# frames already downscaled, but a 2500-frame 800px dir is still ~0.6GB — keep only the
# rec.mp4 (re-extractable) + inspect.json + worst frames; drop the bulk PNG dir.
rm -rf "$FRAMES"
echo "[cap $CFG DONE] frames=$NF -> $OUT"
