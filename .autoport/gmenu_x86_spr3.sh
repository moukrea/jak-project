#!/usr/bin/env bash
# gmenu_x86_spr3.sh — x86 reference for the menu sprite render path. Boots build-x86/gk
# to the title (a progress screen), holds, then opens the progress menu via START, and
# harvests the renderer GK-SPR3 dump (mode 1=Mode2D / 2=ModeHUD, mtx index, uhx/uhy,
# px/py). Tells us whether the menu sprites render as ModeHUD (mtx=1..34, uhx/uhy spread)
# on x86 — the correct behavior to compare the device (which showed ONLY Mode2D mtx=0).
# Env: GK (default build-x86/game/gk), ISO (default out/jak1/iso), TAG (label)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK="${GK:-build-x86/game/gk}"
ISO="${ISO:-out/jak1/iso}"
TAG="${TAG:-ourx86}"
OUT=.autoport/reports/Gmenu-textures
GKLOG="$OUT/x86-$TAG-gk.log"
SUM="$OUT/x86-$TAG-spr3.txt"
mkdir -p "$OUT"
# X11 env (auto-detect the mutter Xwayland auth cookie; suffix is per-session)
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  XA=$(ls -t /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
  export XAUTHORITY="${XA:-$HOME/.Xauthority}"
fi
echo "[x86-spr3] GK=$GK ISO=$ISO XAUTHORITY=$XAUTHORITY"
: > "$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup EXIT
echo "[x86-spr3] booting; waiting for title (link finish: logo-loop, up to 200s)"
ok=0
for i in $(seq 1 200); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[x86-spr3] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  if grep -qaE 'link finish: logo-loop' "$GKLOG" 2>/dev/null; then echo "[x86-spr3] title reached ~${i}s"; ok=1; break; fi
  sleep 1
done
[ "$ok" = 1 ] || { echo "[x86-spr3] never reached logo-loop"; tail -20 "$GKLOG"; }
echo "[x86-spr3] hold title 18s (GK-SPR3 accumulates)"; sleep 18
# open the progress menu via START key tap
PY="$HOME/.venv/autoport/bin/python"; [ -x "$PY" ] || PY="python3"
XFOCUS=".autoport/xfocus_tap.py"
if [ -f "$XFOCUS" ]; then
  echo "[x86-spr3] opening menu via START (xfocus_tap 28)"
  "$PY" "$XFOCUS" 28 >/tmp/x86spr3-focus.log 2>&1 || echo "[x86-spr3] xfocus warn (see /tmp/x86spr3-focus.log)"
  sleep 3
  "$PY" "$XFOCUS" 28 >>/tmp/x86spr3-focus.log 2>&1 || true
fi
echo "[x86-spr3] hold menu 18s"; sleep 18
kill "$GKPID" 2>/dev/null || true
echo "[x86-spr3] === harvest ==="
{
echo "# Gmenu-textures x86 GK-SPR3 dump TAG=$TAG $(date -Is)"
echo "GK=$GK"
echo "title_reached=$ok  gk_log_lines=$(wc -l < "$GKLOG")"
echo
echo "## total GK-SPR3 lines + mode histogram (1=Mode2D 2=ModeHUD 3=Mode3D)"
grep -aoE 'GK-SPR3 mode=[0-9]+' "$GKLOG" 2>/dev/null | sort | uniq -c
echo
echo "## (mode,mtx) combos top 30"
grep -aoE 'GK-SPR3 mode=[0-9]+ idx=[0-9]+ px=[^ ]+ py=[^ ]+ pz=[^ ]+ sx=[^ ]+ sy=[^ ]+ mtx=-?[0-9]+' "$GKLOG" 2>/dev/null \
  | sed -E 's/ idx=[0-9]+ px=[^ ]+ py=[^ ]+ pz=[^ ]+ sx=[^ ]+ sy=[^ ]+//' | sort | uniq -c | sort -rn | head -30
echo
echo "## distinct ModeHUD (mode=2) sprites (px py = on-screen, mtx index, uhx/uhy = user-hvdf offset)"
grep -aoE 'GK-SPR3 mode=2 .*' "$GKLOG" 2>/dev/null | sort -u | head -60
echo
echo "## ModeHUD mtx histogram"
grep -aoE 'GK-SPR3 mode=2 .*mtx=-?[0-9]+' "$GKLOG" 2>/dev/null | grep -aoE 'mtx=-?[0-9]+' | sort -t= -k2 -n | uniq -c
echo
echo "## ModeHUD distinct uhx (user-hvdf X offsets — the menu spread)"
grep -aE 'GK-SPR3 mode=2' "$GKLOG" 2>/dev/null | grep -aoE 'uhx=-?[0-9.]+' | sort -u
echo
echo "## ModeHUD distinct px (on-screen X)"
grep -aE 'GK-SPR3 mode=2' "$GKLOG" 2>/dev/null | grep -aoE ' px=-?[0-9.]+' | sort -u
echo
echo "## GMENU-ALLOC (sprite-allocate-user-hvdf returns) if present"
grep -aoE 'GMENU-ALLOC.*' "$GKLOG" 2>/dev/null | sort -u | head -40
} | tee "$SUM"
echo "[x86-spr3] DONE -> $SUM ; full gk log -> $GKLOG"
