#!/usr/bin/env bash
# ==================================================================================================
# ROUND 31 — grade EVERY MESH OF EVERY LEVEL, both tiers, from the SHIPPED sidecars.
#
# Owner scope: "pars du principe que absolument tous les mesh auront du PBR (tesselation ou parallax
# suivant ce qui est activé par l'utilisateur)". So the perimeter is the whole game, not the seven
# materials that happen to ship a _height.png today, and the coverage number has to be
# covered == existing per level. --all-textures applies the SYNTHETIC CHECKER to every material,
# which is exactly what the debug material is for: a perfectly known height field, hence an exact
# expected result on a mesh whose art has not landed yet.
#
# --use-sidecar, not the live pass, on purpose: the graded geometry must be the geometry the RUNTIME
# opens. Four rounds of this project were lost to measuring one artefact and shipping another.
# ==================================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT=${1:-.autoport/reports/Grecharged-pbr-realtime-fusion/r31}
JOBS=${2:-4}
BIN=./build/tools/tess_sign/tess_sign
mkdir -p "$OUT/levels"

[ -x "$BIN" ] || { echo "missing $BIN — cmake --build build --target tess_sign"; exit 1; }

echo "[r31-sweep] $(date -Is) binary $(md5sum $BIN | cut -c1-16) jobs=$JOBS out=$OUT"

run_one() {
  local f="$1" out="$2"
  local L
  L=$(basename "$f" .fr3)
  # --use-sidecar: grade the baked artefact, not a live re-derivation of it.
  ./build/tools/tess_sign/tess_sign \
      --fr3 "$f" --use-sidecar --all-textures \
      --out "$out/levels/tess_sign_$L.txt" \
      --csv "$out/levels/tess_sign_$L.csv" \
      > "$out/levels/tess_sign_$L.log" 2>&1
  echo "[r31-sweep] $L rc=$? $(grep -aoE 'A_sign OVERALL *: *[0-9.]+%' "$out/levels/tess_sign_$L.txt" 2>/dev/null | head -1)"
}
export -f run_one

ls out/jak1/fr3/*.fr3 | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} "$OUT"

echo "[r31-sweep] done $(date -Is)"
