#!/usr/bin/env bash
# gcine_cut_capture.sh — DETERMINISTIC per-frame cutscene camera STATE dump.
# Boots a desktop gk into the title attract, connects goalc, (build-game) to intern
# game symbols, triggers the NEW-GAME intro cinematic EXACTLY like the progress menu
# (progress.gc:739) does, then spawns a per-FRAME GOAL probe that formats the
# math-camera CUT state:
#    reset   = (-> *math-camera* reset)        ; cam-master sets this to 1 ON A CUT
#    trans   = camera world position           ; CUT => big jump, INTERP => smooth
#    forward = (-> *math-camera* camera-rot vector 2)  ; view dir (rotational cuts)
#    fov
# Reads ONLY runtime fields over the listener => NO source edits => the target repo
# stays byte-pristine (build-game writes only gitignored out/). Identical method on
# our-x86 (FMT_DEST=0, output to gk stdout) and the original v0.3.3 (FMT_DEST=#t,
# output to the goalc/listener stdout — format dest is INVERTED across versions).
#
# Env (required): REPO GK GOALC ISO OUTLOG
# Env (optional): GOALC_ARGS  FMT_DEST(0|#t, default 0)  WATCH(default 170)
#                 BUILD_WAIT(default 170)  GCINE_CAM(1 => also OG_GCINE_CAM)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
GOALC_ARGS="${GOALC_ARGS:-}"
FMT_DEST="${FMT_DEST:-0}"
WATCH="${WATCH:-170}"
BUILD_WAIT="${BUILD_WAIT:-170}"
GCINE_CAM="${GCINE_CAM:-0}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
cd "$REPO"

GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[cap] repo=$REPO gk=$GK fmt_dest=$FMT_DEST gcine_cam=$GCINE_CAM watch=${WATCH}s"

CAMENV=()
[ "$GCINE_CAM" = 1 ] && CAMENV=(OG_GCINE_CAM=1)
env "${CAMENV[@]}" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
echo "[cap] gk pid=$GKPID; waiting for title..."
booted=0
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[cap] gk exited during boot"; tail -15 "$GKLOG"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)($|-)" "$GKLOG" 2>/dev/null && { booted=1; echo "[cap] title ~${i}s"; break; }
  sleep 1
done
[ "$booted" = 1 ] || { echo "[cap] boot timeout"; tail -15 "$GKLOG"; exit 1; }
sleep 3

echo "[cap] open listener (args=$GOALC_ARGS)"
timeout $((WATCH+BUILD_WAIT+260)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" $GOALC_ARGS < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo "[cap] (build-game) to intern game symbols; waiting (settle-detect, cap ${BUILD_WAIT}s)"
echo '(build-game)' >&3
t0=$(date +%s); lastsz=-1; stable=0
while :; do
  el=$(( $(date +%s) - t0 )); [ "$el" -ge "$BUILD_WAIT" ] && { echo "[cap] build-game wait cap ${el}s"; break; }
  sz=$(stat -c%s "$GCLOG" 2>/dev/null || echo 0)
  if [ "$sz" = "$lastsz" ]; then stable=$((stable+1)); else stable=0; lastsz=$sz; fi
  if [ "$el" -ge 15 ] && [ "$stable" -ge 3 ]; then echo "[cap] build-game settled ~${el}s (size=$sz)"; break; fi
  sleep 2
done
sleep 2

echo "[cap] trigger NEW-GAME intro cinematic (progress.gc:739 path)"
echo "(set! *debug-segment* #f)" >&3
echo "(when *game-info* (set! (-> *game-info* mode) 'play))" >&3
echo "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")" >&3
echo "(set-master-mode 'game)" >&3
echo "[cap] wait 10s for restart, then spawn per-frame probe"
sleep 10

PROBE="(process-spawn-function process (lambda () (loop (format ${FMT_DEST} \"GCINE-CUT f=~D rst=~D px=~f py=~f pz=~f fov=~f~%\" (current-time) (-> *math-camera* reset) (-> *math-camera* trans x) (-> *math-camera* trans y) (-> *math-camera* trans z) (-> *math-camera* fov)) (format ${FMT_DEST} \"GCINE-FWD f=~D fx=~f fy=~f fz=~f~%\" (current-time) (-> *math-camera* camera-rot vector 2 x) (-> *math-camera* camera-rot vector 2 y) (-> *math-camera* camera-rot vector 2 z)) (suspend))))"
echo "$PROBE" >&3
sleep 1
echo "$PROBE" >&3

# which log carries the probe output: FMT_DEST=0 -> gk stdout; FMT_DEST=#t -> goalc stdout
PLOG="$GKLOG"; [ "$FMT_DEST" = "#t" ] && PLOG="$GCLOG"
echo "[cap] watch ${WATCH}s (probe -> $([ "$FMT_DEST" = "#t" ] && echo goalc || echo gk) log)"
t0=$(date +%s); last=0
while [ $(( $(date +%s) - t0 )) -lt "$WATCH" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "[cap] gk exited at $(( $(date +%s) - t0 ))s"; break; }
  n=$(grep -ac 'GCINE-CUT f=' "$PLOG" 2>/dev/null || echo 0)
  fm=$(grep -a 'GCINE-CUT f=' "$PLOG" 2>/dev/null | tail -1 | grep -oE 'f=[0-9]+' | grep -oE '[0-9]+')
  lv=$(grep -aoE 'link (finish|begin): [a-z0-9-]+' "$GKLOG" 2>/dev/null | awk '{print $3}' | sort -u | tr '\n' ' ')
  if [ "$n" != "$last" ]; then echo "   [$(( $(date +%s) - t0 ))s] GCINE-CUT=$n lastf=${fm:-?} links: $lv"; last=$n; fi
  sleep 5
done
exec 3>&-
sleep 2

echo "[cap] === harvest -> $OUTLOG ==="
grep -aE 'GCINE-CUT f=|GCINE-FWD f=' "$PLOG" > "$OUTLOG" 2>/dev/null || true
[ "$GCINE_CAM" = 1 ] && grep -a 'GCINE-CAM f=' "$GKLOG" > "${OUTLOG%.txt}.gcine-cam.txt" 2>/dev/null || true
N=$(grep -ac 'GCINE-CUT f=' "$OUTLOG" 2>/dev/null || echo 0)
echo "[cap] captured $N GCINE-CUT frames -> $OUTLOG"
echo "[cap] frame range: $(grep -aoE 'f=[0-9]+' "$OUTLOG" | grep -oE '[0-9]+' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
echo "[cap] levels linked: $(grep -aoE 'link (finish|begin): [a-z0-9-]+' "$GKLOG" | awk '{print $3}' | sort -u | tr '\n' ' ')"
echo "[cap] goalc errors:"; grep -aiE 'Compilation Error|does not exist|REPL Error' "$GCLOG" 2>/dev/null | head -6 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
