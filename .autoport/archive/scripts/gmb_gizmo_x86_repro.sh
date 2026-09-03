#!/usr/bin/env bash
# gmb_gizmo_x86_repro.sh — Grecharged-mesh-browser v2.2: DESKTOP repro of the device finding
# "rtf_gizmo_px=0 while rtf_gizmo=120" (gizmo lines emitted, zero framebuffer pixels changed).
#
# Method: boot the desktop build warped onto the village1 beach (OG_LEVEL_WARP, meters), attach
# the goalc REPL ((lt) + ad-hoc calls only — NO make/build forms, they overwrite CGO paths), arm
# the SAME C++ target channel the freecam buttons drive (pc-mb-pick-levels!/pc-mb-target-set!/
# pc-mb-gizmos-set!), and read the SAME render-thread counters the device proof reads
# (pc-mb-rt-geti 2/3/6/10). Desktop FBO is single-sampled (settings default msaa=1) so the
# glReadPixels px counter is live here exactly like on the Android FBO.
# Rows: 2156 = vil-beach-01 (TFRAG, 177k m2 footprint around the spawn -> arrows guaranteed in
# the centre band) and 8671 = vil-beachrock (TIE, same system as the device run).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/gmbgz
mkdir -p "$OUT"
GKLOG=$OUT/gk.log
RLOG=$OUT/goalc.log
GK=build-mbrowse/game/gk
[ -x "$GK" ] || { echo "no $GK"; exit 1; }
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"

pkill -f "$GK" 2>/dev/null; sleep 1

SHOTS=build-mbrowse/game/OpenGOAL/jak1/screenshots
rm -f "$SHOTS"/autoport_f*.png
DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$XAUTH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS="10 3 -25" \
AUTOPORT_SHOT_EVERY=60 AUTOPORT_SHOT_START=600 AUTOPORT_SHOT_STOP=30000 \
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!

t=0
until grep -qa "LEVEL-WARP-SPAWN\|link finish: logo" "$GKLOG"; do
  sleep 3; t=$((t+3))
  kill -0 $GKPID 2>/dev/null || { echo "gk died during boot"; tail -20 "$GKLOG"; exit 1; }
  [ $t -ge 300 ] && { echo "no boot after ${t}s"; exit 1; }
done
sleep 25   # let the warp land and the level render steady

FIFO=$OUT/repl.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
( build/goalc/goalc --game jak1 --proj-path . < "$FIFO" > "$RLOG" 2>&1 ) &
GCPID=$!
exec 9>"$FIFO"
say(){ printf '%s\n' "$1" >&9; sleep "${2:-1.5}"; }

say "(lt)" 6
say "(define-extern pc-mb-pick-levels! (function string string none))" 1
say "(define-extern pc-mb-target-set! (function int int none))" 1
say "(define-extern pc-mb-gizmos-set! (function int none))" 1
say "(define-extern pc-mb-target-clear! (function none))" 1
say "(define-extern pc-mb-rt-geti (function int int))" 1
say "(pc-mb-pick-levels! \"village1\" \"\")" 2

probe(){ # label row: arm target+gizmos, then poll the monotonic + per-frame counters
  local label="$1" row="$2"
  say "(pc-mb-target-set! $row 0)" 2
  say "(pc-mb-gizmos-set! 1)" 4
  # format is not available to a fresh REPL; bare expressions echo their value. Order per round:
  # draws(2) faces(3) prims(6) px(10) — parsed positionally from the REPL echo.
  for i in 1 2 3; do
    say "(pc-mb-rt-geti 2)" 2
    say "(pc-mb-rt-geti 3)" 2
    say "(pc-mb-rt-geti 6)" 2
    say "(pc-mb-rt-geti 10)" 2
  done
  say "(pc-mb-gizmos-set! 0)" 2
  say "(pc-mb-target-clear!)" 2
}
# Arm the beach target's gizmos and LEAVE THEM ON: every subsequent captured frame carries
# arrows if the draw lands at all (frame-time vs wall-time correlation killed the last census).
say "(pc-mb-target-set! 2156 0)" 2
say "(pc-mb-gizmos-set! 1)" 2
sleep 90
for i in 1 2 3; do
  say "(pc-mb-rt-geti 2)" 2
  say "(pc-mb-rt-geti 6)" 2
  say "(pc-mb-rt-geti 10)" 2
done
say "(e)" 2
exec 9>&-
sleep 2
kill $GKPID $GCPID 2>/dev/null
sleep 1
echo "=== REPL value echoes (counter polls, positional: draws faces prims px x3, TFRAG then TIE) ==="
grep -aE '^[0-9]+ +#x' "$RLOG" | head -40
echo "=== mb-gizmos lines ==="
grep -a "mb-gizmos" "$GKLOG" || echo "(none)"
echo "=== mesh-browser index lines ==="
grep -a "mesh-browser" "$GKLOG" | head -5
echo "=== arrow-pixel census (pure green/red per frame; arrows are (0,1,0)/(1,0,0)) ==="
cp "$SHOTS"/autoport_f*.png "$OUT"/ 2>/dev/null
python3 - "$OUT" <<'EOF'
import glob, sys
from PIL import Image
for f in sorted(glob.glob(sys.argv[1] + "/autoport_f*.png")):
    im = Image.open(f).convert("RGB")
    px = im.getdata()
    g = sum(1 for r, gg, b in px if gg > 200 and r < 60 and b < 60)
    r_ = sum(1 for r, gg, b in px if r > 200 and gg < 60 and b < 60)
    print(f.split("/")[-1], "green:", g, "red:", r_)
EOF
echo "logs: $GKLOG $RLOG"
