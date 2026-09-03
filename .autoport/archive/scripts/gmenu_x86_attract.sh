#!/usr/bin/env bash
# Capture the x86 title-attract flythrough continuously (NO menu) to discover
# whether/when the camera sweeps through the golden's vista pose. 2400x1080.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
OUTDIR="/tmp/gmenu-attract"; LOG="/tmp/gmenu-attract.log"
GK="build-x86/game/gk"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
: > "$LOG"
echo "== launching gk (attract, no input) =="
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
AUTOPORT_SHOT_EVERY=45 AUTOPORT_SHOT_START=1500 AUTOPORT_SHOT_W=2400 AUTOPORT_SHOT_H=1080 AUTOPORT_SHOT_MSAA=4 \
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!; echo "  gk pid=$GKPID"
cleanup(){ kill -INT "$GKPID" 2>/dev/null||true; sleep 2; kill -KILL "$GKPID" 2>/dev/null||true; wait "$GKPID" 2>/dev/null||true; }
trap cleanup EXIT
deadline=$(( $(date +%s) + 160 )); got=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "gk exited"; tail -12 "$LOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$LOG" 2>/dev/null && { got=1; break; }; sleep 2
done
[ "$got" = 1 ] || { echo "no logo-loop"; tail -15 "$LOG"; exit 1; }
echo "  attract running; capturing 90s continuously"
sleep 90
n=0
for f in $(ls -t "$SHOTDIR"/autoport_f*.png 2>/dev/null); do cp -f "$f" "$OUTDIR/$(basename $f)"; n=$((n+1)); done
echo "  harvested $n frames"; ls "$OUTDIR" | head -3; ls "$OUTDIR" | tail -3
