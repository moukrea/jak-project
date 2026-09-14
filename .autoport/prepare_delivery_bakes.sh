#!/usr/bin/env bash
# Rafraichir les sidecars avant Gradle, sans toucher aux gardes du pack.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
FR3=out/jak1/fr3
SOURCES=(common/custom_data/MeshConsolidate.cpp common/custom_data/MeshConsolidate.h
  common/custom_data/MeshSubdivide.cpp common/custom_data/MeshSubdivide.h
  common/custom_data/TFrag3Data.cpp common/custom_data/Tfrag3Data.h tools/mesh_audit/main.cpp)
fail(){ echo "[delivery-bake] ECHEC: $*" >&2; exit 1; }
stale(){
  local src
  [ -s "$1" ] || return 0
  for src in "$2" "${SOURCES[@]}"; do
    [ ! -f "$src" ] || [ ! "$src" -nt "$1" ] || return 0
  done
  return 1
}
[ -d "$FR3" ] || fail "$FR3 absent"
levels=()
while IFS= read -r -d '' fr; do
  if stale "${fr%.fr3}.meshweld" "$fr"; then levels+=("$(basename "${fr%.fr3}")"); fi
done < <(find "$FR3" -maxdepth 1 -type f -name '*.fr3' -print0 | sort -z)
# Un sidecar orphelin ne doit pas rester perime jusqu'au refus Gradle.
while IFS= read -r -d '' mw; do
  [ -f "${mw%.meshweld}.fr3" ] || fail "sidecar sans fr3: $mw"
done < <(find "$FR3" -maxdepth 1 -type f -name '*.meshweld' -print0)
echo "[delivery-bake] niveaux_a_cuire=${#levels[@]}"
[ "${#levels[@]}" -gt 0 ] || exit 0
bash .autoport/lib/build_x86.sh --target mesh_audit
mkdir -p .autoport/logs/delivery-bakes
stage=""
cleanup(){
  if [ -n "$stage" ]; then
    rm -f "$stage/$level.fr3" "$stage/$level.meshweld"
    rmdir "$stage" 2>/dev/null || true
  fi
}
trap cleanup EXIT
for level in "${levels[@]}"; do
  mw="$FR3/$level.meshweld"
  log=".autoport/logs/delivery-bakes/$level.txt"
  stage=$(mktemp -d .autoport/logs/delivery-bakes/.stage.XXXXXX)
  ln -s "$PWD/$FR3/$level.fr3" "$stage/$level.fr3"
  build/tools/mesh_audit/mesh_audit --game jak1 --fr3-dir "$stage" --level "$level" \
    --bake --out "$log" --csv "${log%.txt}.csv" > "$log.stdout" 2>&1 \
    || fail "outil refuse $level (voir $log.stdout)"
  # mesh_audit peut rendre 0 apres une ecriture ratee : verifier le resultat.
  grep -qE '^BAKED SIDECARS: 1 written' "$log.stdout" || fail "cuisson non confirmee: $level"
  [ -s "$stage/$level.meshweld" ] || fail "sidecar non produit: $level"
  if stale "$stage/$level.meshweld" "$FR3/$level.fr3"; then fail "sidecar encore perime: $level"; fi
  # Un outil interrompu ne peut plus rendre la destination partielle et fraiche,
  # ce qui ferait sauter la cuisson au prochain tour.
  mv -f "$stage/$level.meshweld" "$mw"
  cleanup
  stage=""
  echo "[delivery-bake] niveau=$level sidecar=$(sha256sum "$mw" | cut -d' ' -f1)"
done
