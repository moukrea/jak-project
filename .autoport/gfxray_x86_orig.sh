#!/usr/bin/env bash
# gfxray_x86_orig.sh — ORIGINAL-x86 logo-volumes (title light-rays) lifetime dump,
# using the UNTOUCHED original v0.3.3 (c4bc4d3ff) build at /home/emeric/code/jak-original-v033
# with its OWN toolchain. title-obs.gc there carries a temporary GFXRAY (format #t ...)
# dump in the logo startup :post (v0.3.3 routes (format #t ...) -> the listener; see
# ghalo-sun-listener-dump-gotchas). We rebuild TIT.DGO with the v033 goalc, boot the
# v033 gk, attach the v033 goalc listener (so the per-frame format #t streams to goalc
# stdout), and capture the GFXRAY lines. The v033 source is restored to byte-pristine
# (git checkout) by the caller afterwards. Deterministic STATE dump, NOT pixels.
#
# Env: OUTLOG (abs, def .../orig-x86.txt), SECS (capture after link, def 110)
set -uo pipefail
V="/home/emeric/code/jak-original-v033"
GOALC="$V/build/Release/bin/goalc/goalc"
GK="$V/build/Release/bin/game/gk"
ISO="$V/out/jak1/iso"
ROOT="$(git -C /home/emeric/code/jak-project rev-parse --show-toplevel)"
OUTLOG="${OUTLOG:-$ROOT/.autoport/reports/Gfix-title-rays/orig-x86.txt}"
SECS="${SECS:-110}"
mkdir -p "$(dirname "$OUTLOG")"
export DISPLAY="${DISPLAY:-:0}"
[ -x "$GOALC" ] || { echo "[orig] missing $GOALC"; exit 1; }
[ -x "$GK" ]    || { echo "[orig] missing $GK"; exit 1; }
cd "$V"

BLOG="$ROOT/.autoport/reports/Gfix-title-rays/orig-x86-build.log"
echo "[orig] rebuild v033 iso TIT.DGO with v033 goalc ..."
"$GOALC" --user-auto --game jak1 --disable-ansi -c '(make-group "iso")' > "$BLOG" 2>&1 \
  || "$GOALC" --user-auto --game jak1 --disable-ansi -c '(mi)' >> "$BLOG" 2>&1 || true
grep -qE "Successfully built all [0-9]+ targets|Done!|\] OK" "$BLOG" || { echo "[orig] BUILD maybe-failed; tail:"; tail -40 "$BLOG"; }
echo "[orig] $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$BLOG" | head -1)"

GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"; : > "$GKLOG"; : > "$GCLOG"
echo "[orig] boot v033 gk ..."
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 140); do kill -0 "$GKPID" 2>/dev/null || { echo "[orig] gk exited during boot"; tail -25 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[orig] booted ~${i}s"; break; }; sleep 1; done
# attach listener BEFORE the smash so the startup :post (format #t ...) per-frame stream is captured
timeout $((SECS+60)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo "[orig] listener attached; capturing attract ${SECS}s (J&D smash + post-smash window)"
# light keepalive so the connection is not idle-closed (no build-game: dump is native in the DGO)
for i in $(seq 1 "$SECS"); do echo '(/ 1 1)' >&3 2>/dev/null || break; sleep 1; done
exec 3>&-
sleep 2
cleanup; trap - EXIT
# GFXRAY lines arrive on the listener (goalc stdout). Filter value lines (skip the form echo).
grep -aE "GFXRAY f=[0-9]" "$GCLOG" > "$OUTLOG" 2>/dev/null || true
N=$(grep -acE "GFXRAY f=[0-9]" "$GCLOG" 2>/dev/null || echo 0)
if [ "$N" -eq 0 ]; then grep -aE "GFXRAY f=[0-9]" "$GKLOG" > "$OUTLOG" 2>/dev/null || true; N=$(grep -acE "GFXRAY f=[0-9]" "$GKLOG" 2>/dev/null || echo 0); echo "[orig] (fell back to gk stdout) "; fi
echo "[orig] GFXRAY lines=$N -> $OUTLOG"
echo "[orig] --- transition window (vol 1->0) ---"
awk '
  /GFXRAY f=/ {
    match($0,/f=([0-9]+) vol=([0-9]+) bga=([-0-9.]+) vil=([a-zA-Z0-9_-]+)/,m);
    f=m[1]; vol=m[2]; bga=m[3]; vil=m[4];
    if (prevvol==0 && vol==1) print "  APPEAR vol@frame="f" bga="bga" vil="vil;
    if (prevvol==1 && vol==0) print "  VANISH vol@frame="f" bga="bga" vil="vil"  (prev frame "prevf" bga "prevbga" vil "prevvil")";
    prevvol=vol; prevf=f; prevbga=bga; prevvil=vil;
  }' "$OUTLOG" || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
