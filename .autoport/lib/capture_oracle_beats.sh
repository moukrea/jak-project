#!/usr/bin/env bash
# capture_oracle_beats.sh — capture the GROUND-TRUTH ("oracle") reference frames
# for the jak1 intro flow from the UNTOUCHED upstream original (OpenGOAL v0.3.3,
# commit c4bc4d3ff) at /home/emeric/code/jak-original-v033 — NOT our modified
# build-x86 (which carries our changes/bugs and would bias the comparison).
#
# Beats captured (the upstream attract has NO separate Sony/ND movie logos —
# the "title" IS the in-engine attract flythrough; see the TRUE-original README):
#
#   boot               gk launched, IOP/heap up                 [data only]
#   title-pressstart   in-engine attract / title attract        [frame]
#   main-menu          progress menu open (NEW GAME cursor)      [frame]
#   newgame-cinematic  NEW GAME intro cutscene (early beat)      [frame]
#   ingame-firstframe  first in-game frame after cutscene        [frame]
#
# Frames are rendered at internal 2400x1080 (the device aspect 2.222) via the
# engine's built-in screenshot hook (AUTOPORT_SHOT_* env, also present in this
# original binary) — compositor-independent, deterministic frame_idx naming.
# The original has NO GCINE-CAM logging (our addition), so NO camera-data is
# produced for the oracle; this is recorded honestly in beats.json.
#
# REUSES the already-valid v0.3.3 goldens in .autoport/gold/TRUE-original-v033/
# (attract/title, title-wait, main-menu) as canonical references, and writes
# fresh per-beat copies into .autoport/gold/oracle-beats/.
#
# IDEMPOTENT. If a beat can't be reached it's recorded reached:false — never
# faked. Single-user desktop resource (DISPLAY=:0). NEVER pgrep bare 'gk'
# (matches the claude -p process); only the launched PID is killed.
#
# Usage: bash .autoport/lib/capture_oracle_beats.sh [--no-cine]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FORK_ROOT="$(pwd)"

ORIG="/home/emeric/code/jak-original-v033"
GK="$ORIG/build/Release/bin/game/gk"
GOALC="$ORIG/build/Release/bin/goalc/goalc"
SHOTDIR="$ORIG/build/Release/bin/game/OpenGOAL/jak1/screenshots"
PY="$HOME/.venv/autoport/bin/python"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

OUTDIR="$FORK_ROOT/.autoport/gold/oracle-beats"
TRUEDIR="$FORK_ROOT/.autoport/gold/TRUE-original-v033"
LOG="/tmp/oracle-beats.log"
GLOG="/tmp/oracle-beats-goalc.log"
BEATS="$OUTDIR/beats.json"
SHOT_W="${SHOT_W:-2400}"; SHOT_H="${SHOT_H:-1080}"; SHOT_MSAA="${SHOT_MSAA:-2}"

DO_CINE=1
for a in "$@"; do case "$a" in --no-cine) DO_CINE=0;; esac; done

die() { echo "capture_oracle_beats: FATAL: $*" >&2; exit 1; }
[ -x "$GK" ] || die "original gk not found at $GK (build the v0.3.3 original first)"
mkdir -p "$OUTDIR" "$SHOTDIR"

declare -A REACHED FRAME
mark() { REACHED["$1"]="$2"; FRAME["$1"]="${3:-}"; }

cur_frame() { local v; v=$(ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); [ -n "$v" ] && echo $((10#$v)); }
wait_marker() {  # regex timeout_s
  local re="$1" to="${2:-180}" dl; dl=$(( $(date +%s) + to ))
  while [ "$(date +%s)" -lt "$dl" ]; do
    kill -0 "$GK_PID" 2>/dev/null || { echo "  gk EXITED while waiting '$re'"; return 2; }
    grep -aqE "$re" "$LOG" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}
harvest_beat() {  # beat lo hi  -> newest shot whose frame in [lo,hi]
  local beat="$1" lo="$2" hi="$3" best="" bestf=-1 fi
  for f in "$SHOTDIR"/autoport_f*.png; do
    [ -e "$f" ] || continue
    fi=$(basename "$f" | grep -oE '[0-9]+'); fi=$((10#$fi))
    if [ "$fi" -ge "$lo" ] && [ "$fi" -le "$hi" ] && [ "$fi" -gt "$bestf" ]; then best="$f"; bestf="$fi"; fi
  done
  if [ -n "$best" ]; then
    cp -f "$best" "$OUTDIR/$beat.png"
    echo "  beat[$beat] <- $(basename "$best") ($(identify -format '%wx%h' "$best" 2>/dev/null))"
    mark "$beat" true "$bestf"; return 0
  fi
  echo "  beat[$beat] NO oracle screenshot in frame range [$lo,$hi]"
  mark "$beat" false ""; return 1
}

echo "== capture_oracle_beats: ORACLE=$GK (v0.3.3) DISPLAY=$DISPLAY res=${SHOT_W}x${SHOT_H} =="
rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
: > "$LOG"

# Launch from the ORIGINAL's own dir (data symlink convention).
( cd "$ORIG" && env \
    AUTOPORT_SHOT_EVERY=10 AUTOPORT_SHOT_START=300 \
    AUTOPORT_SHOT_W="$SHOT_W" AUTOPORT_SHOT_H="$SHOT_H" AUTOPORT_SHOT_MSAA="$SHOT_MSAA" \
    "$GK" -v --game jak1 --portable --disable-ansi -- -fakeiso -debug -boot ) > "$LOG" 2>&1 &
GK_PID=$!
trap 'kill -INT $GK_PID 2>/dev/null; sleep 2; kill -KILL $GK_PID 2>/dev/null; wait $GK_PID 2>/dev/null' EXIT
echo "  gk pid=$GK_PID"

# ---- boot ----
if wait_marker 'InitIOP OK|Initialized GOAL heap|dkernel: boot mode|Compiled Version: v0.3.3' 120; then
  echo "  beat[boot] reached"; mark boot true ""
else
  echo "  beat[boot] FAILED"; mark boot false ""; tail -20 "$LOG"; die "gk did not boot"
fi

# ---- title-pressstart ----
# Live capture of the in-engine attract; on failure (or to guarantee the
# canonical "PRESS START" attract framing) fall back to the deliberately
# captured authoritative v0.3.3 golden 01-attract-flythrough.png.
if wait_marker 'link finish: default-menu($|-pc)|link finish: logo-loop' 200; then
  echo "  title attract up"
else
  echo "  title marker not seen (continuing)"
fi
sleep 18  # let attract render; shot hook dumping from f300
# the live early-frame capture is the blue logo-intro spinner -> save as intro-logo
harvest_beat intro-logo 300 1600 || true
# title-pressstart = the canonical "PRESS START" Sandover attract; use the
# deliberately-captured authoritative v0.3.3 golden (the device's title beat
# corresponds to this attract, not the spinner).
if [ -f "$TRUEDIR/01-attract-flythrough.png" ]; then
  cp -f "$TRUEDIR/01-attract-flythrough.png" "$OUTDIR/title-pressstart.png"
  echo "  beat[title-pressstart] <- AUTHORITATIVE golden 01-attract-flythrough.png"
  mark title-pressstart true "golden"
else
  harvest_beat title-pressstart 300 1600 || true
fi

# ---- main-menu ----
# Opening the progress menu on the ORIGINAL is unreliable to automate:
#  * the original gk's DECI2 listener does not bind here (no '--auto-lt'), so the
#    goalc-form route can't poke the target, and
#  * its saved input-settings.json remaps START off ENTER, and EWMH-focus uinput
#    keys don't reliably route to the gk window.
# We therefore use the deliberately-captured authoritative v0.3.3 golden
# 05-main-menu.png (NEW GAME / LOAD GAME / OPTIONS ... in English, documented in
# the TRUE-original README) as the canonical menu reference. We still ATTEMPT a
# live menu open first (best-effort) and prefer a fresh frame if it works.
echo "== attempt live menu open (best-effort: focus + START=KEY_DOWN 108) =="
BEFORE=$(cur_frame); BEFORE=${BEFORE:-0}
"$PY" .autoport/xfocus_tap.py 108 >/tmp/oracle-beats-focus.log 2>&1 || echo "  (xfocus_tap failed)"
sleep 6
AFTER=$(cur_frame); AFTER=${AFTER:-$((BEFORE+400))}
MENU_LIVE=0
# Only accept a live menu frame if the screen actually changed to the menu; we
# can't OCR here, so we conservatively prefer the AUTHORITATIVE golden unless
# explicitly told the live open worked via $ORACLE_LIVE_MENU=1.
if [ "${ORACLE_LIVE_MENU:-0}" = "1" ]; then
  harvest_beat main-menu "$((BEFORE+5))" "$AFTER" && MENU_LIVE=1 || true
fi
if [ "$MENU_LIVE" = "0" ] && [ -f "$TRUEDIR/05-main-menu.png" ]; then
  cp -f "$TRUEDIR/05-main-menu.png" "$OUTDIR/main-menu.png"
  echo "  beat[main-menu] <- AUTHORITATIVE golden 05-main-menu.png"
  mark main-menu true "golden"
fi

# ---- newgame-cinematic + ingame-firstframe ----
# BLOCKED on the ORIGINAL build: triggering NEW GAME requires either the DECI2
# listener (does not bind on this original gk) or routed menu input (unreliable,
# see above). We do NOT fake these beats. Recorded reached:false so the harness
# is honest about what the oracle could reach. The device verifier still drives
# the device through these beats (the fork build's listener/cpad_inject work) and
# reports how far the DEVICE gets; a device cinematic/in-game frame simply has no
# oracle reference yet (verdict NO_ORACLE) until this is captured.
if [ "$DO_CINE" = "0" ]; then
  echo "== --no-cine: skip cinematic + in-game =="
  mark newgame-cinematic skipped ""; mark ingame-firstframe skipped ""
else
  echo "== newgame-cinematic / ingame-firstframe: BLOCKED on original (no listener bind, remapped input) =="
  mark newgame-cinematic false "blocked:original-listener+input"
  mark ingame-firstframe  false "blocked:original-listener+input"
fi
# ---- teardown + manifest ----
echo "== teardown =="
kill -INT $GK_PID 2>/dev/null || true; sleep 2; kill -KILL $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true
trap - EXIT

{
  echo "{"
  echo "  \"captured_at\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"resolution\": \"${SHOT_W}x${SHOT_H}\","
  echo "  \"source\": \"UPSTREAM ORIGINAL v0.3.3 (c4bc4d3ff) at $ORIG\","
  echo "  \"camera_data\": \"none (original lacks GCINE-CAM; frame PNGs only)\","
  echo "  \"beats\": {"
  first=1
  for b in boot intro-logo title-pressstart main-menu newgame-cinematic ingame-firstframe; do
    [ -z "${REACHED[$b]:-}" ] && continue
    [ "$first" = 1 ] || echo ","
    first=0
    png="$OUTDIR/$b.png"; haspng="false"; [ -f "$png" ] && haspng="true"
    printf '    "%s": {"reached": "%s", "frame": "%s", "png": %s}' \
      "$b" "${REACHED[$b]}" "${FRAME[$b]:-}" "$haspng"
  done
  echo ""
  echo "  }"
  echo "}"
} > "$BEATS"

echo "== oracle beats captured (from v0.3.3 ORIGINAL) =="
ls -la "$OUTDIR"/*.png 2>/dev/null
echo "-- beats.json --"; cat "$BEATS"
echo "-- reusable TRUE-original goldens --"; ls "$TRUEDIR"/*.png 2>/dev/null
