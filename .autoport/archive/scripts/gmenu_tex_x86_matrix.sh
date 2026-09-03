#!/usr/bin/env bash
# gmenu_tex_x86_matrix.sh — x86-first ground truth for the menu user-hvdf MATRIX
# index. Opens the title 'progress' menu over the goalc listener at a forced
# aspect and dumps, per progress particle, the launch-control `matrix` field (the
# user-hvdf index) + the *sprite-hvdf-control* alloc array state (nalloc / first
# free slot). Reads RUNTIME state only => target repo stays git-clean.
#
# Expectation (x86, working): matrix = 12..16 for the visible menu particles,
# firstfree ~= 12 (slots 1..11 pre-allocated by the title HUD).
#
# Env: REPO GK GOALC ISO OUTLOG  AW AH  [POLLS=14]
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
AW="${AW:-20}"; AH="${AH:-9}"; POLLS="${POLLS:-14}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cd "$REPO"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gmenu-mtx] repo=$REPO aspect=${AW}:${AH} polls=$POLLS"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "[gmenu-mtx] gk exited during boot"; tail -15 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$GKLOG" && { echo "[gmenu-mtx] title attract reached ~${i}s"; break; }; sleep 1; done
grep -qE "link finish: logo-loop" "$GKLOG" || { echo "[gmenu-mtx] never reached logo-loop"; tail -20 "$GKLOG"; exit 1; }
sleep 6
timeout $((POLLS+220)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gmenu-mtx] build-game sent; waiting up to 140s to intern symbols..."
for i in $(seq 1 140); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK|interned" "$GCLOG" 2>/dev/null && { echo "[gmenu-mtx] build-game done ~${i}s"; break; }; done
sleep 4
OPEN="(set-aspect! *pc-settings* ${AW} ${AH})"
PY="$HOME/.venv/autoport/bin/python"; [ -x "$PY" ] || PY="python3"
XFOCUS="${XFOCUS:-/home/emeric/code/jak-project/.autoport/xfocus_tap.py}"
# DUMP: alloc-array summary + per-particle launch-control matrix index
DUMP='(when *progress-process* (let ((pr (-> *progress-process* 0))) (let ((nalloc 0) (firstfree -1)) (dotimes (j 76) (when (nonzero? (-> *sprite-hvdf-control* alloc j)) (+! nalloc 1)) (when (and (< firstfree 0) (zero? (-> *sprite-hvdf-control* alloc j))) (set! firstfree j))) (format 0 "GMENU-HVDF nalloc=~D firstfree=~D npart=~D inout=~D~%" nalloc firstfree (-> pr nb-of-particles) (-> pr in-out-position))) (dotimes (i (-> pr nb-of-particles)) (format 0 "GMENU-MTX ~D matrix=~D initx=~f~%" i (-> pr particles i part matrix) (-> pr particles i init-pos x)))))'
echo "[gmenu-mtx] forcing aspect (${AW}:${AH}) over listener"
for k in 1 2 3; do echo "$OPEN" >&3; sleep 1; done
echo "[gmenu-mtx] opening menu via START (xfocus_tap 28)"
"$PY" "$XFOCUS" 28 >/tmp/gmenu-mtx-focus.log 2>&1 || echo "[gmenu-mtx] xfocus_tap warn"
sleep 4
echo "[gmenu-mtx] polling ${POLLS}x @1s"
for i in $(seq 1 "$POLLS"); do echo "$OPEN" >&3; echo "$DUMP" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[gmenu-mtx] === GMENU matrix/hvdf samples (target + listener logs) ==="
{ grep -aE '^GMENU-(HVDF|MTX|ALLOC|AS)' "$GKLOG" 2>/dev/null; grep -aE '^GMENU-(HVDF|MTX|ALLOC|AS)' "$GCLOG" 2>/dev/null; } | sort -u > "$OUTLOG" || true
cat "$OUTLOG" || true
N=$(wc -l < "$OUTLOG" 2>/dev/null || echo 0)
echo "[gmenu-mtx] lines=$N -> $OUTLOG"
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
