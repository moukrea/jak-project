#!/usr/bin/env bash
# gmenu_pos_x86_dump.sh — deterministic per-element POSITION dump of the main
# (progress 'title') menu over the goalc listener, x86-first. NO source edits to
# the target repo: opens the menu and reads RUNTIME fields via (lt)-sent forms.
#
# For the given aspect (AW:AH), forces (set-aspect! *pc-settings* AW AH), opens
# the menu via activate-progress, then polls a dump form that prints each menu
# element's screen-space X/Y (particles[].pos = offset-from-center in GS units;
# screen fraction = pos.x / x-pix) plus the camera/aspect factors. Captured from
# BOTH the target stdout log and the goalc log (format-dest differs across
# goalc versions). Reads only runtime state => target repo stays git-clean.
#
# Env: REPO GK GOALC ISO OUTLOG  AW AH  [POLLS=14]
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
AW="${AW:?}"; AH="${AH:?}"; POLLS="${POLLS:-14}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cd "$REPO"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gmenu-pos] repo=$REPO aspect=${AW}:${AH} polls=$POLLS"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "[gmenu-pos] gk exited during boot"; tail -15 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$GKLOG" && { echo "[gmenu-pos] title attract reached ~${i}s"; break; }; sleep 1; done
grep -qE "link finish: logo-loop" "$GKLOG" || { echo "[gmenu-pos] never reached logo-loop"; tail -20 "$GKLOG"; exit 1; }
sleep 6
timeout $((POLLS+220)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gmenu-pos] build-game sent; waiting up to 140s to intern symbols..."
for i in $(seq 1 140); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK|interned" "$GCLOG" 2>/dev/null && { echo "[gmenu-pos] build-game done ~${i}s"; break; }; done
sleep 4
# force aspect over the listener (safe field-sets); open the menu via REAL START
# input (xfocus_tap key 28) so the title handler runs activate-progress in the
# proper kernel context (calling it from the listener thread segfaults).
SYM="${SYM:-}"  # optional: aspect4x3 | aspect16x9 — forces the get-aspect-ratio symbol
if [ -n "$SYM" ]; then
  OPEN="(begin (set-setting! 'aspect-ratio '${SYM} 0.0 0) (apply-settings *setting-control*) (set-aspect! *pc-settings* ${AW} ${AH}))"
else
  OPEN="(set-aspect! *pc-settings* ${AW} ${AH})"
fi
PY="$HOME/.venv/autoport/bin/python"; [ -x "$PY" ] || PY="python3"
XFOCUS="${XFOCUS:-/home/emeric/code/jak-project/.autoport/xfocus_tap.py}"
# dump form: camera/aspect factors + per-particle pos + per-icon pos (<=6 args/format)
DUMP='(when *progress-process* (let ((pr (-> *progress-process* 0))) (format 0 "GMENU CAM arscale=~f relx=~f xpix=~f xratio=~f perspx=~f hvdfx=~f~%" (-> *pc-settings* aspect-ratio-scale) (-> *video-parms* relative-x-scale) (-> *math-camera* x-pix) (-> *math-camera* x-ratio) (-> *math-camera* perspective vector 0 x) (-> *math-camera* hvdf-off x)) (format 0 "GMENU AUX asym=~A usevis=~A inout=~D npart=~D nicon=~D~%" (get-aspect-ratio) (-> *pc-settings* use-vis?) (-> pr in-out-position) (-> pr nb-of-particles) (-> pr nb-of-icons)) (dotimes (i (-> pr nb-of-particles)) (format 0 "GMENU PART ~D posx=~f posy=~f initx=~f~%" i (-> pr particles i pos x) (-> pr particles i pos y) (-> pr particles i init-pos x))) (dotimes (i (-> pr nb-of-icons)) (format 0 "GMENU ICON ~D iconx=~D icony=~D scalex=~f~%" i (-> pr icons i icon-x) (-> pr icons i icon-y) (-> pr icons i scale-x)))))'
echo "[gmenu-pos] forcing aspect (${AW}:${AH}) over listener"
for k in 1 2 3; do echo "$OPEN" >&3; sleep 1; done
echo "[gmenu-pos] opening menu via START (xfocus_tap 28)"
"$PY" "$XFOCUS" 28 >/tmp/gmenu-focus.log 2>&1 || echo "[gmenu-pos] xfocus_tap warn"
sleep 4
echo "[gmenu-pos] polling ${POLLS}x @1s"
for i in $(seq 1 "$POLLS"); do echo "$OPEN" >&3; echo "$DUMP" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[gmenu-pos] === GMENU samples (from target + listener logs) ==="
{ grep -aE '^GMENU (CAM|AUX|PART|ICON) ' "$GKLOG" 2>/dev/null; grep -aE '^GMENU (CAM|AUX|PART|ICON) ' "$GCLOG" 2>/dev/null; } | sort -u > "$OUTLOG" || true
cat "$OUTLOG" || true
N=$(wc -l < "$OUTLOG" 2>/dev/null || echo 0)
echo "[gmenu-pos] lines=$N -> $OUTLOG"
echo "[gmenu-pos] goalc errors:"; grep -aiE "Compilation Error|does not exist|listen to target|Connected to OpenGOAL|symbol .* not" "$GCLOG" 2>/dev/null | head -8 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
