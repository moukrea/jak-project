#!/usr/bin/env bash
# gmenu_x86_probes.sh — rebuild build-x86/gk (incl. the shared mips2c GK-MWRITE/GK-COMMIT/GK-SPB
# probes + renderer GK-G1/GK-SPR3) and run it to the progress menu, harvesting the SAME probes the
# device run uses. The x86 values at each probe point are the reference: where x86 shows the matrix
# (1..34) but arm64 shows it lost is the exact divergence.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK="build-x86/game/gk"
ISO="out/jak1/iso"
OUT=.autoport/reports/Gmenu-textures
GKLOG="$OUT/x86-probes-gk.log"
SUM="$OUT/x86-probes-summary.txt"
mkdir -p "$OUT"
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  XA=$(ls -t /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1); export XAUTHORITY="${XA:-$HOME/.Xauthority}"
fi
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "=== build build-x86/gk (recompiles mips2c sparticle probes) ==="
cmake --build build-x86 --target gk -j > "$OUT/x86-build.log" 2>&1
rc=$?
tail -3 "$OUT/x86-build.log"
[ $rc -eq 0 ] || { say "x86 build FAILED rc=$rc"; exit 10; }
say "built: $(stat -c '%y' "$GK")"

say "=== boot build-x86/gk to title, open menu, harvest ==="
: > "$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup EXIT
ok=0
for i in $(seq 1 200); do
  kill -0 "$GKPID" 2>/dev/null || { say "gk exited during boot"; tail -15 "$GKLOG"; break; }
  grep -qaE 'link finish: logo-loop' "$GKLOG" 2>/dev/null && { say "title ~${i}s"; ok=1; break; }
  sleep 1
done
say "hold title 15s"; sleep 15
PY="$HOME/.venv/autoport/bin/python"; [ -x "$PY" ] || PY="python3"
if [ -f .autoport/xfocus_tap.py ]; then
  say "open menu via START (xfocus 28) x2"
  "$PY" .autoport/xfocus_tap.py 28 >/tmp/x86p-focus.log 2>&1 || true; sleep 3
  "$PY" .autoport/xfocus_tap.py 28 >>/tmp/x86p-focus.log 2>&1 || true
fi
say "hold menu 20s"; sleep 20
kill "$GKPID" 2>/dev/null || true
say "=== harvest ==="
{
echo "# Gmenu-textures x86 PROBES $(date -Is)  title_reached=$ok"
echo
echo "## GK-MWRITE (sp-launch matrix src vs written sp+148) — distinct (src,written)"
grep -aoE 'GK-MWRITE src=-?[0-9]+ written=-?[0-9]+' "$GKLOG" 2>/dev/null | sort -u | head -40
echo
echo "## GK-COMMIT (matrix committed to sprite vec-data v1+20) — distinct (v1,mtx) + mtx histogram"
grep -aoE 'GK-COMMIT v1=[0-9a-f]+ mtx=-?[0-9]+' "$GKLOG" 2>/dev/null | sort -u | head -12
grep -aE 'GK-COMMIT' "$GKLOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
echo
echo "## GK-SPB-IN (matrix entering sp-process-block-2d) — addr + histogram"
grep -aoE 'GK-SPB-IN a=[0-9a-f]+' "$GKLOG" 2>/dev/null | sort -u | head -4
grep -aE 'GK-SPB-IN ' "$GKLOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
echo
echo "## GK-SPB-OUT (matrix leaving sp-process-block-2d) — histogram"
grep -aE 'GK-SPB-OUT ' "$GKLOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
echo
echo "## GK-G1 render_2d_group1 (HUD): chunks/sprites/nz"
grep -aoE 'GK-G1 chunks=[0-9]+ sprites=[0-9]+ nz=[0-9]+ .*' "$GKLOG" 2>/dev/null | sort | uniq -c | sort -rn | head -6
echo
echo "## GK-SPR3 ModeHUD (mode=2) mtx histogram"
grep -aoE 'GK-SPR3 mode=2 .*mtx=-?[0-9]+' "$GKLOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c | head -40
} | tee "$SUM"
say "DONE -> $SUM"
