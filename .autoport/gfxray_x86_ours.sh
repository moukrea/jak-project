#!/usr/bin/env bash
# gfxray_x86_ours.sh — OUR-x86 logo-volumes (title light-rays) lifetime dump.
# Rebuilds the x86 TIT.DGO from current goal_src (which carries the temporary
# GFXRAY (format 0 ...) per-frame dump in title-obs.gc logo startup :post),
# boots build-x86/game/gk standalone into the title attract, and captures the
# GFXRAY lines from gk stdout. On OUR HEAD, (format 0 ...) -> stdout (the
# format-dest is inverted vs the v0.3.3 original; see ghalo-sun-listener-dump-gotchas).
# Deterministic STATE dump, NOT pixels.
#
# Env: OUTLOG (abs, def .autoport/reports/Gfix-title-rays/ours-x86.txt)
#      SECS (capture seconds after link, def 100), FORCE (1=force full iso rebuild)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GOALC="build-x86/goalc/goalc"
GK="build-x86/game/gk"
ISO="out/jak1/iso"
OUTLOG="${OUTLOG:-.autoport/reports/Gfix-title-rays/ours-x86.txt}"
SECS="${SECS:-100}"
FORCE="${FORCE:-1}"
mkdir -p "$(dirname "$OUTLOG")"
export DISPLAY="${DISPLAY:-:0}"

[ -x "$GOALC" ] || { echo "[ours] missing $GOALC"; exit 1; }
[ -x "$GK" ]    || { echo "[ours] missing $GK"; exit 1; }
"$GOALC" --version 2>&1 | grep -q "backend: x86" || { echo "[ours] $GOALC not x86"; exit 1; }

BLOG=".autoport/reports/Gfix-title-rays/ours-x86-build.log"
if [ "$FORCE" = "1" ]; then MK='(make-group "iso" :force #t)'; else MK='(make-group "iso")'; fi
echo "[ours] rebuild x86 iso: $MK (logo-volumes dump in TIT.DGO) ..."
"$GOALC" --user-auto --game jak1 --disable-ansi -c "$MK" > "$BLOG" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$BLOG" || { echo "[ours] BUILD FAILED"; tail -40 "$BLOG"; exit 1; }
echo "[ours] $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$BLOG" | head -1)"

GKLOG="$(mktemp)"; : > "$GKLOG"
echo "[ours] boot gk standalone, capture ${SECS}s (wall-clock timestamped) ..."
( "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
   | python3 -u -c 'import sys,time
for l in sys.stdin:
    sys.stdout.write(f"{time.time():.3f} "+l)' > "$GKLOG" ) &
GKPID=$!
cleanup(){ kill "$GKPID" 2>/dev/null || true; pkill -f "build-x86/game/gk" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup EXIT
for i in $(seq 1 120); do kill -0 "$GKPID" 2>/dev/null || { echo "[ours] gk exited during boot"; tail -25 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[ours] booted ~${i}s"; break; }; sleep 1; done
echo "[ours] capturing attract ${SECS}s (the J&D smash + post-smash window)"
sleep "$SECS"
cleanup; trap - EXIT
grep -a "GFXRAY" "$GKLOG" > "$OUTLOG" 2>/dev/null || true
N=$(grep -ac "GFXRAY" "$GKLOG" 2>/dev/null || echo 0)
echo "[ours] GFXRAY lines=$N -> $OUTLOG"
echo "[ours] --- transition window (vol 1->0) ---"
awk '
  /GFXRAY/ {
    ts=$1+0;
    match($0,/f=([0-9]+) vol=([0-9]+) bga=([-0-9.]+) vil=([a-zA-Z0-9_-]+)/,m);
    f=m[1]; vol=m[2]; bga=m[3]; vil=m[4];
    if (prevvol==0 && vol==1){ appf=f; appts=ts; print "  APPEAR vol@frame="f" bga="bga" vil="vil" ts="ts; }
    if (prevvol==1 && vol==0){ print "  VANISH vol@frame="f" bga="bga" vil="vil" ts="ts"  (prev frame "prevf" bga "prevbga" vil "prevvil")";
                               printf "  -> RAYS wall-clock = %.3f s  (base-frame span %d)\n", ts-appts, f-appf; }
    prevvol=vol; prevf=f; prevbga=bga; prevvil=vil;
  }' "$OUTLOG" || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
