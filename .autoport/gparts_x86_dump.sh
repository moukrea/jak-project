#!/usr/bin/env bash
# gparts_x86_dump.sh — deterministic PARTICLE + STAR state dump over the goalc listener.
# Boots a desktop gk into the title attract, connects goalc (lt)+(build-game) so the
# game symbols/types are interned, then polls the sparticle + time-of-day state every
# ~0.6s while FORCING fast time (ratio 18000) so the day/night cycle runs and stars
# (night) + sun corona (day) both appear. Reads go to the TARGET stdout via
# (format 0 ...) -> captured from the gk log. NON-INVASIVE: no source edits to the
# target repo (out/ is gitignored so the repo stays git-clean). Works on our-x86 AND
# the pristine original-v033 x86 with the SAME forms (1-to-1 proof).
#
# Metrics per poll (PARTS line):
#   tod   = time-of-day  (float hour 0..24)        hr    = hour (int)
#   nstars= *time-of-day-context* num-stars (target, float)
#   starc = star-count   (# star particles spawned, int)   <- the NIGHT-STAR count
#   sunc  = sun-count    (# sun corona launchers, int)
#   a3d   = *sp-particle-system-3d* num-alloc[0]   (ALIVE 3D particles: stars+ambient+sun)
#   a2d0/1= *sp-particle-system-2d* num-alloc[0/1] (ALIVE 2D particles)
# Plus a one-shot POFF line with the byte offsets of the time-of-day-proc fields
# (for the device C++ read).
#
# Env: GK (abs), GOALC (abs), PROJ (abs proj/cwd), ISO (abs), OUTLOG (abs),
#      POLLS (def 90), LABEL (def x86), DO_BUILD_GAME (def 1)
set -uo pipefail
GK="${GK:?}"; GOALC="${GOALC:?}"; PROJ="${PROJ:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
POLLS="${POLLS:-90}"; LABEL="${LABEL:-x86}"; DO_BUILD_GAME="${DO_BUILD_GAME:-1}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cd "$PROJ"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gparts/$LABEL] gk=$GK proj=$PROJ polls=$POLLS build-game=$DO_BUILD_GAME"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 120); do kill -0 "$GKPID" 2>/dev/null || { echo "[gparts/$LABEL] gk exited during boot"; tail -12 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gparts/$LABEL] booted ~${i}s"; break; }; sleep 1; done
sleep 3
timeout $((POLLS+260)) "$GOALC" --game jak1 --proj-path "$PROJ" --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 2
if [ "$DO_BUILD_GAME" = "1" ]; then
  echo '(build-game)' >&3
  echo "[gparts/$LABEL] build-game sent; waiting up to 140s for symbol intern..."
  for i in $(seq 1 140); do sleep 1; grep -qiE "Successfully built all|Build Successful|\\] OK" "$GCLOG" 2>/dev/null && { echo "[gparts/$LABEL] build-game done ~${i}s"; break; }; done
fi
sleep 3
# One-shot: byte offsets of time-of-day-proc fields (for the device C++ read).
OFFFORM='(when (and *time-of-day-proc* (-> *time-of-day-proc* 0)) (format 0 "POFF hour=~D tod=~D starc=~D sunc=~D~%" (- (the-as int (&-> (-> *time-of-day-proc* 0) hour)) (the-as int (-> *time-of-day-proc* 0))) (- (the-as int (&-> (-> *time-of-day-proc* 0) time-of-day)) (the-as int (-> *time-of-day-proc* 0))) (- (the-as int (&-> (-> *time-of-day-proc* 0) star-count)) (the-as int (-> *time-of-day-proc* 0))) (- (the-as int (&-> (-> *time-of-day-proc* 0) sun-count)) (the-as int (-> *time-of-day-proc* 0)))))'
echo "$OFFFORM" >&3
sleep 1
echo "[gparts/$LABEL] polling ${POLLS}x @0.6s (forcing ratio=18000 -> fast day/night)"
# format() caps at 8 total params (dest + fmt-string + <=6 args); split into PA (time/
# star state, 4 args) + PB (alive sparticle counts, 3 args), emitted per poll.
POLLFORM='(when (and *time-of-day-proc* (-> *time-of-day-proc* 0)) (begin (set! (-> *time-of-day-proc* 0 time-ratio) 18000.0) (format 0 "PA tod=~f hr=~D starc=~D sunc=~D~%" (-> *time-of-day-proc* 0 time-of-day) (-> *time-of-day-proc* 0 hour) (-> *time-of-day-proc* 0 star-count) (-> *time-of-day-proc* 0 sun-count)) (format 0 "PB a3d=~D a2d0=~D a2d1=~D~%" (-> *sp-particle-system-3d* num-alloc 0) (-> *sp-particle-system-2d* num-alloc 0) (-> *sp-particle-system-2d* num-alloc 1))))'
for i in $(seq 1 "$POLLS"); do echo "$POLLFORM" >&3; sleep 0.6; done
exec 3>&-
sleep 3
grep -aE "PA |PB |POFF " "$GKLOG" | sed -E 's/^.*(PA |PB |POFF )/\1/' > "$OUTLOG" 2>/dev/null || true
NP=$(grep -ac 'PA ' "$GKLOG" 2>/dev/null); NP=${NP:-0}
NB=$(grep -ac 'PB ' "$GKLOG" 2>/dev/null); NB=${NB:-0}
NO=$(grep -ac 'POFF ' "$GKLOG" 2>/dev/null); NO=${NO:-0}
echo "[gparts/$LABEL] PA=$NP PB=$NB POFF=$NO -> $OUTLOG"
echo "[gparts/$LABEL] === offsets ==="; grep -aE 'POFF ' "$OUTLOG" | head -1 || true
echo "[gparts/$LABEL] === PA sample (first/last 4) ==="; grep -aE 'PA ' "$OUTLOG" | head -4; echo "..."; grep -aE 'PA ' "$OUTLOG" | tail -4
echo "[gparts/$LABEL] === PB sample (first/last 4) ==="; grep -aE 'PB ' "$OUTLOG" | head -4; echo "..."; grep -aE 'PB ' "$OUTLOG" | tail -4
echo "[gparts/$LABEL] goalc errors:"; grep -aiE "Compilation Error|does not exist|listen to target" "$GCLOG" 2>/dev/null | head -5 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
[ "$NP" -gt 0 ]
