#!/usr/bin/env bash
# gcine_cut_capture.sh — DETERMINISTIC per-frame cutscene CUT/INTERP state dump.
# Boots a desktop gk to the title, connects goalc, (build-game) to intern game
# symbols (waits for the EXPLICIT "Successfully built all" marker — attempt 1's
# size-settle heuristic fired before build-game finished, so *game-info* was not
# interned and the trigger failed), triggers the NEW-GAME intro cinematic the same
# way the progress menu does, then spawns a per-FRAME GOAL probe that formats the
# camera CUT/INTERP state read ONLY from runtime globals (no source edits => the
# target repo stays byte-pristine; build-game writes only gitignored out/):
#   rst = (-> *math-camera* reset)       ; cam-master sets 1 ONLY on a zero-blend CUT (cam-master.gc:681)
#   iv  = (-> *camera-combiner* interp-val)   ; 0->1 ramp during an INTERP (cam-combiner.gc:208)
#   is  = (-> *camera-combiner* interp-step)  ; 5.0/blend-dur (huge=cut, small=interp; cam-combiner.gc:22)
#   ns  = (-> *camera* num-slaves)       ; 2 while interpolating between two shots, 1 when settled
#   pos = (-> *math-camera* trans)       ; CUT => big one-frame jump, INTERP => smooth
# format dest is INVERTED across versions: HEAD => 0 (-> gk stdout), v0.3.3 => #t (-> goalc stdout).
#
# Env (required): REPO GK GOALC ISO OUTLOG
# Env (optional): GOALC_ARGS FMT_DEST(0|#t default 0) WATCH(default 220) GCINE_CAM(1)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
GOALC_ARGS="${GOALC_ARGS:-}"
FMT_DEST="${FMT_DEST:-0}"
WATCH="${WATCH:-220}"
GCINE_CAM="${GCINE_CAM:-0}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# Resolve OUTLOG to ABSOLUTE before cd (REPO may be the original repo, where a
# relative OUTLOG would not resolve — attempt cost us a stranded harvest).
case "$OUTLOG" in /*) : ;; *) OUTLOG="$PWD/$OUTLOG" ;; esac
mkdir -p "$(dirname "$OUTLOG")"
cd "$REPO"

GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[cap] repo=$REPO fmt_dest=$FMT_DEST gcine_cam=$GCINE_CAM watch=${WATCH}s"

CAMENV=(); [ "$GCINE_CAM" = 1 ] && CAMENV=(OG_GCINE_CAM=1)
env "${CAMENV[@]}" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
echo "[cap] gk pid=$GKPID; waiting for boot..."
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[cap] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  if grep -aqE "link finish: default-menu($|-pc)" "$GKLOG" 2>/dev/null; then booted=1; echo "[cap] default-menu ~${i}s"; break; fi
  if grep -aqE "link finish: logo($|-)" "$GKLOG" 2>/dev/null && [ "$i" -ge 30 ]; then booted=1; echo "[cap] logo+fallback ~${i}s"; break; fi
  sleep 1
done
[ "$booted" = 1 ] || { echo "[cap] boot timeout"; tail -20 "$GKLOG"; exit 1; }
sleep 4

echo "[cap] open listener (args=$GOALC_ARGS)"
timeout $((WATCH+700)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" $GOALC_ARGS < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 5
echo "[cap] (build-game) to intern game symbols; waiting up to 240s for 'Successfully built all'"
echo '(build-game)' >&3
built=0
for i in $(seq 1 240); do
  sleep 1
  grep -aqiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { built=1; echo "[cap] build-game done ~${i}s"; break; }
  kill -0 "$GKPID" 2>/dev/null || { echo "[cap] gk died during build-game"; tail -20 "$GKLOG"; exit 1; }
done
[ "$built" = 1 ] || echo "[cap] WARN: build-game marker not seen; proceeding anyway"
sleep 4

echo "[cap] trigger NEW-GAME intro cinematic"
echo "(when *game-info* (set! (-> *game-info* mode) 'play))" >&3
echo "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")" >&3
echo "(set-master-mode 'game)" >&3
echo "[cap] wait 10s for cinematic restart, then spawn per-frame probe"
sleep 10

PROBE="(process-spawn-function process (lambda () (loop (format ${FMT_DEST} \"CAMCUT f=~D rst=~D iv=~f is=~f ns=~D~%\" (current-time) (-> *math-camera* reset) (-> *camera-combiner* interp-val) (-> *camera-combiner* interp-step) (-> *camera* num-slaves)) (format ${FMT_DEST} \"CAMPOS f=~D px=~f py=~f pz=~f~%\" (current-time) (-> *math-camera* trans x) (-> *math-camera* trans y) (-> *math-camera* trans z)) (suspend))))"
echo "$PROBE" >&3
sleep 2
echo "$PROBE" >&3

PLOG="$GKLOG"; [ "$FMT_DEST" = "#t" ] && PLOG="$GCLOG"
echo "[cap] watch ${WATCH}s (probe -> $([ "$FMT_DEST" = "#t" ] && echo goalc || echo gk) log)"
t0=$(date +%s); last=0
while [ $(( $(date +%s) - t0 )) -lt "$WATCH" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "[cap] gk exited at $(( $(date +%s) - t0 ))s"; break; }
  n=$(grep -ac 'CAMCUT f=' "$PLOG" 2>/dev/null || echo 0)
  fm=$(grep -a 'CAMCUT f=' "$PLOG" 2>/dev/null | tail -1 | grep -oE 'f=[0-9]+' | grep -oE '[0-9]+')
  lv=$(grep -aoE 'link (finish|begin): [a-z0-9-]+' "$GKLOG" 2>/dev/null | awk '{print $3}' | sort -u | tr '\n' ' ')
  if [ "$n" != "$last" ]; then echo "   [$(( $(date +%s) - t0 ))s] CAMCUT=$n lastf=${fm:-?} links: $lv"; last=$n; fi
  sleep 5
done
exec 3>&-
sleep 2

echo "[cap] === harvest -> $OUTLOG ==="
grep -aE 'CAMCUT f=|CAMPOS f=' "$PLOG" > "$OUTLOG" 2>/dev/null || true
[ "$GCINE_CAM" = 1 ] && grep -a 'GCINE-CAM f=' "$GKLOG" > "${OUTLOG%.txt}.gcine-cam.txt" 2>/dev/null || true
N=$(grep -ac 'CAMCUT f=' "$OUTLOG" 2>/dev/null || echo 0)
echo "[cap] captured $N CAMCUT frames -> $OUTLOG"
echo "[cap] frame range: $(grep -aoE 'f=[0-9]+' "$OUTLOG" | grep -oE '[0-9]+' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
echo "[cap] levels linked: $(grep -aoE 'link (finish|begin): [a-z0-9-]+' "$GKLOG" | awk '{print $3}' | sort -u | tr '\n' ' ')"
echo "[cap] goalc errors:"; grep -aiE 'Compilation Error|does not exist|REPL Error|cannot use more than' "$GCLOG" 2>/dev/null | head -6 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
