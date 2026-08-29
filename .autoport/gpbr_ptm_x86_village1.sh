#!/usr/bin/env bash
# gpbr_ptm_x86_village1.sh — phase Gpbr-per-texture-materials: load VILLAGE1 on x86 and harvest the
# per-texture material trace.
#
# WHY x86 AND NOT A DEVICE. Owner 2026-08-29: "la plupart des choses sont testables sur x86 aussi".
# The seven materials that carry PBR maps are all in village1-vis-tfrag, and the thing being proved
# here is a DATA PATH (materials.txt -> PbrMaterialMaps -> the uniforms a draw receives), which is
# identical on both targets. Nothing here is a visual judgement.
#
# WHAT IT PROVES, and it is the phase's success criterion (b) — "two distinct materials render
# measurably different relief in the same scene":
#   [pbrmat] PARAMSRC=... path=...            the file was READ, and from where
#   [pbrmat] <name> relief=... depth=... ...  the values PARSED, one line per material
#   [pbrmat-draw] <name> ns=... hs=... si=... the values a DRAW actually received. Two different
#                                             names with two different triples in one run is the
#                                             measurement; identical triples would mean the knobs
#                                             never reached the GPU, whatever the parse printed.
# It is a RUNTIME TRACE, not a comment: DIRECTIVES rule 0.
#
# Shape borrowed from .autoport/f1_x86_dump.sh (boot to the title attract, connect goalc, intern the
# game symbols with (lt)+(build-game), then warp through a named continue).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
REPO=$(pwd)
GK=${GK:-build-x86/game/gk}
GOALC=${GOALC:-build-x86/goalc/goalc}
ISO=${ISO:-out/jak1/iso}
CONT=${CONT:-village1-hut}
OUT=${OUT:-.autoport/reports/Gpbr-per-texture-materials/x86_village1.log}
HOLD=${HOLD:-60}          # seconds to sit in the level while it streams in
export DISPLAY="${DISPLAY:-:0}"

GKLOG=$(mktemp); GCLOG=$(mktemp); FIFO=$(mktemp -u); mkfifo "$FIFO"
echo "[gpm] gk=$GK continue=$CONT hold=${HOLD}s log=$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem \
  > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null || true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null || true; wait 2>/dev/null || true; rm -f "$FIFO"; }
trap cleanup EXIT

for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[gpm] gk exited during boot"; tail -25 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gpm] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

timeout $((HOLD + 300)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gpm] build-game sent; waiting up to 180s for the symbol intern..."
for i in $(seq 1 180); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gpm] build-game done ~${i}s"; break; }
done
sleep 4

echo "[gpm] warping to continue '$CONT'"
echo "(start 'play (get-continue-by-name *game-info* \"$CONT\"))" >&3
sleep "$HOLD"
exec 3>&-
sleep 3

mkdir -p "$(dirname "$OUT")"
{
  echo "===== [pbrmat] PARSE (materials.txt was read, and from where) ====="
  grep -a "\[pbrmat\] PARAMSRC" "$GKLOG" || echo "(none)"
  echo
  echo "===== [pbrmat] PARSED VALUES, one line per authored material ====="
  grep -a "\[pbrmat\] " "$GKLOG" | grep -av PARAMSRC || echo "(none)"
  echo
  echo "===== [pbrmat-draw] VALUES A DRAW ACTUALLY RECEIVED ====="
  grep -a "\[pbrmat-draw\]" "$GKLOG" || echo "(none)"
  echo
  echo "===== level markers ====="
  grep -aE "link finish: (logo|village1)|custom pbr material registered" "$GKLOG" | tail -30
} > "$OUT"
cat "$OUT"
echo "[gpm] -> $OUT   (raw gk log kept at $GKLOG)"
cp "$GKLOG" "$(dirname "$OUT")/x86_village1_gk_raw.log" 2>/dev/null || true
