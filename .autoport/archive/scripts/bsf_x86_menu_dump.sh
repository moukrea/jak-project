#!/usr/bin/env bash
# bsf_x86_menu_dump.sh — Grecharged-buildsys-flags deliverable-4 desktop proof via
# DETERMINISTIC STATE DUMP (owner methodology: state dumps, not screenshots).
# Boots the freshly built DEFAULT linux gk + default-flag CGOs, opens the title
# menu (real START key via xfocus_tap), then dumps over the goalc listener:
#   - *graphic-options-pc* (desktop) + *graphic-options-pc-android* lengths,
#   - which array *options-remap* graphic-settings points at (must be desktop),
#   - every row's :name text-id for both arrays.
# Android-hidden rows kept on desktop == text-ids #x1031 display-mode / #x1043
# display / #x1060 frame-rate present in the DESKTOP rows and absent from the
# android rows. No VULKAN row (flag off) == desktop len 14 / android len 11.
# Adapted from .autoport/gmenu_pos_x86_dump.sh (proven boot+listener recipe).
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"; cd "$REPO"
GK="${GK:-$REPO/build/game/gk}"; GOALC="${GOALC:-$REPO/build/goalc/goalc}"
ISO="${ISO:-$REPO/out/jak1/iso}"
OUT=.autoport/reports/Grecharged-buildsys-flags; mkdir -p "$OUT"
DUMPLOG="$OUT/desktop-menu-state-dump.txt"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
echo "[bsf-x86] gk=$GK iso=$ISO" | tee "$DUMPLOG"
strings "$GK" | grep -m1 '^ogflags:' | tee -a "$DUMPLOG"
grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$ISO/GAME.CGO" | head -1 | tee -a "$DUMPLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "[bsf-x86] gk exited during boot"; tail -15 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$GKLOG" && { echo "[bsf-x86] title attract ~${i}s"; break; }; sleep 1; done
grep -qE "link finish: logo-loop" "$GKLOG" || { echo "[bsf-x86] never reached logo-loop"; tail -20 "$GKLOG"; exit 1; }
sleep 6
timeout 400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[bsf-x86] build-game sent; waiting up to 160s..."
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "[bsf-x86] build-game done ~${i}s"; break; }; done
sleep 4
PY="$HOME/.venv/autoport/bin/python"; [ -x "$PY" ] || PY="python3"
XFOCUS="/home/emeric/code/jak-project/.autoport/xfocus_tap.py"
"$PY" "$XFOCUS" 28 2>/dev/null || true   # START -> open title menu (runs init-game-options)
sleep 3
DUMP='(let ((d *graphic-options-pc*) (a *graphic-options-pc-android*) (sel (-> *options-remap* (progress-screen graphic-settings)))) (format 0 "BSF ARR dlen=~D alen=~D sel-is-desktop=~A sel-is-android=~A~%" (-> d length) (-> a length) (eq? sel d) (eq? sel a)) (dotimes (i (-> d length)) (format 0 "BSF DROW ~D name=#x~X~%" i (-> d i name))) (dotimes (i (-> a length)) (format 0 "BSF AROW ~D name=#x~X~%" i (-> a i name))))'
for try in 1 2 3; do
  echo "$DUMP" >&3
  sleep 5
  { grep -ha "BSF " "$GKLOG" "$GCLOG" 2>/dev/null || true; } > "$OUT/.bsf_lines.tmp"
  [ -s "$OUT/.bsf_lines.tmp" ] && break
  "$PY" "$XFOCUS" 28 2>/dev/null || true; sleep 3
done
grep -ha "BSF " "$GKLOG" "$GCLOG" 2>/dev/null | sort -u | tee -a "$DUMPLOG"
grep -q "BSF ARR" "$DUMPLOG" || { echo "[bsf-x86] DUMP FAILED (no BSF ARR line)"; tail -25 "$GCLOG"; exit 2; }
echo "[bsf-x86] dump complete -> $DUMPLOG"
