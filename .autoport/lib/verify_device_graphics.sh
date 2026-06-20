#!/usr/bin/env bash
# verify_device_graphics.sh — OBJECTIVE oracle-vs-device graphics gate for the
# jak1 Android port. For WHATEVER build is currently on the device eae4df44, it:
#
#   1. force-stops + launches org.opengoal.gk.jak1, verifies foreground=jak1
#   2. drives it through the canonical beats via cpad_inject input injection:
#        title-pressstart -> main-menu (START) -> newgame-cinematic (NEW GAME)
#        -> ingame-firstframe
#   3. screencaps the device frame at each beat (only when fg==jak1)
#   4. runs frame_compare.py of each device frame vs .autoport/gold/oracle-beats
#      /<beat>.png (or pristine-frames-2400 fallback), MASKING the touch overlay
#      via --ignore-rect (dpad left, face buttons right, START center-bottom)
#   5. detects the HALO numerically: bright-blob area on device absent in oracle
#   6. writes .autoport/reports/graphics-verify/report.json (per-beat verdict)
#
# DOES NOT rebuild/redeploy/edit anything — verifies the CURRENT build only.
# Device must remain usable after a failed launch. Real measurements only.
#
# Device serial eae4df44 ONLY (shared device). Verifies fg==jak1 before trusting
# any frame. grep -a on logcat. pgrep leftover runners before starting.
#
# Usage: bash .autoport/lib/verify_device_graphics.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SERIAL="eae4df44"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PKG/files/cpad_inject"
PY="$HOME/.venv/autoport/bin/python"
FC=".autoport/lib/frame_compare.py"

ORACLE=".autoport/gold/oracle-beats"
# intro-logo gates the HALO at the ndi (Naughty-Dog-logo-on-BLACK) beat — the
# beat where the village+sun-glow halo actually appears (per the Gndlogo phase).
# The spinning blue-starburst "JAK AND DAXTER" title card DELIBERATELY renders
# the village+sun (the flythrough of Sandover), so it is the WRONG beat for a
# brightness-halo gate. NDI_ORACLE = the matched-phase ND-logo-on-black frame
# captured from the UNTOUCHED upstream v0.3.3 original (c4bc4d3ff).
NDI_ORACLE=".autoport/gold/pristine-frames-2400/intro-ndlogo-full.png"
FALLBACK=".autoport/gold/TRUE-original-v033"
OUT=".autoport/reports/graphics-verify"
SHOTS="$OUT/device-shots"
LOG="$OUT/routed-logcat.log"
REPORT="$OUT/report.json"

# pixel-gate params (cross-renderer GLES-vs-GL floor; per MEMORY: detailed beats
# ~2.2% at thr24, use thr56/tol2% for matched-phase).
THRESHOLD="${THRESHOLD:-56}"; TOLERANCE="${TOLERANCE:-0.02}"
# halo/bloom gate: a beat whose halo_excess_frac (device-bright region absent in
# the oracle) exceeds this FAILS the gate. Clean device ~0.002, ND-logo halo ~0.28.
HALO_GATE="${HALO_GATE:-0.02}"

die() { echo "verify_device_graphics: FATAL: $*" >&2; exit 2; }
[ -x "$ADB" ] || command -v "$ADB" >/dev/null 2>&1 || die "adb not found at $ADB"
mkdir -p "$SHOTS"

export ANDROID_SERIAL="$SERIAL"

# refuse wrong device
state="$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)"
[ "$state" = "device" ] || die "device $SERIAL not in 'device' state (got '${state:-none}')"

# kill any leftover run scripts (their trailing force-stop kills our run)
for pat in 'Gd1_run' 'gcine_audit' 'e1_run' 'jak1_first_level_drive' 'capture_device_beat'; do
  for p in $(pgrep -f "$pat" 2>/dev/null || true); do
    [ "$p" = "$$" ] && continue
    echo "  killing leftover runner pid=$p ($pat)"; kill "$p" 2>/dev/null || true
  done
done

adb() { "$ADB" -s "$SERIAL" "$@"; }
read_focus() { adb shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
is_fg() { case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clear_inject() { inject ""; }
cur_render_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }
snap() {  # beat -> device-shots/<beat>.png ; only if fg==jak1
  local beat="$1"; local o="$SHOTS/$beat.png"
  if ! is_fg; then echo "  snap[$beat] SKIP (fg!=jak1: $(read_focus))"; return 1; fi
  adb exec-out screencap -p > "$o" 2>/dev/null
  if [ -s "$o" ] && identify "$o" >/dev/null 2>&1; then
    echo "  snap[$beat] -> $beat.png ($(identify -format '%wx%h' "$o" 2>/dev/null))"; return 0
  fi
  echo "  snap[$beat] FAIL"; rm -f "$o"; return 1
}

# --- resolve oracle reference for a beat (oracle-beats preferred, fallback) ---
oracle_for() {
  local beat="$1"
  # intro-logo => the ndi ND-logo-on-BLACK oracle (the real halo beat).
  if [ "$beat" = "intro-logo" ] && [ -f "$NDI_ORACLE" ]; then echo "$NDI_ORACLE"; return; fi
  [ -f "$ORACLE/$beat.png" ] && { echo "$ORACLE/$beat.png"; return; }
  # FALLBACK = TRUE upstream v0.3.3 originals (.autoport/gold/TRUE-original-v033)
  case "$beat" in
    title-pressstart) [ -f "$FALLBACK/01-attract-flythrough.png" ] && echo "$FALLBACK/01-attract-flythrough.png";;
    main-menu)        [ -f "$FALLBACK/05-main-menu.png" ] && echo "$FALLBACK/05-main-menu.png";;
    *) echo "";;
  esac
}

# --- touch-overlay mask rects in GOLDEN (oracle) pixel coords ----------------
# computed from TouchOverlayView.layoutHits: dpad cx=0.12w cy=0.72h, face
# cx=0.88w cy=0.72h, r=0.075h, spacing=1.6r, start cx=0.5w cy=0.92h r=0.7*0.075h
mask_rects_for() {  # GOLDEN.png -> echoes one "X,Y,W,H" per line
  "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
gw, gh = Image.open(sys.argv[1]).size
r = max(40.0, gh*0.075); sp = r*1.6
def rect(cx, cy, half_w, half_h):
    x=int(cx-half_w); y=int(cy-half_h); w=int(2*half_w); h=int(2*half_h)
    x=max(0,x); y=max(0,y); return f"{x},{y},{min(w,gw-x)},{min(h,gh-y)}"
# dpad cluster left
print(rect(gw*0.12, gh*0.72, sp+r+10, sp+r+10))
# face cluster right
print(rect(gw*0.88, gh*0.72, sp+r+10, sp+r+10))
# start button center-bottom
print(rect(gw*0.5, gh*0.92, r*0.7+15, r*0.7+15))
PYEOF
}

# --- launch ------------------------------------------------------------------
echo "== verify_device_graphics: serial=$SERIAL pkg=$PKG thr=$THRESHOLD tol=$TOLERANCE =="
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb logcat -G 16M >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( adb logcat -v threadtime \
    | grep --line-buffered -aE 'A35-RENDER frame=|A36-STR-DIAG rpc name=|overlay-map:|touch-hitbox:|engine: state=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|has died' \
    > "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null; clear_inject 2>/dev/null; adb shell am force-stop "$PKG" >/dev/null 2>&1 || true' EXIT

clear_inject
echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/vdg-amstart.out 2>&1 || true

# --- per-beat state, all start un-reached ------------------------------------
declare -A R_REACHED R_DIFF R_RMSE R_VERDICT R_HALO R_HALOAREA R_REF
for b in intro-logo title-pressstart main-menu newgame-cinematic ingame-firstframe; do
  R_REACHED[$b]=false; R_DIFF[$b]=""; R_RMSE[$b]=""; R_VERDICT[$b]="UNREACHED"
  R_HALO[$b]=""; R_HALOAREA[$b]=""; R_REF[$b]=""
done

# ---- matched-phase intro capture (ndi ND-logo-on-BLACK = the halo beat) ------
# The Android loader is SLOWER than the oracle, so a fixed wall-clock screencap
# lands on the wrong beat. The HALO (a yellow sun-glow blob that the original
# lacks) appears during the ndi Naughty-Dog-logo-on-BLACK beat. So we capture a
# DENSE burst across the whole intro window; graphics_analyze.py (below) then
# selects the burst frame by LOGO-STRUCTURE overlap (the frame whose bright
# pixels best cover the oracle's ND-logo text) and grades the halo on it.
# IMPORTANT: do NOT select by global-min-diff (the old pick_best_frame.py) — the
# ALL-BLACK loader frame minimises diff to a mostly-black oracle, so min-diff
# picked black -> halo read 0.0 on a visibly haloed logo (the false-green this
# phase fixes). A clean device (Gndlogo fix) reads ~0.002 excess; the current
# defective device reads ~0.28 -> a ~140x separation, robust to rotation phase.
echo "== wait for fg==jak1 =="
fg_dl=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$fg_dl" ]; do is_fg && break; sleep 2; done
is_fg && echo "  fg=jak1" || echo "  WARNING fg!=jak1 ($(read_focus))"

BURST="$SHOTS/introburst"; rm -rf "$BURST"; mkdir -p "$BURST"
echo "== dense intro burst (matched-phase): screencap until render>=1500 or 80s =="
bn=0; burst_dl=$(( $(date +%s) + 80 ))
while [ "$(date +%s)" -lt "$burst_dl" ]; do
  if is_fg; then
    bf=$(printf '%03d' "$bn")
    adb exec-out screencap -p > "$BURST/f$bf.png" 2>/dev/null
    if [ -s "$BURST/f$bf.png" ] && identify "$BURST/f$bf.png" >/dev/null 2>&1; then
      bn=$((bn+1))
    else
      rm -f "$BURST/f$bf.png"
    fi
  fi
  fr=$(cur_render_frame); fr=${fr:-0}
  [ "$fr" -ge 1500 ] 2>/dev/null && { echo "  burst: render=$fr >=1500 after $bn shots (attract reached)"; break; }
  sleep 0.7
done
echo "  burst captured $bn frames (render_frame now $(cur_render_frame))"

# intro-logo = the ndi ND-logo-on-BLACK beat. The intro-logo FRAME SELECTION is
# now done by graphics_analyze.py (below) using LOGO-STRUCTURE overlap, NOT the
# old pick_best_frame.py global-min-diff. The old min-diff selector picked the
# ALL-BLACK loader frame (it minimises diff to a mostly-black oracle), so the
# halo frame was never measured -> halo read 0.0 on a visibly haloed logo. The
# analyzer instead picks the burst frame whose bright pixels best COVER the
# oracle's ND-logo text (logo present), then grades the halo on that frame.
echo "  ndi spool seen in logcat: $(grep -acE 'A36-STR-DIAG rpc name=\"ndi-intro\"' "$LOG" 2>/dev/null) ; logo-intro: $(grep -acE 'A36-STR-DIAG rpc name=\"logo-intro\"' "$LOG" 2>/dev/null)"
echo "  intro-logo frame selection deferred to graphics_analyze.py (burst=$bn frames)"

# title-pressstart = the settled PRESS START attract = the LAST good burst frame.
LASTB=$(ls "$BURST"/f*.png 2>/dev/null | sort | tail -1)
if [ -n "$LASTB" ]; then
  cp -f "$LASTB" "$SHOTS/title-pressstart.png" && R_REACHED[title-pressstart]=true
  echo "  title-pressstart <- $(basename "$LASTB") (settled attract)"
fi
sleep 6  # let attract reach interactive PRESS START before cpad START

# ---- beat: main-menu (START) ------------------------------------------------
echo "== START (open progress menu) =="
inject "start"; sleep 1.2; clear_inject; sleep 5
snap main-menu && R_REACHED[main-menu]=true

# ---- beat: newgame-cinematic (nav to NEW GAME + X, continue w/o saving) -----
echo "== nav to NEW GAME + X (Gd1-proven sequence: down,down,up,up settles cursor) =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
# continue without saving dialog
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "x";    sleep 0.6; clear_inject; sleep 6
snap newgame-cinematic && R_REACHED[newgame-cinematic]=true

# ---- beat: ingame-firstframe (let cinematic play out) -----------------------
# INGAME_CAP (default 200s) is the wall cap for the in-game render-frame watch.
# Cinematic-cadence runs render ~36fps wall (vs ~60fps on title/menu) and the
# misty load stall burns dead wall-time, so reaching a deep frame (e.g. >=10500)
# needs a larger cap; callers can override via INGAME_CAP without changing the
# default for the quick static-beat gate.
INGAME_CAP="${INGAME_CAP:-200}"
echo "== let cinematic play to in-game (watch up to ${INGAME_CAP}s for high render frame) =="
CINE_F=$(cur_render_frame); CINE_F=${CINE_F:-0}
target=$((CINE_F + 9000)); t0=$(date +%s)
while :; do
  el=$(( $(date +%s) - t0 )); [ "$el" -ge "$INGAME_CAP" ] && { echo "  ingame wall cap"; break; }
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  [ -z "$PID" ] && { echo "  app gone (crash?) at ${el}s"; break; }
  # crash counter matches sig=(4|6|11): SIGILL(4)/SIGABRT(6)/SIGSEGV(11). The old
  # sig=11-only grep MISSED the SIGILL/SIGABRT crashes (see memory gmatch-pass).
  CR=$(grep -acE "GK-DIAG sig=(4|6|11)|Fatal signal (4|6|11)|signal (4|6|11) \(SIG" "$LOG" 2>/dev/null); CR=${CR:-0}
  [ "$CR" -ge 1 ] && { echo "  CRASH SIGNATURE at ${el}s"; break; }
  FM=$(cur_render_frame); FM=${FM:-0}
  (( el % 20 < 5 )) && echo "   [${el}s] render=$FM target=$target fg=$(is_fg && echo jak1 || echo other)"
  [ "$FM" -ge "$target" ] && { echo "  reached in-game target frame $FM"; break; }
  sleep 5
done
snap ingame-firstframe && R_REACHED[ingame-firstframe]=true

# capture final foreground + crash status BEFORE teardown
ENDFOC="$(read_focus)"; ENDPID="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
# crash regex broadened sig=11 -> sig=(4|6|11) to count SIGILL/SIGABRT/SIGSEGV.
CRASH_SIGS=$(grep -acE 'Fatal signal|signal (4|6|11) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null); CRASH_SIGS=${CRASH_SIGS:-0}

# ---- teardown logcat (keep device usable) -----------------------------------
kill ${LCP:-0} 2>/dev/null || true
clear_inject 2>/dev/null || true
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT

# ---- compare + halo + STATIC-BEAT GATE (graphics_analyze.py is the SOT) ------
# The per-beat diff + halo + the STANDING-GATE verdict are computed by the SINGLE
# source-of-truth analyzer graphics_analyze.py (the SAME code that generates the
# calibration known-bad/report.json offline). It:
#   * selects the intro-logo frame from the burst by LOGO-STRUCTURE overlap
#     (rejects the all-black loader frame the old min-diff selector wrongly chose)
#   * gates the STATIC beats (intro-logo / title-pressstart / main-menu) on the
#     oracle pixel-diff, and gates EVERY beat on the halo/bloom metric
#   * overall_verdict = FAIL on any hard static-beat MISMATCH (menu/logo garble),
#     any halo_excess over --halo-gate, or any crash signature.
echo "== analyze each captured beat vs oracle: static-beat diff gate + halo gate =="
"$PY" .autoport/lib/graphics_analyze.py \
  --shots "$SHOTS" --oracle-beats "$ORACLE" --ndi-oracle "$NDI_ORACLE" \
  --true-original "$FALLBACK" --fc "$FC" --py "$PY" \
  --out "$REPORT" --diff-dir "$OUT" \
  --threshold "$THRESHOLD" --tolerance "$TOLERANCE" --halo-gate "${HALO_GATE:-0.02}" \
  --serial "$SERIAL" --package "$PKG" \
  --end-foreground "$ENDFOC" --end-pid "${ENDPID:-gone}" \
  --crash-sigs "$CRASH_SIGS" --reached auto
GATE_RC=$?
echo "== graphics_analyze exit=$GATE_RC (0=PASS,1=FAIL,2=inconclusive) =="
GATE_VERDICT=$("$PY" -c "import json;print(json.load(open('$REPORT'))['summary']['overall_verdict'])" 2>/dev/null || echo UNKNOWN)
echo "== STANDING GATE overall_verdict=$GATE_VERDICT =="

echo "== device usable check =="
echo "  end foreground: $ENDFOC  pid=${ENDPID:-gone}  crash_sigs=$CRASH_SIGS"
echo "  report: $REPORT"

# This is a REAL gate: exit nonzero when the standing-gate verdict is FAIL so any
# caller (a phase validator, CI) inherits the strictness automatically.
[ "$GATE_VERDICT" = "PASS" ] && exit 0 || exit 1
